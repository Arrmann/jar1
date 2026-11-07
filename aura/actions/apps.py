import os
import shutil
import subprocess
import webbrowser
from pathlib import Path
from typing import Any, Dict, List

import psutil


KNOWN_APPS = {
    "калькулятор": "calc",
    "calculator": "calc",
    "блокнот": "notepad",
    "notepad": "notepad",
    "paint": "mspaint",
    "проводник": "explorer",
    "explorer": "explorer",
    "cmd": "cmd",
    "powershell": "powershell",
    "браузер": "__browser__",
    "browser": "__browser__",
}

PROTECTED_PROCESS_NAMES = {
    "system",
    "svchost.exe",
    "csrss.exe",
    "wininit.exe",
    "winlogon.exe",
    "services.exe",
    "lsass.exe",
    "dwm.exe",
    "explorer.exe",
}


def _start_menu_dirs() -> List[Path]:
    paths = []

    program_data = os.getenv("ProgramData", r"C:\ProgramData")
    paths.append(Path(program_data) / "Microsoft" / "Windows" / "Start Menu" / "Programs")

    appdata = os.getenv("APPDATA", "")
    if appdata:
        paths.append(Path(appdata) / "Microsoft" / "Windows" / "Start Menu" / "Programs")

    desktop = os.getenv("USERPROFILE", "")
    if desktop:
        paths.append(Path(desktop) / "Desktop")

    return [p for p in paths if p.exists()]


def _find_shortcut(query: str) -> Path | None:
    query = query.strip().lower()
    if not query:
        return None

    for base in _start_menu_dirs():
        try:
            for lnk in base.rglob("*.lnk"):
                if query in lnk.stem.lower():
                    return lnk
            for url in base.rglob("*.url"):
                if query in url.stem.lower():
                    return url
        except PermissionError:
            continue

    return None


def open_app(args: Dict[str, Any]) -> Dict[str, Any]:
    query = str(args.get("query", "")).strip()
    if not query:
        return {"success": False, "message": "Не указано приложение."}

    key = query.lower()

    if key in KNOWN_APPS:
        target = KNOWN_APPS[key]
        if target == "__browser__":
            webbrowser.open("about:blank")
            return {"success": True, "message": "Браузер открыт."}
        subprocess.Popen(target, shell=True)
        return {"success": True, "message": f"Приложение '{query}' запущено."}

    shortcut = _find_shortcut(query)
    if shortcut:
        os.startfile(str(shortcut))  # noqa: S301 - пользовательская команда, подтверждается настройкой безопасности
        return {"success": True, "message": f"Приложение '{shortcut.stem}' открыто."}

    exe = shutil.which(query)
    if exe:
        subprocess.Popen([exe])
        return {"success": True, "message": f"Программа '{query}' запущена."}

    return {"success": False, "message": f"Приложение '{query}' не найдено."}


def close_app(args: Dict[str, Any]) -> Dict[str, Any]:
    name = str(args.get("name", "")).strip().lower()
    if not name:
        return {"success": False, "message": "Не указано приложение для закрытия."}

    closed = []

    for proc in psutil.process_iter(["name", "exe"]):
        try:
            pname = (proc.info.get("name") or "").lower()
            pexe = proc.info.get("exe") or ""
            stem = Path(pexe).stem.lower() if pexe else ""

            if pname in PROTECTED_PROCESS_NAMES:
                continue

            if proc.pid == os.getpid():
                continue

            if name in pname or name in stem:
                proc.terminate()
                closed.append(pname or stem)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    if closed:
        return {"success": True, "message": f"Закрыто процессов: {len(closed)}", "processes": closed[:20]}

    return {"success": False, "message": f"Приложение '{name}' не найдено среди запущенных."}


def list_windows(args: Dict[str, Any]) -> Dict[str, Any]:
    try:
        import pygetwindow as gw

        titles = [title for title in gw.getAllTitles() if title.strip()]
        return {"success": True, "windows": titles[:100]}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось получить окна: {exc}"}


def switch_window(args: Dict[str, Any]) -> Dict[str, Any]:
    title = str(args.get("title", "")).strip()
    if not title:
        return {"success": False, "message": "Не указан заголовок окна."}

    try:
        import pygetwindow as gw

        windows = gw.getWindowsWithTitle(title)
        if not windows:
            return {"success": False, "message": f"Окно '{title}' не найдено."}

        windows[0].activate()
        return {"success": True, "message": f"Окно '{title}' активировано."}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось переключить окно: {exc}"}


def set_volume(args: Dict[str, Any]) -> Dict[str, Any]:
    try:
        percent = int(args.get("percent", 50))
        percent = max(0, min(100, percent))

        from ctypes import POINTER, cast

        from comtypes import CLSCTX_ALL
        from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume

        devices = AudioUtilities.GetSpeakers()
        interface = devices.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        volume = cast(interface, POINTER(IAudioEndpointVolume))
        volume.SetMasterVolumeLevelScalar(percent / 100.0, None)

        return {"success": True, "message": f"Громкость установлена на {percent}%."}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось изменить громкость: {exc}"}
