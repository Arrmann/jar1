"""Windows executor: UIA first, cropped vision fallback; no model-generated code."""
from __future__ import annotations

import ctypes
import hashlib
import io
import json
import logging
import os
import re
import subprocess
import time
import winreg
from pathlib import Path

from agent_runtime import ActionError, ExecutionUncertain, Stopped, ObservationChanged, Observation, SENSITIVE, SYSTEM_COMMAND, bound_observation_text, clean_env, is_search_field, is_search_button, protected_path, safe_url


class WindowsDesktop:
    def __init__(self, *, browser_first=False):
        self._desktop = self._uia = None
        self._browser_first = browser_first
        if not browser_first:
            self._load_native()
        self.browser = None
        self.browser_mode = False
        self._browser_attachment_checked = False
        self._action_guard = lambda: None
        from agent_apps import AppCatalog
        self.apps = AppCatalog()

    def _load_native(self):
        # Importing windows_use also imports LiteLLM. Its optional remote price
        # catalog is unrelated to our API calls and must not delay UI startup.
        os.environ['LITELLM_LOCAL_MODEL_COST_MAP'] = 'True'
        from windows_use.agent.desktop.service import Desktop
        import windows_use.uia as uia
        logging.disable(logging.CRITICAL)
        # Keep physical pixels consistent on mixed-DPI monitors, before COM/UIA.
        ctypes.windll.user32.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
        self._desktop, self._uia = Desktop(use_vision=False), uia
        self._active_tree_only(self._desktop)
        from agent_native import ForegroundDesktop
        self._desktop = ForegroundDesktop(self._desktop)

    @property
    def desktop(self):
        if self._desktop is None:
            self._load_native()
        return self._desktop

    @desktop.setter
    def desktop(self,value):
        self._desktop = value

    @property
    def uia(self):
        if getattr(self,'_uia',None) is None:
            self._load_native()
        return self._uia

    @uia.setter
    def uia(self,value):
        self._uia = value

    def set_action_guard(self, guard):
        self._action_guard = guard
        if self.browser is not None:
            self.browser.guard = guard

    def set_browser_broker(self, broker):
        self._browser_broker = broker
        if self.browser is not None:
            self.browser.broker = broker

    def prepare_task(self, task):
        from agent_start import opening_action
        action=opening_action(task)
        if action and action['action']=='browser_open':
            url=action['args']['url']
            if '?' not in url and re.search(r'найди|найти|поищи|прочитай|включи|find|search',task,re.I):
                return None  # Let the model navigate directly to a known target page.
        if action and action['action']=='launch':
            try:self._app_path(action['args']['name'])
            except ActionError:return None  # Unknown/ambiguous app stays a model decision.
        return action

    def inspect(self, query, offset, *, scope='elements'):
        if self.browser_mode:
            return self.browser.observe(query=query,offset=offset,scope=scope)
        return None

    def reset_task(self, *, browser_first):
        """Reuse native service, never task-local plans, permissions or guards."""
        self._action_guard = lambda: (_ for _ in ()).throw(Stopped('Нет активной задачи'))
        port = os.environ.get('JARVIS_AGENT_BROWSER_PORT', '')
        if self.browser is not None and port and str(getattr(self.browser, 'port', '')) != port:
            self.browser.close()
            self.browser = None
        self.browser_mode = bool(browser_first and self.browser is not None)
        self._browser_first = browser_first
        self._browser_attachment_checked = False

    @staticmethod
    def _active_tree_only(desktop):
        original = desktop.tree.get_state
        def read(active_handle, other_handles):
            # Background windows remain selectable by title; their control trees are never needed.
            return original(active_handle, [])
        desktop.tree.get_state = read

    @staticmethod
    def _private(node):
        try:
            if node.metadata.get("is_password") or SENSITIVE.search(node.name or ""):
                return True
            if node.control:
                try:
                    return bool(node.control.CachedIsPassword)
                except Exception:
                    return bool(node.control.IsPassword)
            return False
        except Exception:
            return True

    def observe(self, image=False):
        if self.browser_mode:
            return self.browser.observe(image=image)
        if getattr(self,'_browser_first',False):
            # The GUI owns a persistent browser. Read its existing tab instead
            # of telling the planner that no browser exists on every new task.
            if not getattr(self,'_browser_attachment_checked',False):
                self._browser_attachment_checked = True
                port = os.environ.get('JARVIS_AGENT_BROWSER_PORT','')
                if port.isdigit() and 1 <= int(port) <= 65535:
                    from agent_browser import ManagedBrowser
                    browser = ManagedBrowser(guard=self._action_guard)
                    try:
                        browser._start()
                        observation = browser.observe(image=image)
                    except Exception:
                        browser.close()
                        raise ActionError('Не удалось прочитать открытую вкладку браузера Jarvis; запуск не считается выполнением задачи.') from None
                    self.browser, self.browser_mode = browser, True
                    return observation
            text=json.dumps({'active_window':'Управляемая веб-вкладка пока не открыта. Используй browser_open; для окон Windows сначала desktop.',
                             'window':0,'windows':[]},ensure_ascii=False)
            return Observation(text,hashlib.sha256(text.encode()).hexdigest())
        state = self.desktop.get_state()
        active = state.active_window
        if active is None:
            windows=[{'id':'w'+str(w.handle),'name':w.name[:120]} for w in state.windows
                     if w.handle and not SENSITIVE.search(w.name)]
            text=json.dumps({'active_window':'Рабочий стол: активного окна приложения нет. '
                'Открой нужное приложение через launch/browser_open или выбери доступное окно через switch.',
                'window':0,'windows':windows},ensure_ascii=False)
            return Observation(text,hashlib.sha256(text.encode()).hexdigest())
        if ctypes.windll.user32.GetForegroundWindow() != active.handle:
            raise ObservationChanged("Окно сменилось во время чтения элементов")
        if SENSITIVE.search(active.name):
            raise ActionError("Окно может содержать пароли или коды доступа; выбери другое окно")
        box = active.bounding_box
        own_window = bool(re.fullmatch(r"jarvis|джарвис", active.name.strip(), re.I))
        rect = (box.left, box.top, box.right, box.bottom)
        targets, rows, hidden = {}, [], []
        for index, node in enumerate((state.tree_state.interactive_nodes or [])[:300]):
            b = node.bounding_box
            # Only expose elements inside the active window. Background windows
            # are selectable explicitly but their content is never sent.
            if not (box.left <= node.center.x < box.right and box.top <= node.center.y < box.bottom):
                continue
            if self._private(node):
                hidden.append((b.left, b.top, b.right, b.bottom))
                continue
            key = "e" + str(index)
            data = {"name": (node.name or "")[:180], "type": node.control_type,
                    "rect": [b.left, b.top, b.right, b.bottom]}
            if re.search(r'edit|textbox|text box',str(node.control_type),re.I):
                data['search']=is_search_field(node.name)
            if re.search(r'button',str(node.control_type),re.I):
                data['search_submit']=is_search_button(node.name)
            if node.control and re.search(r'edit|textbox|text box', str(node.control_type), re.I):
                try:
                    # Only emptiness, never the field's value, is exposed to the planner.
                    value = node.control.GetValuePattern().Value
                    if isinstance(value, str):
                        data['empty'] = value == ''
                    data['focused'] = bool(node.control.HasKeyboardFocus)
                except Exception:
                    pass
            targets[key] = dict(data, node=node)
            if node.control:
                try:
                    targets[key]['_native_name']=str(node.control.CachedName or '')[:180]
                except Exception:
                    pass
            rows.append(key + " " + json.dumps(data, ensure_ascii=False))
        windows = [{"id": "w" + str(w.handle), "name": w.name[:120]} for w in state.windows]
        text = json.dumps({"active_window": active.name[:200], "window": active.handle,
                           "rect": rect, "windows": windows}, ensure_ascii=False)
        text += "\nЭлементы текущего окна:\n" + "\n".join(rows)
        if own_window:
            targets = {}
            text = json.dumps({"active_window": "JARVIS — собственное окно помощника; выбери другое окно",
                               "window": active.handle, "windows": windows}, ensure_ascii=False)
        if not own_window and state.tree_state.dom_informative_nodes:
            # Visible browser text, not the complete desktop/document.
            content = [str(getattr(n, "text", getattr(n, "content", "")))[:250]
                       for n in state.tree_state.dom_informative_nodes[:35]
                       if not SENSITIVE.search(str(getattr(n, "text", getattr(n, "content", ""))))]
            text += "\nТекст страницы: " + " | ".join(content)
        text = text[:18000]
        raw_text = text
        fingerprint = hashlib.sha256(text.encode()).hexdigest()
        text = bound_observation_text(text)
        jpeg = None
        if image and not own_window:
            if ctypes.windll.user32.GetForegroundWindow() != active.handle:
                raise ObservationChanged("Рабочее окно сменилось перед снимком")
            from PIL import ImageGrab, ImageDraw
            shot = ImageGrab.grab(bbox=rect, all_screens=True)
            draw = ImageDraw.Draw(shot)
            for left, top, right, bottom in hidden:
                draw.rectangle((max(0, left-box.left), max(0, top-box.top),
                                min(shot.width, right-box.left), min(shot.height, bottom-box.top)), fill="black")
            shot.thumbnail((1440, 1000))
            stream = io.BytesIO()
            shot.convert("RGB").save(stream, "JPEG", quality=72)
            jpeg = stream.getvalue()
            if ctypes.windll.user32.GetForegroundWindow() != active.handle:
                raise ObservationChanged("Окно сменилось во время снимка; изображение отброшено")
            text += "\nСнимок рабочего окна; координаты click_point нормализованы 0..1000 внутри него."
        return Observation(text, fingerprint, image=jpeg, targets=targets,
                           window=active.handle, rect=rect,raw_text=raw_text,window_pid=getattr(active,'process_id',0))

    def recovery_observation(self):
        # A moving foreground must not discard task context. Window enumeration
        # needs no full accessibility tree and supplies no stale click targets.
        windows,_=self.desktop.get_windows()
        choices=[{'id':'w'+str(w.handle),'name':w.name[:120]} for w in windows
                 if w.handle and not SENSITIVE.search(w.name)]
        if not choices:
            raise ObservationChanged('Пока нет доступных окон для продолжения')
        text=json.dumps({'active_window':'Окно меняется. Выбери рабочее окно через switch или открой нужное приложение; задача продолжается.',
            'window':0,'windows':choices},ensure_ascii=False)
        self.desktop.desktop_state.windows=windows
        return Observation(text,hashlib.sha256(text.encode()).hexdigest())

    def validate(self, name, args, obs):
        if self.browser_mode and name not in ("file", "shell", "browser_open", "launch", "apps", "open_url", "desktop"):
            return self.browser.validate(name, args, obs)
        if name in ("click", "type"):
            if str(args.get("id", "")) not in obs.targets:
                raise ActionError("Элемент отсутствует в текущем наблюдении")
        if name == "click":
            if args.get("button", "left") not in ("left", "right") or args.get("count", 1) not in (1, 2):
                raise ActionError("Недопустимый клик")
        if name == "type":
            if not isinstance(args.get("text"), str) or len(args["text"]) > 4000:
                raise ActionError("Текст должен быть строкой до 4000 символов")
            if type(args.get("clear", False)) is not bool:
                raise ActionError("clear должен быть boolean")
            if SENSITIVE.search(obs.targets[str(args["id"])]["name"]):
                raise ActionError("Ввод секретов недоступен агенту")
        if name == "click_point":
            if obs.image is None or any(type(args.get(k)) not in (int, float) or
                                       not 0 <= args[k] <= 1000 for k in ("x", "y")):
                raise ActionError("Для координатного клика нужен свежий снимок и координаты 0..1000")
        if name == "shortcut":
            keys = args.get("keys", "")
            if not isinstance(keys, str) or len(keys) > 60 or not all(
                k in {"ctrl", "alt", "shift", "win", "enter", "escape", "tab", "space", "delete",
                      "backspace", "home", "end", "pageup", "pagedown", "left", "right", "up", "down"}
                or (len(k) == 1 and k.isascii() and k.isalnum())
                for k in keys.lower().split("+")):
                raise ActionError("Неизвестное сочетание клавиш")
        if name == "scroll" and (args.get("direction") not in ("up", "down", "left", "right") or
             type(args.get("count", 3)) is not int or not 1 <= args.get("count", 3) <= 8):
            raise ActionError("Некорректная прокрутка")
        if name == "switch":
            value = args.get("id", "")
            if not isinstance(value, str) or not value.startswith("w") or not value[1:].isdigit():
                raise ActionError("Неизвестное окно")
            if getattr(self,'_browser_first',False) and self._desktop is None:
                raise ActionError('Окна Windows ещё не наблюдались. Используй browser_open или desktop перед выбором окна.')
            state = self.desktop.desktop_state
            if int(value[1:]) not in [w.handle for w in state.windows]:
                raise ActionError("Окно отсутствует в наблюдении")
        if name in ("open_url", "browser_open"):
            safe_url(args.get("url"))
        if name == "launch":
            if not isinstance(args.get("name"), str) or not 1 <= len(args["name"]) <= 120:
                raise ActionError("Не указано название приложения")
            self._app_path(args["name"])
        if name == "apps" and (not isinstance(args.get("query", ""), str) or len(args.get("query", "")) > 120):
            raise ActionError("Слишком длинное название приложения")
        if name == "file":
            if args.get("mode") not in ("read", "list", "exists", "write", "copy", "move", "delete"):
                raise ActionError("Неизвестная операция с файлом")
            if not isinstance(args.get("path"), str) or not args["path"]:
                raise ActionError("Не указан путь")
            protected_path(args["path"])
            if args.get("mode") in ("copy", "move"):
                if not isinstance(args.get("destination"), str) or not args["destination"]:
                    raise ActionError("Не указано назначение")
                protected_path(args["destination"])
            if args.get("mode") == "write" and (not isinstance(args.get("content"), str) or len(args["content"]) > 8000):
                raise ActionError("Содержимое файла должно быть строкой до 8000 символов")
        if name == "shell":
            command = args.get("command", "")
            if (not isinstance(command, str) or not 1 <= len(command) <= 4000 or
                SENSITIVE.search(command) or SYSTEM_COMMAND.search(command)):
                raise ActionError("Команда не разрешена политикой безопасности")

    def _fresh(self, name, args, obs):
        if name in ("file", "shell", "launch", "apps", "open_url", "browser_open", "desktop"):
            return
        if name == "switch":
            return
        if ctypes.windll.user32.GetForegroundWindow() != obs.window:
            import win32gui
            import win32process
            if not win32gui.IsWindow(obs.window) or not obs.window_pid:
                raise ActionError("Рабочее окно исчезло. Нужен новый снимок")
            if win32process.GetWindowThreadProcessId(obs.window)[1] != obs.window_pid:
                raise ActionError("Процесс рабочего окна изменился. Нужен новый снимок")
            self._activate(obs.window)
        if name=='shortcut' and str(args.get('keys','')).lower()=='enter':
            focused=[v for v in obs.targets.values() if v.get('search') is True and v.get('focused') is True]
            if len(focused)==1:
                import win32gui
                from agent_native import target_is_current
                if tuple(win32gui.GetWindowRect(obs.window))!=tuple(obs.rect) or not target_is_current(focused[0]['node'],focused[0],self.uia):
                    raise ActionError('Поисковое поле изменилось; нужен новый выбор действия')
                return
        if name in ('click','type'):
            import win32gui
            if tuple(win32gui.GetWindowRect(obs.window)) != tuple(obs.rect):
                raise ActionError('Окно переместилось. Координаты устарели')
            from agent_native import target_is_current
            expected=obs.targets[str(args['id'])]
            if not target_is_current(expected['node'],expected,self.uia):
                raise ActionError('Цель изменилась или перекрыта; нужно новое наблюдение')
            return
        current = self.observe(image=False)
        if "собственное окно помощника" in current.text:
            raise ActionError("Управление собственным окном JARVIS запрещено. Выбери рабочее окно")
        if current.rect != obs.rect:
            raise ActionError("Окно переместилось. Координаты устарели")
        if name in ("click", "type"):
            old = obs.targets[str(args["id"])]
            matches = [v for v in current.targets.values() if all(v[k] == old[k] for k in ("name", "type", "rect"))]
            if len(matches) != 1:
                raise ActionError("Целевой элемент изменился или неоднозначен")
            obs.targets[str(args["id"])] = matches[0]
        elif current.fingerprint != obs.fingerprint:
            raise ActionError("Интерфейс изменился. Нужен новый выбор действия")
        if name == "click_point" and time.monotonic() - obs.captured > 20:
            raise ActionError("Снимок устарел. Запроси новый")

    def execute(self, name, args, obs):
        self.validate(name, args, obs)
        if self.browser_mode and name not in ("file", "shell", "browser_open", "launch", "apps", "open_url", "desktop"):
            return self.browser.execute(name, args, obs)
        self._fresh(name, args, obs)
        if name in ("click", "type", "click_point"):
            if name == "click_point":
                l, t, r, b = obs.rect
                x, y = l + round((r-l-1)*args["x"]/1000), t + round((b-t-1)*args["y"]/1000)
                node = None
            else:
                node = obs.targets[str(args["id"])]["node"]
                if self._private(node):
                    raise ActionError("Поле защищено")
                rect = node.control.CachedBoundingRectangle if node.control else None
                if rect is not None and [rect.left, rect.top, rect.right, rect.bottom] != obs.targets[str(args["id"])]["rect"]:
                    raise ActionError("Элемент переместился")
                x, y = node.center.x, node.center.y
            target = self.uia.ControlFromPoint(x, y)
            root = target.GetTopLevelControl()
            if root.NativeWindowHandle != obs.window:
                raise ActionError("Цель перекрыта другим окном")
            if name == "type":
                if node.control and not node.control.CachedIsEnabled:
                    raise ActionError("Поле недоступно")
                return self._type_literal(args,obs,x,y)
            if name == "click" and args.get("button", "left") == "left" and args.get("count", 1) == 1:
                try:
                    pattern = node.control.GetInvokePattern() if node.control else None
                except Exception:
                    pattern = None
                if pattern:
                    pattern.Invoke()
                    return "Действие элемента вызвано через UI Automation"
            self.desktop.click((x, y), button=args.get("button", "left"), clicks=args.get("count", 1))
        elif name == "shortcut":
            self.desktop.shortcut(args["keys"])
        elif name == "scroll":
            l, t, r, b = obs.rect
            self.desktop.scroll(((l+r)//2, (t+b)//2),
                type="horizontal" if args["direction"] in ("left", "right") else "vertical",
                direction=args["direction"], wheel_times=args.get("count", 3))
        elif name == "switch":
            self._activate(int(args["id"][1:]))
        elif name == "launch":
            target = self._app_path(args["name"])
            _, previous_handles = self.desktop.get_windows()
            if target.startswith('shell:AppsFolder\\'):
                self._shell_open(str(Path(os.environ['WINDIR'])/'explorer.exe'), target)
            else:
                self._shell_open(target)
            self.browser_mode = False
            return self._wait_for_app_window(args['name'], target, previous_handles)
        elif name == "apps":
            return json.dumps(self.apps.search(args.get('query', '')), ensure_ascii=False)
        elif name == "open_url":
            if self.browser_mode:
                self.browser.open(safe_url(args["url"]))
            else:
                self._shell_open(safe_url(args["url"]))
        elif name == "desktop":
            self.browser_mode = False
            self._browser_first = False
        elif name == "browser_open":
            from agent_browser import ManagedBrowser
            if self.browser is None:
                self.browser = ManagedBrowser(guard=self._action_guard,broker=getattr(self,'_browser_broker',None))
            self.browser.open(safe_url(args["url"]))
            self.browser_mode = True
            return 'Нужная страница открыта; проверь её состояние'
        elif name == "file":
            return self._file(args)
        elif name == "shell":
            # Exact command shown and approved by the user; never EncodedCommand,
            # execution-policy bypass, elevation, or an antivirus exclusion.
            p = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", args["command"]],
                capture_output=True, timeout=20, creationflags=0x08000000, env=clean_env())
            return f"Код выхода {p.returncode}; " + (p.stdout + p.stderr).decode("utf-8", errors="replace")[:1800]
        time.sleep(0.25)
        return "Действие выполнено; результат нужно проверить"

    def _type_literal(self,args,obs,x,y):
        control=self.uia.ControlFromPoint(x,y)
        # Resolve/focus only the observed field, not an arbitrary active document.
        try:
            control.SetFocus()
        except Exception:
            self.desktop.click((x,y),button='left',clicks=1)
        focused=self.uia.GetFocusedControl()
        def focus_valid():
            try:
                active=self.uia.GetFocusedControl()
                box=active.BoundingRectangle
                return (ctypes.windll.user32.GetForegroundWindow()==obs.window
                    and active.GetTopLevelControl().NativeWindowHandle==obs.window
                    and box.left<=x<box.right and box.top<=y<box.bottom
                    and bool(active.HasKeyboardFocus))
            except Exception:
                return False
        guard=getattr(self,'_action_guard',lambda:None)
        guard()
        if not focused or not focus_valid():
            raise ActionError('Не подтверждён фокус текстового поля; ввод не выполнен')
        pattern=None
        try:
            pattern=focused.GetValuePattern()
            if pattern and pattern.IsReadOnly:
                raise ActionError('Поле доступно только для чтения')
            before=pattern.Value if pattern else None
        except ActionError:
            raise
        except Exception:
            pattern,before=None,None
        text=args['text']
        if pattern and isinstance(before,str):
            expected=text if args.get('clear') else before+text
            guard()
            if not focus_valid():
                raise ActionError('Фокус поля изменился; ввод отменён')
            try:
                # Direct field value is literal, including braces/newlines, never Enter.
                pattern.SetValue(expected,waitTime=0)
                actual=pattern.Value
            except Exception:
                raise ExecutionUncertain('Поле могло получить текст, но ввод не подтверждён. Повтор не выполняется.') from None
            if actual!=expected:
                raise ExecutionUncertain('Поле изменило или обрезало текст. Остановился без повторного ввода.')
            return 'Ввод проверен: True; текст добавлен буквально, отправка не выполнялась'
        if args.get('clear'):
            raise ActionError('Поле не поддерживает безопасную замену текста; автоматическая очистка не выполнена')
        from agent_text import send_literal, read_control_text, insertion_verified
        previous=read_control_text(focused)
        send_literal(self.uia,text,guard,focus_valid)
        if previous is not None:
            deadline=time.monotonic()+.7
            while time.monotonic()<deadline:
                guard()
                actual=read_control_text(focused)
                if insertion_verified(previous,actual,text) is True:
                    return 'Ввод проверен: True; точный текст подтверждён через UI Automation TextPattern; отправка не выполнялась'
                time.sleep(.025)
            raise ExecutionUncertain('Текст передан, но его точное появление в документе не подтверждено. Не ввожу повторно.')
        return 'Буквальный текст передан Windows без Enter/Tab; результат нужно проверить по новому наблюдению'

    @staticmethod
    def _shell_open(target, parameters=""):
        # Dispatch through the existing Explorer desktop, not this Python
        # process. Apps the user asked to open must survive the agent's job.
        import pythoncom
        from win32com.client import Dispatch, VARIANT
        try:
            windows = Dispatch("Shell.Application").Windows()
            hwnd = VARIANT(pythoncom.VT_BYREF | pythoncom.VT_I4, 0)
            desktop = windows.FindWindowSW(0, 0, 8, hwnd, 1)
            desktop.Document.Application.ShellExecute(str(target), parameters, "", "open", 1)
        except Exception:
            raise ActionError("Не удалось открыть через оболочку Windows. Приложение не запускалось напрямую") from None

    def _app_path(self, name):
        return self.apps.resolve(name)

    def _wait_for_app_window(self, name, target, previous_handles=None):
        from agent_apps import normalize
        labels = {normalize(name), normalize(Path(target).stem)}
        for entry in self.apps.entries or []:
            if entry['id'] == name or entry['target'] == target:
                labels.add(normalize(entry['name']))
        labels.discard('')
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            # Read the cheap window inventory, not the complete foreground UIA
            # tree repeatedly while waiting. The active window is in this list.
            windows, _ = self.desktop.get_windows()
            matches = list({w.handle:w for w in windows if w and w.handle and
                       any(label in normalize(w.name) for label in labels)}.values())
            if len(matches) == 1:
                self._activate(matches[0].handle)
                return 'Приложение открыто, рабочее окно готово. Проверь его содержимое перед действием.'
            if len(matches) > 1:
                new_matches = [w for w in matches if previous_handles is not None and w.handle not in previous_handles]
                foreground = ctypes.windll.user32.GetForegroundWindow()
                selected = (new_matches[0] if len(new_matches)==1 else
                            next((w for w in matches if w.handle==foreground),matches[0]))
                self._activate(selected.handle)
                return 'Приложение открыто; выбрано новое или последнее рабочее окно. Проверь содержимое; другие документы не изменяй.'
            time.sleep(.25)
        return 'Запрос запуска передан Windows, но окно пока не появилось. Проверь следующее наблюдение и используй wait; не считай задачу завершённой.'

    def show_challenge(self, obs):
        if self.browser_mode:
            self.browser.actions.select_page(self.browser.page_id).bring_to_front()
        elif obs.window:
            self._activate(obs.window)

    def resume(self, obs):
        if not self.browser_mode and obs.window:
            self._activate(obs.window)

    def _activate(self, handle):
        try:
            import win32gui
            if win32gui.IsIconic(handle):
                win32gui.ShowWindow(handle, 9)  # SW_RESTORE; never reuse minimized coordinates.
            self.desktop.bring_window_to_top(handle)
            deadline = time.monotonic() + 0.8
            while time.monotonic() < deadline:
                if ctypes.windll.user32.GetForegroundWindow() == handle:
                    return
                time.sleep(0.05)
        except Exception:
            pass
        raise ActionError("Не удалось переключиться. Выбери рабочее окно; действие ещё не выполнено")

    @staticmethod
    def _file(args):
        import shutil
        path = protected_path(args["path"])
        mode = args["mode"]
        if mode == "exists":
            return str(path.exists())
        if mode == "list":
            if not path.is_dir():
                raise ActionError("Это не папка")
            return "\n".join(p.name for p in sorted(path.iterdir())[:100])
        if mode == "read":
            if path.stat().st_size > 64000:
                raise ActionError("Файл слишком большой для чтения агентом")
            return path.read_text(encoding="utf-8")[:8000]
        if mode == "write":
            with path.open('w' if args.get('_allow_overwrite') is True else 'x', encoding='utf-8') as output:
                output.write(args['content'])
            return f"Записано {path.stat().st_size} байт: {path}"
        if mode == "delete":
            path.rmdir() if path.is_dir() else path.unlink()  # No recursive deletion.
            return f"Удаление проверено: {not path.exists()}"
        destination = protected_path(args["destination"])
        if destination.exists():
            raise ActionError("Назначение существует. Перезапись при копировании/переносе запрещена")
        if mode == "copy":
            if not path.is_file():
                raise ActionError("Копирование папок не выполняется этим инструментом")
            shutil.copy2(path, destination)
        else:
            shutil.move(str(path), str(destination))
        return f"Назначение существует: {destination.exists()}"

    def close(self):
        if self.browser:
            self.browser.close()
