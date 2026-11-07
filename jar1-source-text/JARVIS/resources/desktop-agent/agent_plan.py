"""Bounded typed plans and local task checkpoints. Never executes generated code."""
from __future__ import annotations

from dataclasses import dataclass
import copy
import hashlib
import json

from agent_runtime import ActionError

PLAN_ACTIONS = {'click', 'type', 'shortcut', 'scroll', 'switch', 'launch',
                'browser_open', 'open_url', 'desktop', 'skill'}


def prepare_sequence(args, observation):
    steps = args.get('steps')
    if not isinstance(steps, list) or not 2 <= len(steps) <= 6:
        raise ActionError('sequence требует от двух до шести шагов')
    if len(json.dumps(steps, ensure_ascii=False)) > 8000:
        raise ActionError('Слишком большая последовательность')
    prepared = []
    for step in steps:
        if (not isinstance(step, dict) or step.get('action') not in PLAN_ACTIONS
                or not isinstance(step.get('args'), dict)):
            raise ActionError('Недопустимый шаг последовательности')
        # Every step still goes through perform(), including host approvals.
        if step.get('risk', 'none') not in ('none', 'delete', 'send', 'overwrite', 'system'):
            raise ActionError('Неизвестный риск шага')
        action = copy.deepcopy(step)
        identifiers = []
        if action['action'] in ('click', 'type'):
            identifiers.append(str(action['args'].get('id', '')))
        elif action['action'] == 'skill':
            if action['args'].get('name') == 'search':
                identifiers.append(str(action['args'].get('id', '')))
            elif action['args'].get('name') == 'fill_fields':
                fields = action['args'].get('fields')
                if not isinstance(fields, list) or not all(isinstance(f, dict) for f in fields):
                    raise ActionError('Некорректные поля последовательности')
                identifiers.extend(str(f.get('id', '')) for f in fields)
            else:
                raise ActionError('Неизвестный навык последовательности')
        expected = {}
        for identifier in identifiers:
            target = observation.targets.get(identifier)
            if target is None:
                raise ActionError('Следующая цель ещё не наблюдалась; сначала получи новое состояние')
            expected[identifier] = {k: target.get(k) for k in
                ('name', 'type', 'input_type', 'url', 'search', 'search_submit', 'result_rank')}
        prepared.append((action, expected))
    return prepared


def check_sequence_targets(expected, original, current):
    if original.document != current.document or original.window != current.window:
        raise ActionError('Последовательность остановлена после смены документа или окна; выполненные шаги не повторять')
    for identifier, identity in expected.items():
        target = current.targets.get(identifier)
        if not target or target.get('disabled') or any(target.get(k) != v for k, v in identity.items()):
            raise ActionError('Следующая цель последовательности изменилась; выполненные шаги не повторять')
        if not original.document and target.get('rect') != original.targets[identifier].get('rect'):
            raise ActionError('Нативный элемент переместился; требуется новый план')


@dataclass
class TaskProgress:
    revision: int = 0
    stage: str = 'observing'
    completed: int = 0
    plan_completed: int = 0
    plan_total: int = 0
    missing: str = ''
    waiting: bool = False

    def corrected(self):
        self.revision += 1
        self.missing = ''
        self.stage = 'replanning'

    def summary(self):
        return dict(revision=self.revision, stage=self.stage, completed=self.completed,
                    plan_completed=self.plan_completed, plan_total=self.plan_total,
                    missing=self.missing[:400], waiting=self.waiting)

    def metrics(self):
        # Free text is only used in the in-memory prompt, never diagnostics.
        return {k: v for k, v in self.summary().items() if k != 'missing'}


class SearchMemory:
    """Process-local field descriptors. No queries, personal text, URLs or coordinates.

    Two independently successful executions are required before reuse. It only
    resolves a field for an explicit search skill; it never invents user intent.
    """
    def __init__(self):
        self.entries = {}

    @staticmethod
    def key(obs):
        from urllib.parse import urlsplit
        try:
            url = urlsplit(json.loads(obs.text)['url'])
            return hashlib.sha256((url.scheme+'://'+url.netloc+url.path).encode()).hexdigest()
        except (ValueError, KeyError, TypeError):
            return None

    def remember(self, obs, target):
        key = self.key(obs)
        # Store only standard generic search labels, never an arbitrary page label.
        from agent_runtime import is_search_field
        if not key or not is_search_field(target.get('name', '')):
            return
        identity = {k: target.get(k) for k in ('name', 'type', 'input_type')}
        old = self.entries.get(key)
        count = min(3, old[1]+1) if old and old[0] == identity else 1
        if len(self.entries) >= 64 and key not in self.entries:
            self.entries.pop(next(iter(self.entries)))
        self.entries[key] = (identity, count)

    def resolve(self, obs):
        old = self.entries.get(self.key(obs))
        if not old or old[1] < 2:
            return None
        matches = [identifier for identifier, target in obs.targets.items()
                   if target.get('search') is True and not target.get('disabled')
                   and all(target.get(k) == v for k, v in old[0].items())]
        return matches[0] if len(matches) == 1 else None
