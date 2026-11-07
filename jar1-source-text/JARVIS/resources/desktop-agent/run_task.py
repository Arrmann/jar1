# JARVIS desktop-agent bootstrap. Policy and execution live in agent_runtime.py.

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path


def _root() -> str:
    machine = os.path.join(os.environ.get("PROGRAMDATA", ""), "JARVIS", "windows-use", "venv", "Scripts", "python.exe")
    base = os.environ.get("PROGRAMDATA") if os.path.isfile(machine) else os.environ.get("LOCALAPPDATA")
    base = base or os.getcwd()
    path = os.path.join(base, "JARVIS", "windows-use")
    os.makedirs(path, exist_ok=True)
    return path


def _venv_python() -> str:
    return os.path.join(_root(), "venv", "Scripts", "python.exe")


def _in_venv() -> bool:
    return os.path.normcase(os.path.abspath(sys.executable)) == os.path.normcase(
        os.path.abspath(_venv_python())
    )


def _emit(ok: bool, text: str) -> None:
    line = json.dumps({"ok": ok, "text": text}, ensure_ascii=False)
    print("JARVIS_AGENT_RESULT " + line, flush=True)


def _ensure_venv() -> None:
    py = _venv_python()
    venv_dir = os.path.join(_root(), "venv")
    if not os.path.isfile(py):
        print("JARVIS_AGENT_STATUS installing", flush=True)
        boot = os.path.join(_root(), "bootstrap")
        os.makedirs(boot, exist_ok=True)
        subprocess.check_call(
            [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--target",
                boot,
                "virtualenv==21.14.6",
            ]
        )
        creator = (
            "import sys\n"
            "sys.path.insert(0, sys.argv[1])\n"
            "from virtualenv import cli_run\n"
            "cli_run([sys.argv[2], '--python', sys.executable])\n"
        )
        subprocess.check_call([sys.executable, "-c", creator, boot, venv_dir])
    probe = subprocess.run(
        [py, "-c", "from importlib.metadata import version; from importlib.util import find_spec; from pathlib import Path; import sys; "
         "pins=[line.strip().split('==') for line in Path(sys.argv[1]).read_text().splitlines() if '==' in line]; "
         "assert all(version(name)==pin for name,pin in pins); "
         "assert find_spec('windows_use') is not None and find_spec('playwright') is not None",
         str(Path(__file__).with_name("requirements.lock"))],
        capture_output=True,
        text=True,
        env=_child_env(),
        timeout=20,
    )
    if probe.returncode != 0:
        print("JARVIS_AGENT_STATUS installing", flush=True)
        print('JARVIS_AGENT_EVENT ' + json.dumps({"status": "starting", "message": "Устанавливаю проверенные компоненты агента; первый запуск может занять несколько минут"}, ensure_ascii=False), flush=True)
        subprocess.check_call(
            [
                py,
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "-r",
                str(Path(__file__).with_name("requirements.lock")),
            ]
        )


def _child_env() -> dict:
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    env.pop("PYTHONHOME", None)
    env["PYTHONNOUSERSITE"] = "1"
    env["ANONYMIZED_TELEMETRY"] = "false"
    env["DO_NOT_TRACK"] = "1"
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    # Jarvis has its own model transport/accounting. Dependency imports must not
    # download LiteLLM's optional price catalog or retry the network at startup.
    env["LITELLM_LOCAL_MODEL_COST_MAP"] = "True"
    return env


def _lower_limit(name, default, minimum):
    raw = os.environ.get(name)
    if raw is None:
        return default
    value = int(raw)
    if not minimum <= value <= default:
        raise ValueError(f'{name}: допускается только уменьшение лимита до {minimum}..{default}')
    return value


def _save_metrics(path, api, controller, outcome, question_types, setup_timings):
    if api is None:
        return
    try:
        cycles = controller.cycle_snapshot() if controller is not None and hasattr(controller,'cycle_snapshot') else []
        metrics={'model':api.model,'requests':api.requests,'input_tokens':api.input,'output_tokens':api.output,
            'reserved_tokens':api.reserved_input,'cost_usd':api.cost,'question_types':list(question_types),
            'timings':dict(getattr(controller,'timings',{})) | setup_timings,
            'action_trace':getattr(controller,'trace',[]),'proposal_trace':getattr(controller,'proposal_trace',[]),
            'verification_trace':getattr(controller,'verification_trace',[]),
            'model_call_trace':getattr(api,'call_trace',[]),
            'task_state':controller.progress.metrics() if controller is not None and hasattr(controller,'progress') else {},
            'outcome':outcome,'cycle_trace':cycles,
            'executed_actions':[r['action'] for r in (controller.receipts if controller else [])]}
        target=Path(path).with_suffix('.metrics.json')
        temporary=target.with_suffix('.json.tmp')
        temporary.write_text(json.dumps(metrics),encoding='utf-8')
        temporary.replace(target)
    except (OSError,ValueError,AttributeError):
        pass  # Diagnostics cannot interfere with task execution.


