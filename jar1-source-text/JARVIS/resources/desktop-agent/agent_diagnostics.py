"""Explicit local developer opt-in; disabled in normal installations.

Place diagnostic-domain.txt next to this module to trace one public web domain.
No screenshots, credentials, hidden input values or typed text are written.
"""
import hashlib
import json
import tempfile
import time
from pathlib import Path
from urllib.parse import urlsplit


def record(obs, *, action=None, error=None):
    flag = Path(__file__).with_name('diagnostic-domain.txt')
    if not flag.is_file():
        return
    try:
        domain = flag.read_text(encoding='utf-8').strip().lower()
        page = json.loads(obs.text)
        host = (urlsplit(page.get('url','')).hostname or '').lower()
        if not domain or not (host==domain or host.endswith('.'+domain)):
            return
        safe_action = None
        if action is not None:
            safe_action = dict(action, args=dict(action.get('args',{})))
            if safe_action.get('action')=='type':
                text = safe_action['args'].pop('text','')
                safe_action['args']['text_length'] = len(text)
                safe_action['args']['text_hash'] = hashlib.sha256(text.encode()).hexdigest()
        output = Path(tempfile.gettempdir())/'jarvis-agent'/'diagnostic-trace.jsonl'
        output.parent.mkdir(exist_ok=True)
        with output.open('a',encoding='utf-8') as stream:
            stream.write(json.dumps(dict(time=time.time(),page=page,action=safe_action,
                                        error=str(error)[:600] if error else None),ensure_ascii=False)+'\n')
    except (OSError,ValueError,TypeError):
        pass  # Diagnostics must not change execution or cause retries.
