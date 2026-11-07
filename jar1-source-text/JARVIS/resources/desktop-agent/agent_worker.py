"""Single-flight stdio worker owned by Jarvis's Windows Job Object.

Idle is a blocking queue read. All UIA/Playwright use stays on the same thread.
Fresh channels, controllers and credentials for every task; no pending task queue.
"""
from __future__ import annotations
import json
import os
import queue
import sys
import threading
from pathlib import Path

CONFIG_KEYS = {
    'JARVIS_AGENT_KEY', 'JARVIS_AGENT_MODEL', 'JARVIS_AGENT_BASE', 'JARVIS_AGENT_CANCEL_FILE',
    'JARVIS_AGENT_VISION', 'JARVIS_AGENT_VISION_KEY', 'JARVIS_AGENT_VISION_MODEL',
    'JARVIS_AGENT_VISION_BASE', 'JARVIS_AGENT_BROWSER_PORT',
    'JARVIS_AGENT_INPUT_TOKEN_LIMIT', 'JARVIS_AGENT_OUTPUT_TOKEN_LIMIT',
}


class WorkerResources:
    def __init__(self):
        self.desktop = None
        self.pools = {}
        self.tasks = 0

    def transport(self, url):
        from agent_transport import PooledOpener
        if url not in self.pools:
            if len(self.pools) >= 4:
                self.pools.pop(next(iter(self.pools))).close()
            self.pools[url] = PooledOpener(url)
        return self.pools[url]

    def adapter(self, browser_first, factory):
        if self.desktop is None:
            # Native initialization remains lazy. Existing modules and UIA service
            # are reused after the first task that needs Windows controls.
            self.desktop = factory(browser_first=True)
        self.desktop.reset_task(browser_first=browser_first)
        self.tasks += 1
        return self.desktop

    def close(self):
        if self.desktop is not None:
            self.desktop.close()
        for pool in self.pools.values():
            pool.close()

    def release_task(self):
        # Bound guards reference the entire Controller (including dialogue and
        # receipts). Drop them at completion, keeping only native services,
        # browser connections and generic search descriptors warm.
        if self.desktop is not None:
            from agent_runtime import Stopped
            def inactive():
                raise Stopped('Нет активной задачи')
            self.desktop.set_action_guard(inactive)
            self.desktop.set_browser_broker(inactive)
            native = getattr(self.desktop, '_desktop', None)
            if native is not None and hasattr(native, 'delegate'):
                native.delegate.desktop_state = None


def serve(stream=None, output=None, runner=None):
    from agent_runtime import Channel, task_stop_requested
    import run_task
    stream, output = stream or sys.stdin, output or sys.stdout
    for pipe in (stream, output):
        if hasattr(pipe, 'reconfigure'):
            pipe.reconfigure(encoding='utf-8')
    runner = runner or run_task._run_agent
    requests = queue.Queue(maxsize=1)
    lock = threading.Lock()
    active = [None]
    eof = threading.Event()
    resources = WorkerResources()
    bootstrap_seconds = os.environ.pop('JARVIS_AGENT_BOOTSTRAP_SECONDS', '0')
    completed_tasks = 0

    def write(prefix, value):
        output.write(prefix + json.dumps(value, ensure_ascii=False) + '\n')
        output.flush()

    def read():
        try:
            for line in stream:
                if len(line) > 40000:
                    continue
                try:
                    message = json.loads(line)
                except (ValueError, TypeError):
                    continue
                if not isinstance(message, dict):
                    continue
                with lock:
                    if message.get('type') == 'run':
                        if active[0] is not None or requests.full():
                            continue  # No background queue of actions that can run unexpectedly.
                        task_id, path, config = message.get('task_id'),message.get('path'),message.get('config')
                        if not isinstance(task_id,str) or not isinstance(path,str) or not isinstance(config,dict):
                            continue
                        cancel_path = config.get('JARVIS_AGENT_CANCEL_FILE','')
                        cancel_path = cancel_path if isinstance(cancel_path,str) else ''
                        channel = Channel(emit=lambda event,tid=task_id:write('JARVIS_AGENT_EVENT ',dict(event,task_id=tid)),
                            cancel=lambda path=cancel_path:eof.is_set() or bool(path and Path(path).exists()))
                        # Bind as soon as the request is accepted. Corrections
                        # spoken during initialization must not disappear.
                        active[0] = (task_id, channel)
                        message['_channel'] = channel
                        requests.put_nowait(message)
                    elif active[0] is not None:
                        task_id, channel = active[0]
                        if message.get('task_id', task_id) != task_id:
                            continue
                        if task_stop_requested(message.get('text', '')):
                            channel.stop_requested = True
                        else:
                            (channel.control if message.get('type') == 'browser_ready' else
                             channel.instructions if message.get('type') == 'instruction' else channel.answers).put(message)
        finally:
            eof.set()
            with lock:
                if active[0] is not None:
                    active[0][1].stop_requested = True
            try:
                requests.put_nowait(None)
            except queue.Full:
                pass

    threading.Thread(target=read, name='jarvis-worker-input', daemon=True).start()
    try:
        while not eof.is_set():
            try:
                request = requests.get(timeout=300)
            except queue.Empty:
                break  # Release large native imports after five minutes idle.
            if request is None:
                break
            task_id = request.get('task_id')
            path, config = request.get('path'), request.get('config')
            if not isinstance(task_id, str) or not isinstance(path, str) or not isinstance(config, dict):
                continue
            # Parent is the only writer. Configuration never becomes persisted state.
            for key in CONFIG_KEYS:
                os.environ.pop(key, None)
            for key, value in config.items():
                if key in CONFIG_KEYS and isinstance(value, str):
                    os.environ[key] = value
            os.environ['JARVIS_AGENT_BOOTSTRAP_SECONDS'] = bootstrap_seconds if completed_tasks == 0 else '0'
            channel = request['_channel']
            original_emit = run_task._emit
            result = []
            run_task._emit = lambda ok, text: result.append(dict(ok=ok, text=text, task_id=task_id))
            try:
                runner(path, channel=channel, resources=resources)
            except Exception:
                result[:] = [dict(ok=False, text='Ошибка рабочего процесса; результат не подтверждён', task_id=task_id)]
            finally:
                run_task._emit = original_emit
                resources.release_task()
                with lock:
                    active[0] = None
                for key in CONFIG_KEYS:
                    os.environ.pop(key, None)
                # A correction/answer can never leak into the next task's channel.
                channel.stop_requested = True
                channel.output = lambda event: None
            # Completion is published only after cleanup. A new run received
            # immediately by the GUI cannot race the previous task's channel.
            write('JARVIS_AGENT_RESULT ', result[-1] if result else dict(
                ok=False, text='Агент завершился без результата', task_id=task_id))
            completed_tasks += 1
    finally:
        resources.close()
    return 0