def _run_agent(task_path=None, *, channel=None, resources=None) -> int:
    task_began = time.monotonic()
    from agent_runtime import ActionError, Channel, Controller, Limits, Model, Stopped
    from agent_desktop import WindowsDesktop

    cancel_path = os.environ.get("JARVIS_AGENT_CANCEL_FILE", "")
    channel = channel or Channel(sys.stdin, cancel=lambda: bool(cancel_path and Path(cancel_path).exists()))
    task_path = task_path or sys.argv[1]
    adapter = None
    api = controller = None
    outcome = 'failed'
    question_types = []
    setup_timings = {}
    try:
        setup_timings['bootstrap_seconds'] = float(os.environ.get('JARVIS_AGENT_BOOTSTRAP_SECONDS','0'))
    except ValueError:
        setup_timings['bootstrap_seconds'] = 0
    report = channel.output
    def report_event(event):
        if event.get('question'):
            question_types.append('approval' if event['question'].get('approval') else 'clarification')
        report(event)
        _save_metrics(task_path,api,controller,outcome,question_types,setup_timings)
    channel.output = report_event
    try:
        task = Path(task_path).read_text(encoding="utf-8").strip()
        if not 3 <= len(task) <= 1500:
            raise ValueError("Задача должна содержать от 3 до 1500 символов")
        key = os.environ.get("JARVIS_AGENT_KEY", "").strip()
        if not key:
            raise ValueError("Нет API-ключа агента")
        model = os.environ.get("JARVIS_AGENT_MODEL", "deepseek-flash")
        base = os.environ.get("JARVIS_AGENT_BASE", "https://api.deepseek.com/v1")
        limits = Limits()
        limits.input_tokens = _lower_limit('JARVIS_AGENT_INPUT_TOKEN_LIMIT',limits.input_tokens,1000)
        limits.output_tokens = _lower_limit('JARVIS_AGENT_OUTPUT_TOKEN_LIMIT',limits.output_tokens,600)
        api = Model(key, model, base, limits, channel)
        if resources is not None:
            api.opener = resources.transport(api.url)
        api.text_vision = os.environ.get("JARVIS_AGENT_VISION") == "1"
        vision_key = os.environ.pop("JARVIS_AGENT_VISION_KEY", "")
        vision_model = os.environ.get("JARVIS_AGENT_VISION_MODEL", "")
        vision_base = os.environ.get("JARVIS_AGENT_VISION_BASE", "")
        if vision_key and vision_model and vision_base and not api.text_vision:
            api.vision_model = Model(vision_key, vision_model, vision_base, limits, channel)
            if resources is not None:
                api.vision_model.opener = resources.transport(api.vision_model.url)
        os.environ.pop("JARVIS_AGENT_KEY", None)
        began = time.monotonic()
        from agent_skills import browser_first_task
        adapter = (resources.adapter(browser_first_task(task), WindowsDesktop) if resources is not None
                   else WindowsDesktop(browser_first=browser_first_task(task)))
        setup_timings['adapter_init_seconds'] = round(time.monotonic()-began,3)
        controller = Controller(adapter, api, channel, limits=limits,
                            vision=api.vision_model is not None or os.environ.get("JARVIS_AGENT_VISION") == "1")
        outcome = 'running'
        _save_metrics(task_path,api,controller,outcome,question_types,setup_timings)
        answer = controller.run(task)
        outcome = 'completed'
        _emit(True, answer)
        return 0
    except Stopped as exc:
        outcome = 'repeat_limit' if str(exc).startswith('Остановил повторяющееся') else 'stopped'
        _emit(False, str(exc))
        return 1
    except Exception as exc:
        message = str(exc) if isinstance(exc, (ActionError, ValueError)) else "Ошибка агента: " + type(exc).__name__
        _emit(False, message[:800])
        return 1
    finally:
        # Local counters only. Never save screenshots, prompts, field contents, task text or credentials.
        if api is not None:
            try:
                setup_timings['task_total_seconds'] = round(time.monotonic()-task_began,3)
                setup_timings['clock_origin'] = 'accepted_text_after_speech_recognition'
                if controller is not None and hasattr(controller,'finish_cycle'):
                    controller.finish_cycle()
                _save_metrics(task_path,api,controller,outcome,question_types,setup_timings)
            except (OSError, ValueError, AttributeError):
                pass
        if adapter is not None and resources is None:
            adapter.close()
        if resources is None and api is not None:
            for selected in (api, getattr(api, 'vision_model', None)):
                if selected is not None and hasattr(getattr(selected, 'opener', None), 'close'):
                    selected.opener.close()


def main() -> int:
    if not _in_venv():
        began = time.monotonic()
        try:
            _ensure_venv()
        except Exception as exc:  # noqa: BLE001
            _emit(False, f"Не удалось установить компоненты агента: {exc}"[:400])
            return 1
        env = _child_env()
        env['JARVIS_AGENT_BOOTSTRAP_SECONDS'] = str(round(time.monotonic()-began,3))
        proc = subprocess.run(
            [_venv_python(), os.path.abspath(__file__), *sys.argv[1:]],
            env=env,
        )
        return proc.returncode
    if sys.argv[1:] == ['--worker']:
        from agent_worker import serve
        return serve()
    return _run_agent()


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(code)
