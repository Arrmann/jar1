"""
JARVIS gesture engine — official MediaPipe Hand Landmarker (Google Tasks API).

Runs headless by default (no preview window / no taskbar icon).
Set JARVIS_GESTURES_PREVIEW=1 to show the debug camera window.

Gestures:
  point (index up)       -> move cursor (anchored on the knuckles, so pinching never drags it)
  thumb+index pinch tap  -> left click (double pinch = double click)
  thumb+index pinch hold -> drag (>= 0.34 s)
  thumb+middle pinch tap -> right click
  victory (V)            -> scroll: move the hand up/down from where V started, like a joystick;
                            holding V still fires a constructor command if one is bound
  open hand (hold 0.3 s) -> resize/move window (size = thumb<->pinky span; full open = fullscreen)
  fist hold ~0.55 s      -> minimize foreground window (once per fist)
  three/four/horns/shaka/ily hold -> constructor commands

Stop: hold Esc ~0.8 s (or press it twice), gestures.stop file, voice "gestures off" / Settings toggle.
"""

from __future__ import annotations

import collections
import ctypes
import json
import math
import os
import queue
import sys
import threading
import time
import traceback
import urllib.request
from ctypes import wintypes
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Package root (…/JARVIS) — scripts & model live here (may be Program Files, read-only).
ROOT = HERE.parents[1]


def _jarvis_data_dir(appdata_default: str) -> Path:
    override = (os.environ.get("JARVIS_CONFIG_DIR") or "").strip()
    if override:
        return Path(override)
    local = (os.environ.get("LOCALAPPDATA") or "").strip()
    if local:
        pointer = Path(local) / "JARVIS" / "active-config-dir.txt"
        try:
            lines = pointer.read_text(encoding="utf-8").splitlines()
        except OSError:
            lines = []
        line = lines[0].strip() if lines else ""
        if line:
            pointed = Path(line)
            if pointed.is_dir():
                return pointed
    appdata = Path(os.environ.get("APPDATA", appdata_default) or appdata_default)
    return appdata / "com.jarvisn.assistant"


def _bootstrap_offline_site() -> None:
    """Embeddable Python ignores PYTHONPATH; ship deps under site-packages/."""
    sites: list[Path] = []
    # Optional offline repair install (gestures-control Ensure-Deps → %APPDATA%/.../py-user).
    cfg = _jarvis_data_dir("")
    user_site = cfg / "py-user" / "Lib" / "site-packages"
    if user_site.is_dir():
        sites.append(user_site)
    bundled = HERE / "site-packages"
    if bundled.is_dir():
        sites.append(bundled)
    # Insert bundled first, then user — last insert(0) wins, so user repair overrides
    # a broken Program Files tree without needing write access to the install dir.
    # Always re-front paths: sitecustomize may have already *appended* the same dirs
    # (for pywin32), which would otherwise leave TTS numpy ahead of gestures numpy.
    for site in reversed(sites):
        for p in (
            site,
            site / "win32",
            site / "win32" / "lib",
            site / "Pythonwin",
        ):
            if not p.is_dir():
                continue
        s = str(p)
            while s in sys.path:
                sys.path.remove(s)
            sys.path.insert(0, s)
    dll = site / "pywin32_system32"
    if dll.is_dir():
        dll_s = str(dll)
        path = os.environ.get("PATH", "")
        if dll_s.lower() not in path.lower():
            os.environ["PATH"] = dll_s + os.pathsep + path
        if hasattr(os, "add_dll_directory"):
            try:
                os.add_dll_directory(dll_s)
            except OSError:
        pass


_bootstrap_offline_site()


def _force_utf8_stdio() -> None:
    # Camera names / status JSON may contain non-ASCII; Windows consoles are often cp125x.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


_force_utf8_stdio()

# Must be set before cv2 is imported.
# MSMF hardware transforms make camera open take seconds on many laptops.
os.environ.setdefault("OPENCV_VIDEOIO_MSMF_ENABLE_HW_TRANSFORMS", "0")
os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")
# CAP_ANY otherwise probes Orbbec depth sensors and spams "Camera index out of range".
os.environ.setdefault("OPENCV_VIDEOIO_PRIORITY_OBSENSOR", "0")
os.environ.setdefault("GLOG_minloglevel", "2")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

try:
    import cv2
    import numpy as np
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
except ImportError as e:
    print("MISSING_DEPS:", e, file=sys.stderr)
    sys.exit(2)

try:
    cv2.setNumThreads(1)
except Exception:
    pass

try:
    import websocket
except ImportError:
    websocket = None

IS_WINDOWS = sys.platform == "win32"

# Runtime state MUST be under writable config dir (standard users / Setup installs).
STATUS_DIR = _jarvis_data_dir(".")
STOP_FILE = STATUS_DIR / "gestures.stop"
LEGACY_STOP_FILE = ROOT / "gestures.stop"
PID_FILE = STATUS_DIR / "gestures.pid"
LOG_FILE = STATUS_DIR / "gestures.log"
PREVIEW = os.environ.get("JARVIS_GESTURES_PREVIEW", "").strip().lower() in (
    "1",
    "true",
    "yes",
    "on",
)
MODEL_BUNDLED = HERE / "hand_landmarker.task"
MODEL_CACHE = STATUS_DIR / "models" / "hand_landmarker.task"
MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/"
    "hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
)
STATUS_FILE = STATUS_DIR / "gestures_status.json"
CAMERA_PREF_FILE = STATUS_DIR / "gestures_camera.txt"
CAMERA_CACHE_FILE = STATUS_DIR / "gestures_camera_cache.json"
IPC_PORT_FILE = STATUS_DIR / "ipc.port"
IPC_TOKEN_FILE = STATUS_DIR / "ipc.token"
GESTURE_CMD_FILE = STATUS_DIR / "gesture-commands.json"
COMMAND_POSES = frozenset({"victory", "three", "horns", "shaka", "ily", "four"})

# MediaPipe hand connections (21 landmarks)
HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (0, 9), (9, 10), (10, 11), (11, 12),
    (0, 13), (13, 14), (14, 15), (15, 16),
    (0, 17), (17, 18), (18, 19), (19, 20),
    (5, 9), (9, 13), (13, 17),
]


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, "") or default)
    except ValueError:
        return default


# ---- Performance -------------------------------------------------------------
MAX_FPS = max(10.0, min(60.0, _env_float("JARVIS_GESTURES_FPS", 30.0)))
IDLE_FPS = 12.0  # no hand in view → run the (expensive) palm detector less often
IDLE_AFTER_S = 1.5
PROC_MAX_W = 640
STATUS_EVERY_S = 0.8
CONTROL_EVERY_S = 0.25  # stop-file / bindings polling

# ---- Camera ------------------------------------------------------------------
CAMERA_INDEX_MAX = 8
# Windows indices are not a packed list: a dead virtual/IR device can sit
# in front of the real webcam. Stop only after a real gap, not after one miss.
CAMERA_MISS_STOP = 4
CAMERA_OPEN_WARMUP_S = 1.6
CAMERA_FAIL_READS = 40  # consecutive failed reads before reconnecting
DARK_WARN_S = 2.0

# ---- Finger state (3D joint angles — independent of hand rotation) -----------
FINGER_ON_ANG = 55.0
FINGER_OFF_ANG = 70.0
FINGER_ON_FAR = 1.08  # tip/PIP distance-to-wrist ratio
FINGER_OFF_FAR = 0.98
THUMB_ON = 1.20  # thumb tip ↔ ring MCP / palm width
THUMB_OFF = 1.05
FIST_THUMB_MAX = 1.0  # minimize only with the thumb clearly tucked (real fists ≤ 0.75)
POSE_STABLE_FRAMES = 2

# ---- Pinch (2D ratio — MediaPipe depth is too noisy for touching fingertips) --
PINCH_ON = 0.26
PINCH_OFF = 0.38
# Pinch point must sit in front of the fingers, not on the palm (a fist has a
# small 2D pinch ratio too: 0.17–0.23 on real photos).
PINCH_PALM_ON = 0.52
PINCH_PALM_KEEP = 0.45
PINCH_INDEX_ANG_ON = 125.0
PINCH_INDEX_ANG_KEEP = 138.0
RIGHT_PINCH_ON = 0.24
RIGHT_PINCH_OFF = 0.36
RIGHT_INDEX_CLEAR = 0.45
# Thumb resting on a curled middle finger (normal pointing pose) must never right-click.
RIGHT_PALM_ON = 0.56
RIGHT_MID_ANG_MAX = 115.0
RIGHT_MID_FAR_MIN = 0.82
RIGHT_CLICK_MAX_S = 0.9
HOLD_ARM_S = 0.34  # pinch this long → mouse-down (drag)
CLICK_MIN_S = 0.05  # ignore micro noise
CLICK_MIN_FRAMES = 2
CLICK_DEBOUNCE_S = 0.12
PINCH_RELEASE_S = 0.045  # must stay open this long before click/end-drag
CURSOR_REWIND_S = 0.10  # click where the cursor was just before the fingers closed
DOUBLE_CLICK_SNAP_PX = 36
HAND_LOST_GRACE_S = 0.25

# ---- Cursor ------------------------------------------------------------------
CURSOR_MIN_CUTOFF = _env_float("JARVIS_GESTURES_MIN_CUTOFF", 0.6)
CURSOR_BETA = _env_float("JARVIS_GESTURES_BETA", 8.0)  # per screen/second
CURSOR_D_CUTOFF = 1.2
CURSOR_DEADBAND_PX = 1.5
# Hand-size adaptive reach: the same arm travel covers the screen whether the
# webcam is a laptop lid (hand close) or a monitor-top USB cam (hand far).
CURSOR_BOX_K = _env_float("JARVIS_GESTURES_REACH", 3.6)
CURSOR_BOX_MIN = 0.30
CURSOR_BOX_MAX = 0.72
CURSOR_BOX_CY = 0.47
HAND_SIZE_TAU_S = 1.2
OFFSET_DECAY_TAU_S = 0.18
SCREEN_MODE = (os.environ.get("JARVIS_GESTURES_SCREEN") or "all").strip().lower()

# ---- Scroll (V joystick) -----------------------------------------------------
SCROLL_DEAD = 0.28  # in hand sizes
SCROLL_FULL = 1.30
SCROLL_MAX_NOTCHES_S = 20.0
SCROLL_SETTLE_S = 0.12
VICTORY_CMD_HOLD_S = 0.9

# ---- Commands / fist ---------------------------------------------------------
CMD_HOLD_S = 0.5
CMD_COOLDOWN_S = 1.6
FIST_MINIMIZE_S = 0.55
MINIMIZE_COOLDOWN_S = 1.2

# ---- Window pack -------------------------------------------------------------
# Open palm snaps windows into the stage layout at once (no slow ease-in).
# While the palm stays up, only the front card follows the hand.
WIN_ENGAGE_SPREAD = 0.22
WIN_KEEP_SPREAD = 0.01
WIN_ENGAGE_S = 0.30  # open palm must be held this long — a wave must not resize windows
WIN_UPDATE_GAP_S = 0.032
WIN_MAX_SPREAD = 0.92
WIN_MOVE_GAIN = 3.4
WIN_MOVE_DEAD = 0.0045
WIN_MOVE_SOFT = 0.010
WIN_HOLD_SPREAD = 0.28  # between this and MAX the card keeps the stage size
# Stage, fractions of the monitor work area (x, y, w, h). Matches a stacked
# desktop: left column, large right pane, centered card on top.
STAGE_CARD = (0.30, 0.16, 0.40, 0.68)
STAGE_SIDE = (0.00, 0.00, 0.30, 1.00)
STAGE_MAIN = (0.28, 0.00, 0.72, 1.00)

# ---- Esc ---------------------------------------------------------------------
ESC_HOLD_S = 0.8
ESC_DOUBLE_S = 0.6

SKIP_PROCS = {
    "jarvis-gui", "jarvis-app", "jarvis-run", "jarvis-gestures",
    "textinputhost", "shellexperiencehost", "startmenuexperiencehost",
    "searchhost", "searchapp", "lockapp",
}
SKIP_CLASSES = {
    "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Progman", "WorkerW",
    "NotifyIconOverflowWindow", "Windows.UI.Core.CoreWindow",
}


# =============================================================================
# Logging / status
# =============================================================================

_log_lock = threading.Lock()


def log(*parts) -> None:
    msg = " ".join(str(p) for p in parts)
    try:
        if sys.stdout is not None:
            print(msg, flush=True)
    except Exception:
        pass
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n"
    with _log_lock:
        try:
            STATUS_DIR.mkdir(parents=True, exist_ok=True)
            if LOG_FILE.exists() and LOG_FILE.stat().st_size > 1_000_000:
                LOG_FILE.replace(LOG_FILE.with_suffix(".log.1"))
            with LOG_FILE.open("a", encoding="utf-8") as fh:
                fh.write(line)
        except Exception:
            pass


def _atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    try:
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, path)
    except OSError:
        # Readers/AV can hold the target briefly; a direct write is better than nothing.
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        path.write_text(text, encoding="utf-8")


def write_status(
    active: bool,
    camera: bool,
    last: str,
    message: str,
    *,
    camera_index=None,
    camera_mode: str = "",
    extra: dict | None = None,
) -> None:
    payload = {
        "active": active,
        "camera": camera,
        "backend": "mediapipe",
        "last_gesture": last,
        "message": message,
        "camera_index": camera_index,
        "camera_mode": camera_mode or read_camera_preference(),
    }
    if extra:
        payload.update(extra)
    try:
        _atomic_write_text(STATUS_FILE, json.dumps(payload, ensure_ascii=False))
    except Exception:
        pass


# =============================================================================
# Win32 (ctypes only — no pywin32 in the hot path)
# =============================================================================

class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


class POINT(ctypes.Structure):
    _fields_ = [("x", wintypes.LONG), ("y", wintypes.LONG)]


class WINDOWPLACEMENT(ctypes.Structure):
    _fields_ = [
        ("length", wintypes.UINT),
        ("flags", wintypes.UINT),
        ("showCmd", wintypes.UINT),
        ("ptMinPosition", POINT),
        ("ptMaxPosition", POINT),
        ("rcNormalPosition", RECT),
    ]


class MONITORINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("rcMonitor", RECT),
        ("rcWork", RECT),
        ("dwFlags", wintypes.DWORD),
    ]


class PROCESS_POWER_THROTTLING_STATE(ctypes.Structure):
    _fields_ = [
        ("Version", wintypes.ULONG),
        ("ControlMask", wintypes.ULONG),
        ("StateMask", wintypes.ULONG),
    ]


if IS_WINDOWS:
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    try:
        dwmapi = ctypes.WinDLL("dwmapi")
    except OSError:
        dwmapi = None

    HWND = wintypes.HWND
    user32.GetForegroundWindow.restype = HWND
    user32.GetForegroundWindow.argtypes = []
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    user32.GetWindowThreadProcessId.argtypes = [HWND, ctypes.POINTER(wintypes.DWORD)]
    for _fn in ("IsWindow", "IsWindowVisible", "IsIconic", "IsZoomed"):
        getattr(user32, _fn).restype = wintypes.BOOL
        getattr(user32, _fn).argtypes = [HWND]
    user32.GetClassNameW.restype = ctypes.c_int
    user32.GetClassNameW.argtypes = [HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowRect.restype = wintypes.BOOL
    user32.GetWindowRect.argtypes = [HWND, ctypes.POINTER(RECT)]
    user32.GetWindowPlacement.restype = wintypes.BOOL
    user32.GetWindowPlacement.argtypes = [HWND, ctypes.POINTER(WINDOWPLACEMENT)]
    user32.SetWindowPlacement.restype = wintypes.BOOL
    user32.SetWindowPlacement.argtypes = [HWND, ctypes.POINTER(WINDOWPLACEMENT)]
    user32.SetWindowPos.restype = wintypes.BOOL
    user32.SetWindowPos.argtypes = [
        HWND, HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.UINT,
    ]
    user32.ShowWindow.restype = wintypes.BOOL
    user32.ShowWindow.argtypes = [HWND, ctypes.c_int]
    user32.ShowWindowAsync.restype = wintypes.BOOL
    user32.ShowWindowAsync.argtypes = [HWND, ctypes.c_int]
    WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, HWND, wintypes.LPARAM)
    user32.EnumWindows.restype = wintypes.BOOL
    user32.EnumWindows.argtypes = [WNDENUMPROC, wintypes.LPARAM]
    user32.GetWindowTextLengthW.restype = ctypes.c_int
    user32.GetWindowTextLengthW.argtypes = [HWND]
    user32.MonitorFromWindow.restype = wintypes.HMONITOR
    user32.MonitorFromWindow.argtypes = [HWND, wintypes.DWORD]
    user32.GetMonitorInfoW.restype = wintypes.BOOL
    user32.GetMonitorInfoW.argtypes = [wintypes.HMONITOR, ctypes.POINTER(MONITORINFO)]
    user32.GetSystemMetrics.restype = ctypes.c_int
    user32.GetSystemMetrics.argtypes = [ctypes.c_int]
    user32.SetCursorPos.restype = wintypes.BOOL
    user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
    user32.GetCursorPos.restype = wintypes.BOOL
    user32.GetCursorPos.argtypes = [ctypes.POINTER(wintypes.POINT)]
    user32.mouse_event.restype = None
    user32.mouse_event.argtypes = [
        wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, ctypes.c_size_t,
    ]
    user32.GetAsyncKeyState.restype = ctypes.c_short
    user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
    user32.GetWindowLongW.restype = ctypes.c_long
    user32.GetWindowLongW.argtypes = [HWND, ctypes.c_int]
    user32.GetDoubleClickTime.restype = wintypes.UINT
    user32.GetDoubleClickTime.argtypes = []
    user32.SystemParametersInfoW.restype = wintypes.BOOL
    user32.SystemParametersInfoW.argtypes = [
        wintypes.UINT, wintypes.UINT, ctypes.c_void_p, wintypes.UINT,
    ]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.CloseHandle.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
    kernel32.QueryFullProcessImageNameW.argtypes = [
        wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD),
    ]
    kernel32.CreateMutexW.restype = wintypes.HANDLE
    kernel32.CreateMutexW.argtypes = [ctypes.c_void_p, wintypes.BOOL, wintypes.LPCWSTR]
    kernel32.GetCurrentProcess.restype = wintypes.HANDLE
    kernel32.GetCurrentProcess.argtypes = []
    try:
        kernel32.SetProcessInformation.restype = wintypes.BOOL
        kernel32.SetProcessInformation.argtypes = [
            wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD,
        ]
    except AttributeError:  # Windows 7
        pass
    if dwmapi is not None:
        dwmapi.DwmGetWindowAttribute.restype = ctypes.c_long
        dwmapi.DwmGetWindowAttribute.argtypes = [
            HWND, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD,
        ]
else:  # pragma: no cover - engine is Windows-only; keeps unit tests importable elsewhere
    user32 = kernel32 = dwmapi = None

MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_WHEEL = 0x0800
SW_SHOWNORMAL = 1
SW_MAXIMIZE = 3
SW_MINIMIZE = 6
SW_RESTORE = 9
SWP_NOZORDER = 0x0004
SWP_NOACTIVATE = 0x0010
SWP_SHOWWINDOW = 0x0040
SWP_NOOWNERZORDER = 0x0200
SWP_ASYNCWINDOWPOS = 0x4000
HWND_TOP = 0
HWND_BOTTOM = 1
GWL_EXSTYLE = -20
WS_EX_TOOLWINDOW = 0x00000080
DWMWA_CLOAKED = 14
MONITOR_DEFAULTTONEAREST = 2
VK_ESCAPE = 0x1B


def enable_dpi_awareness() -> None:
    """Per-monitor DPI awareness: real pixels for cursor/window math on 125–200% laptops."""
    if not IS_WINDOWS:
        return
    try:
        if user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4)):
            return
    except Exception:
        pass
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
        return
    except Exception:
        pass
    try:
        user32.SetProcessDPIAware()
    except Exception:
        pass


def disable_power_throttling() -> None:
    """Windowless background processes get EcoQoS-throttled on battery → laggy tracking."""
    if not IS_WINDOWS:
        return
    try:
        state = PROCESS_POWER_THROTTLING_STATE(1, 0x1 | 0x4, 0)
        kernel32.SetProcessInformation(
            kernel32.GetCurrentProcess(),
            4,  # ProcessPowerThrottling
            ctypes.byref(state),
            ctypes.sizeof(state),
        )
    except Exception:
        pass


_INSTANCE_MUTEX = None


def acquire_single_instance() -> bool:
    global _INSTANCE_MUTEX
    if not IS_WINDOWS:
        return True
    try:
        h = kernel32.CreateMutexW(None, False, "Local\\JarvisGesturesEngine")
        if not h:
            return True
        if ctypes.get_last_error() == 183:  # ERROR_ALREADY_EXISTS
            kernel32.CloseHandle(h)
        return False
        _INSTANCE_MUTEX = h
    except Exception:
        pass
    return True


class Desktop:
    """All OS side effects go through here (swapped for a fake in tests)."""

    def __init__(self) -> None:
        self._screen = (0, 0, 1920, 1080)
        self._screen_at = -1e9
        self._pname_cache: dict[int, str] = {}
        self._own_pid = os.getpid()
        try:
            self.double_click_s = max(0.2, min(0.9, user32.GetDoubleClickTime() / 1000.0))
    except Exception:
            self.double_click_s = 0.5

    # ---- screen / cursor ----
    def screen_rect(self) -> tuple[int, int, int, int]:
        now = time.monotonic()
        if now - self._screen_at > 2.0:
            self._screen_at = now
            try:
                if SCREEN_MODE == "primary":
                    rc = (0, 0, user32.GetSystemMetrics(0), user32.GetSystemMetrics(1))
                else:
                    rc = (
                        user32.GetSystemMetrics(76),
                        user32.GetSystemMetrics(77),
                        user32.GetSystemMetrics(78),
                        user32.GetSystemMetrics(79),
                    )
                if rc[2] > 0 and rc[3] > 0:
                    self._screen = rc
            except Exception:
                pass
        return self._screen

    def cursor_pos(self) -> tuple[int, int]:
        pt = wintypes.POINT()
        try:
            if user32.GetCursorPos(ctypes.byref(pt)):
                return int(pt.x), int(pt.y)
        except Exception:
            pass
        x, y, w, h = self.screen_rect()
        return x + w // 2, y + h // 2

    def set_cursor(self, x: int, y: int) -> None:
        # Fails harmlessly on the secure desktop (UAC / lock screen).
        try:
            user32.SetCursorPos(int(x), int(y))
        except Exception:
            pass

    def mouse_button(self, button: str, down: bool) -> None:
        if button == "right":
            flag = MOUSEEVENTF_RIGHTDOWN if down else MOUSEEVENTF_RIGHTUP
        else:
            flag = MOUSEEVENTF_LEFTDOWN if down else MOUSEEVENTF_LEFTUP
        try:
            user32.mouse_event(flag, 0, 0, 0, 0)
        except Exception:
            pass

    def click(self, button: str = "left") -> None:
        # Many apps ignore a zero-gap down/up pair.
        self.mouse_button(button, True)
        time.sleep(0.012)
        self.mouse_button(button, False)

    def wheel(self, delta: int) -> None:
        try:
            user32.mouse_event(MOUSEEVENTF_WHEEL, 0, 0, int(delta) & 0xFFFFFFFF, 0)
        except Exception:
            pass

    # ---- windows ----
    def _process_name(self, pid: int) -> str:
        name = self._pname_cache.get(pid)
        if name is not None:
            return name
        name = ""
        try:
            h = kernel32.OpenProcess(0x1000, False, pid)  # QUERY_LIMITED_INFORMATION
            if h:
                try:
                    buf = ctypes.create_unicode_buffer(1024)
                    size = wintypes.DWORD(1024)
                    if kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
                        name = Path(buf.value).stem.lower()
                finally:
                    kernel32.CloseHandle(h)
        except Exception:
            name = ""
        if len(self._pname_cache) > 256:
            self._pname_cache.clear()
        self._pname_cache[pid] = name
        return name

    def _is_target(self, hwnd, allow_iconic: bool = False) -> bool:
        if not hwnd:
        return False
        try:
            if not user32.IsWindow(hwnd) or not user32.IsWindowVisible(hwnd):
        return False
            if user32.IsIconic(hwnd) and not allow_iconic:
                return False
            buf = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, buf, 256)
            if buf.value in SKIP_CLASSES:
                return False
            if user32.GetWindowLongW(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW:
                return False
            if dwmapi is not None:
                cloaked = ctypes.c_int(0)
                if dwmapi.DwmGetWindowAttribute(
                    hwnd, DWMWA_CLOAKED, ctypes.byref(cloaked), ctypes.sizeof(cloaked)
                ) == 0 and cloaked.value:
                    return False
            pid = wintypes.DWORD(0)
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            if int(pid.value) == self._own_pid:
                return False
            if self._process_name(int(pid.value)) in SKIP_PROCS:
        return False
    return True
        except Exception:
            return False

    def foreground_target(self):
        try:
            hwnd = user32.GetForegroundWindow()
        except Exception:
            return None
        return hwnd if self._is_target(hwnd) else None

    def is_valid_window(self, hwnd) -> bool:
        try:
            return bool(hwnd) and bool(user32.IsWindow(hwnd)) and not user32.IsIconic(hwnd)
        except Exception:
            return False

    def minimize(self, hwnd) -> bool:
        try:
            return bool(user32.ShowWindowAsync(hwnd, SW_MINIMIZE))
        except Exception:
            return False

    def maximize(self, hwnd) -> None:
        try:
            user32.ShowWindowAsync(hwnd, SW_MAXIMIZE)
        except Exception:
            pass

    def restore_if_zoomed(self, hwnd) -> None:
        try:
            if user32.IsZoomed(hwnd):
                user32.ShowWindowAsync(hwnd, SW_RESTORE)
        except Exception:
            pass

    def window_rect(self, hwnd):
        rc = RECT()
        try:
            if user32.GetWindowRect(hwnd, ctypes.byref(rc)):
                return int(rc.left), int(rc.top), int(rc.right), int(rc.bottom)
        except Exception:
            pass
        return None

    def work_area(self, hwnd) -> tuple[int, int, int, int]:
        try:
            mon = user32.MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)
            mi = MONITORINFO()
            mi.cbSize = ctypes.sizeof(MONITORINFO)
            if mon and user32.GetMonitorInfoW(mon, ctypes.byref(mi)):
                r = mi.rcWork
                return int(r.left), int(r.top), int(r.right), int(r.bottom)
            except Exception:
                pass
        rc = RECT()
        try:
            if user32.SystemParametersInfoW(0x0030, 0, ctypes.byref(rc), 0):
                return int(rc.left), int(rc.top), int(rc.right), int(rc.bottom)
        except Exception:
            pass
        return 0, 0, 1920, 1080

    def set_rect(self, hwnd, x: int, y: int, w: int, h: int) -> None:
        self.place_window(hwnd, x, y, w, h, z="keep")

    def place_window(self, hwnd, x: int, y: int, w: int, h: int, z: str = "keep") -> None:
        """Move/size now. A maximized window is restored once, then placed —
        otherwise the restore lands later and the layout never finishes."""
        if not IS_WINDOWS:
            return
        zoomed = False
        try:
            zoomed = bool(user32.IsZoomed(hwnd) or user32.IsIconic(hwnd))
            except Exception:
            zoomed = False
        if not zoomed:
            rc = self.window_rect(hwnd)
            work = self.work_area(hwnd)
            if rc and work[2] > work[0]:
                ww, hh = rc[2] - rc[0], rc[3] - rc[1]
                aw, ah = work[2] - work[0], work[3] - work[1]
                # Chrome-style "maximized" sometimes leaves IsZoomed false.
                zoomed = ww >= aw * 0.92 and hh >= ah * 0.92
        if zoomed:
            # SetWindowPos is ignored while the window is still maximized.
            # Restore first, then write the normal rect, then place in pixels.
            try:
                user32.ShowWindow(hwnd, SW_RESTORE)
            except Exception:
                pass
            try:
                wp = WINDOWPLACEMENT()
                wp.length = ctypes.sizeof(WINDOWPLACEMENT)
                if user32.GetWindowPlacement(hwnd, ctypes.byref(wp)):
                    wp.showCmd = SW_SHOWNORMAL
                    wp.flags = 0
                    wp.rcNormalPosition = RECT(int(x), int(y), int(x + w), int(y + h))
                    user32.SetWindowPlacement(hwnd, ctypes.byref(wp))
            except Exception:
                pass
        flags = SWP_NOACTIVATE | SWP_SHOWWINDOW
        if not zoomed:
            flags |= SWP_ASYNCWINDOWPOS
        insert = None
        if z == "top":
            insert = HWND(HWND_TOP)
        elif z == "bottom":
            insert = HWND(HWND_BOTTOM)
        else:
            flags |= SWP_NOZORDER | SWP_NOOWNERZORDER
        try:
            user32.SetWindowPos(hwnd, insert, int(x), int(y), int(w), int(h), flags)
                except Exception:
                    pass

    def visible_windows(self, prefer=None, limit: int = 3, include_minimized: bool = False) -> list:
        """Top-level windows on the foreground monitor, front to back.
        Minimized windows stay out unless include_minimized — a fist must stay a fist."""
        if not IS_WINDOWS:
            return [prefer] if prefer else []
        found: list = []

        def _cb(hwnd, _lparam):
            if len(found) >= 16:
                return True
            try:
                if not self._is_target(hwnd, allow_iconic=include_minimized):
                    return True
                if user32.GetWindowTextLengthW(hwnd) <= 0:
                    return True
                if user32.IsIconic(hwnd):
                    found.append(hwnd)
                    return True
                rc = self.window_rect(hwnd)
                if not rc or (rc[2] - rc[0]) < 80 or (rc[3] - rc[1]) < 60:
                    return True
                found.append(hwnd)
            except Exception:
                return True
            return True

        try:
            cb = WNDENUMPROC(_cb)
            user32.EnumWindows(cb, 0)
        except Exception:
            found = []
        if prefer and prefer in found:
            found.remove(prefer)
            found.insert(0, prefer)
        elif prefer and self._is_target(prefer):
            found.insert(0, prefer)
        anchor = found[0] if found else prefer
        if anchor:
            try:
                mon = user32.MonitorFromWindow(anchor, MONITOR_DEFAULTTONEAREST)
            except Exception:
                mon = None
            if mon:
                same = []
                for hwnd in found:
                    try:
                        if user32.MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) == mon:
                            same.append(hwnd)
                    except Exception:
                        continue
                found = same
        return found[:limit]


def _escape_down() -> tuple[bool, bool]:
    """(is_down, was_pressed_since_last_poll) — global, any focused window."""
    if not IS_WINDOWS:
        return False, False
    try:
        st = int(user32.GetAsyncKeyState(VK_ESCAPE))
    except Exception:
        return False, False
    return bool(st & 0x8000), bool(st & 0x0001)


class EscWatcher:
    """Hold Esc or double-press it. A single Esc (closing a dialog, leaving
    fullscreen video) must not kill gesture control."""

    def __init__(self) -> None:
        down, _ = _escape_down()
        self._armed = not down  # ignore an Esc still held from before launch
        self._down_since = None
        self._last_tap = -1e9
        self._was_down = down

    def poll(self, now: float) -> bool:
        down, pressed = _escape_down()
        if not self._armed:
            if not down:
                self._armed = True
                self._was_down = False
            return False
        if down:
            if self._down_since is None:
                self._down_since = now
            if now - self._down_since >= ESC_HOLD_S:
                return True
        edge = (down and not self._was_down) or (pressed and not down and not self._was_down)
        if edge:
            if now - self._last_tap <= ESC_DOUBLE_S:
                return True
            self._last_tap = now
        if not down:
            self._down_since = None
        self._was_down = down
        return False


# =============================================================================
# Camera
# =============================================================================

def frame_is_usable(frame) -> bool:
    """Reject empty / black / flat frames (IR, privacy shutter, half-open USB devices)."""
    if frame is None or getattr(frame, "size", 0) == 0:
        return False
    try:
        small = frame[::8, ::8]
        gray = small.mean(axis=2) if small.ndim == 3 else small
        mean = float(gray.mean())
        std = float(gray.std())
    except Exception:
        return False
    if std < 1.5:
        return False
    if std < 4.0 and (mean < 8.0 or mean > 247.0):
        return False
    return True


def score_frame(frame, fps: float = 0.0) -> float:
    """Higher = better for hand tracking (prefer fast RGB webcam over IR/virtual)."""
    if not frame_is_usable(frame):
        return -1.0
    h, w = frame.shape[:2]
    score = float(min(w, 1920)) / 32.0 + float(min(h, 1080)) / 48.0
    if 480 <= min(h, w) <= 1080:
        score += 12.0
    if frame.ndim == 3 and frame.shape[2] >= 3:
        score += 80.0
        small = frame[::4, ::4, :3].astype(np.int16)
        b, g, r = small[:, :, 0], small[:, :, 1], small[:, :, 2]
        chroma = float(np.abs(r - g).mean() + np.abs((r + g) // 2 - b).mean())
        score += chroma * 0.35
        score += float(small.mean(axis=2).std()) * 0.15
        # IR / mono virtual cams look almost gray
        if chroma < 6.0:
            score -= 55.0
        else:
        score += 8.0
    # A 10 FPS stream is unusable for a cursor no matter how nice the picture is.
    score += min(max(fps, 0.0), 30.0) * 2.0
    return score


def _backend_list():
    out = []
    if hasattr(cv2, "CAP_MSMF"):
        out.append(("msmf", cv2.CAP_MSMF))
    if hasattr(cv2, "CAP_DSHOW"):
        out.append(("dshow", cv2.CAP_DSHOW))
    if not out:
        out.append(("any", cv2.CAP_ANY))
    return out


def _backend_api(name: str):
    for n, api in _backend_list():
        if n == name:
            return api
    return None


@dataclass
class CamCandidate:
    cap: object
    index: int
    backend: str
    width: int
    height: int
    fps: float
    score: float
    dark: bool = False

    def release(self) -> None:
        try:
            self.cap.release()
            except Exception:
                pass


def _open_backend(idx: int, name: str, api) -> CamCandidate | None:
    try:
        cap = cv2.VideoCapture(idx, api)
    except Exception:
        return None
    if not cap.isOpened():
        try:
            cap.release()
    except Exception:
        pass
        return None
    # Leave the native mode. Forcing 640x480 before the first frame makes
    # MSMF/DirectShow return nothing on a lot of laptop webcams. The tracker
    # already scales the frame down.
    frame = None
    last_any = None
    deadline = time.monotonic() + CAMERA_OPEN_WARMUP_S
    while time.monotonic() < deadline:
        try:
            ok, f = cap.read()
        except Exception:
            ok, f = False, None
        if ok and f is not None and getattr(f, "size", 0):
            last_any = f
            if frame_is_usable(f):
                frame = f
                break
        else:
            time.sleep(0.03)
    if frame is None and last_any is None:
        try:
            cap.release()
        except Exception:
            pass
        return None
    dark = frame is None
    if dark:
        frame = last_any
    n = 0
    t0 = time.monotonic()
    while n < 6 and time.monotonic() - t0 < 0.9:
        try:
            ok, f = cap.read()
        except Exception:
            ok, f = False, None
        if ok and f is not None:
            n += 1
            if frame_is_usable(f):
                frame = f
                dark = False
    elapsed = max(1e-3, time.monotonic() - t0)
    fps = n / elapsed
    h, w = frame.shape[:2]
    sc = score_frame(frame, fps) if not dark else -50.0 + fps
    return CamCandidate(cap, idx, name, int(w), int(h), fps, sc, dark)


def try_open_index(idx: int, only_backend: str | None = None) -> CamCandidate | None:
    """First backend that delivers frames wins.

    A camera cannot be open in MSMF and DirectShow at the same time. Closing a
    live stream to measure the other backend leaves a lot of webcams stuck.
    """
    backends = _backend_list()
    if only_backend:
        backends = [(n, a) for n, a in backends if n == only_backend] or backends
    dark: CamCandidate | None = None
    for name, api in backends:
        cand = _open_backend(idx, name, api)
        if cand is None:
            continue
        if not cand.dark:
            if dark is not None:
                dark.release()
            return cand
        if dark is None:
            dark = cand
        else:
            cand.release()
    return dark


def probe_cameras(max_idx: int = CAMERA_INDEX_MAX) -> list:
    found = []
    misses = 0
    for idx in range(max_idx):
        hit = try_open_index(idx)
        if not hit:
            misses += 1
            if misses >= CAMERA_MISS_STOP:
                break
            continue
        misses = 0
        hit.release()
        label = f"Camera {idx}"
        if hit.dark:
            label += " (black image / shutter?)"
        elif hit.score < 140:
            label += " (weak / IR?)"
        elif hit.width >= 1280:
            label += " (HD)"
        found.append(
            {
                "id": str(idx),
                "index": idx,
                "ok": not hit.dark,
                "score": round(hit.score, 1),
                "label": label,
                "width": hit.width,
                "height": hit.height,
                "backend": hit.backend,
                "fps": round(hit.fps, 1),
            }
        )
    found.sort(key=lambda x: x["score"], reverse=True)
    return found


def read_camera_preference() -> str:
    env = (os.environ.get("JARVIS_GESTURES_CAMERA") or "").strip().lower()
    if env:
        return env
    try:
        if CAMERA_PREF_FILE.exists():
            return CAMERA_PREF_FILE.read_text(encoding="utf-8").strip().lower() or "auto"
    except OSError:
        pass
    return "auto"


def _read_camera_cache() -> dict:
    try:
        raw = json.loads(CAMERA_CACHE_FILE.read_text(encoding="utf-8"))
        return raw if isinstance(raw, dict) else {}
    except Exception:
        return {}


def _write_camera_cache(c: CamCandidate) -> None:
    try:
        _atomic_write_text(
            CAMERA_CACHE_FILE,
            json.dumps({"index": c.index, "backend": c.backend, "fps": round(c.fps, 1)}),
        )
    except Exception:
        pass


def open_camera() -> CamCandidate | None:
    """Preferred index, else last good camera (fast path), else scan for the best."""
    pref = read_camera_preference()
    preferred_idx = None
    if pref and pref != "auto":
        try:
            preferred_idx = int(pref)
        except ValueError:
            preferred_idx = None

        if preferred_idx is not None:
        hit = try_open_index(preferred_idx)
        if hit:
            log(
                f"camera index {preferred_idx} backend {hit.backend} ({hit.width}x{hit.height}) "
                f"{hit.fps:.0f} fps score={hit.score:.1f} [manual]"
            )
            return hit
        log(f"preferred camera {preferred_idx} failed — falling back to auto")
    else:
        cache = _read_camera_cache()
        try:
            cidx = int(cache.get("index"))
            cback = str(cache.get("backend") or "")
        except (TypeError, ValueError):
            cidx, cback = None, ""
        if cidx is not None and cback:
            api = _backend_api(cback)
            hit = _open_backend(cidx, cback, api) if api is not None else None
            if hit and not hit.dark and hit.fps >= 15.0 and hit.score >= 140:
                log(
                    f"camera index {cidx} backend {cback} ({hit.width}x{hit.height}) "
                    f"{hit.fps:.0f} fps score={hit.score:.1f} [cached]"
                )
                return hit
            if hit:
                hit.release()

    best: CamCandidate | None = None
    misses = 0
    for idx in range(CAMERA_INDEX_MAX):
            hit = try_open_index(idx)
            if not hit:
            misses += 1
            if misses >= CAMERA_MISS_STOP:
                break
                continue
        misses = 0
        if best is None or hit.score > best.score:
                if best is not None:
                best.release()
            best = hit
            else:
            hit.release()
        if best is not None:
        log(
            f"camera index {best.index} backend {best.backend} ({best.width}x{best.height}) "
            f"{best.fps:.0f} fps score={best.score:.1f} [auto]"
        )
        if not best.dark:
            _write_camera_cache(best)
    return best


class CameraStream:
    """Reads frames on its own thread and keeps only the newest one.

    A blocking cap.read() in the tracking loop adds a full frame of latency and
    lets driver buffers queue stale frames; here the tracker always gets the
    freshest image and never waits on the camera.
    """

    def __init__(self, cand: CamCandidate) -> None:
        self.cand = cand
        self._cond = threading.Condition()
        self._frame = None
        self._seq = 0
        self._t = 0.0
        self._running = True
        self.state = "ok"  # ok | reconnecting | lost
        self.stop_requested = False
        self.reconnected = 0
        self._thread = threading.Thread(target=self._run, name="camera", daemon=True)
        self._thread.start()

    @property
    def index(self) -> int:
        return self.cand.index

    @property
    def label(self) -> str:
        return f"Camera {self.cand.index}"

    def _run(self) -> None:
        fails = 0
        while self._running:
            try:
                ok, frame = self.cand.cap.read()
        except Exception:
                ok, frame = False, None
            if ok and frame is not None and getattr(frame, "size", 0):
                fails = 0
                with self._cond:
                    self._frame = frame
                    self._seq += 1
                    self._t = time.monotonic()
                    self._cond.notify_all()
                continue
            fails += 1
            if fails < CAMERA_FAIL_READS:
                time.sleep(0.025)
                continue
            if not self._reconnect():
                return
            fails = 0

    def _reconnect(self) -> bool:
        """Keep the engine up until the camera is back or the user stops gestures.

        A USB sleep / another app grabbing the cam used to kill the process
        after 30s, and nothing started it again.
        """
        log("camera stream lost — reconnecting")
        self.state = "reconnecting"
        self.cand.release()
        while self._running:
            if should_stop():
                self.stop_requested = True
                self.state = "lost"
                with self._cond:
                    self._cond.notify_all()
                return False
            hit = try_open_index(self.cand.index, only_backend=self.cand.backend)
            if hit is None:
                hit = open_camera()
            if hit is not None:
                self.cand = hit
                self.state = "ok"
                self.reconnected += 1
                log(f"camera reconnected (index {hit.index}, {hit.backend})")
                return True
            time.sleep(1.0)
        return False

    def wait_frame(self, last_seq: int, timeout: float):
        with self._cond:
            if self._seq == last_seq:
                self._cond.wait(timeout)
            if self._seq == last_seq or self._frame is None:
                return None
            return self._seq, self._frame, self._t

    def stop(self) -> None:
        self._running = False
        self._thread.join(timeout=2.0)
        if not self._thread.is_alive():
            self.cand.release()


# =============================================================================
# Hand features
# =============================================================================

def _dist(a, b) -> float:
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(len(a))))


def _angle(a, b, c) -> float:
    """Angle (deg) between segments a→b and b→c. 0 = straight."""
    v1 = [b[i] - a[i] for i in range(len(a))]
    v2 = [c[i] - b[i] for i in range(len(a))]
    n1 = math.sqrt(sum(x * x for x in v1))
    n2 = math.sqrt(sum(x * x for x in v2))
    if n1 < 1e-9 or n2 < 1e-9:
        return 0.0
    cos = sum(v1[i] * v2[i] for i in range(len(a))) / (n1 * n2)
    return math.degrees(math.acos(max(-1.0, min(1.0, cos))))


def _mean(pts):
    n = float(len(pts))
    return tuple(sum(p[i] for p in pts) / n for i in range(len(pts[0])))


@dataclass
class HandObs:
    """One detected hand. `pts` are mirrored image coords (x→1-x, selfie view), 0..1."""

    pts: list
    world: list | None
    aspect: float = 4.0 / 3.0  # frame width / height

    @classmethod
    def from_result(cls, result, aspect: float) -> "HandObs | None":
        if not result.hand_landmarks:
    return None
        lms = result.hand_landmarks[0]
        pts = [(1.0 - float(p.x), float(p.y)) for p in lms]
        world = None
        if getattr(result, "hand_world_landmarks", None):
            wl = result.hand_world_landmarks[0]
            world = [(float(p.x), float(p.y), float(p.z)) for p in wl]
        return cls(pts, world, aspect)


@dataclass
class Features:
    fingers: list  # [thumb, index, middle, ring, pinky]
    pinch: float  # thumb↔index tip / wrist↔middle-MCP (2D)
    pinch_palm: float  # pinch point distance from palm centre (hand sizes)
    index_ang: float
    mid_pinch: float
    mid_palm: float
    mid_ang: float
    mid_far: float
    spread: float  # 0 = thumb at pinky, 1 = fully spread
    anchor: tuple  # cursor anchor (knuckles), mirrored image coords
    palm: tuple  # (index MCP + pinky MCP) / 2
    size: float  # hand size in image units (rotation-robust)
    aspect: float = 4.0 / 3.0
    thumb_ratio: float = 0.0  # thumb tip ↔ ring MCP / palm width (3D)


class FeatureTracker:
    """Landmarks → features, with per-finger hysteresis so states don't flicker."""

    def __init__(self) -> None:
        self.fingers = [0, 0, 0, 0, 0]

    def reset(self) -> None:
        self.fingers = [0, 0, 0, 0, 0]

    def update(self, obs: HandObs) -> Features:
        p = obs.pts
        w = obs.world if obs.world and len(obs.world) == 21 else None
        g = w if w is not None else p  # geometry source for angles / palm distances

        span_g = _dist(g[0], g[9]) or 1e-6
        palm_w = _dist(g[5], g[17]) or 1e-6
        fingers = [0, 0, 0, 0, 0]

        thumb_ratio = _dist(g[4], g[13]) / palm_w
        was = self.fingers[0]
        fingers[0] = 1 if thumb_ratio > (THUMB_OFF if was else THUMB_ON) else 0

        angs = []
        fars = []
        for k, mcp in enumerate((5, 9, 13, 17), start=1):
            pip, tip = mcp + 1, mcp + 3
            ang = _angle(g[mcp], g[pip], g[tip])
            far = _dist(g[tip], g[0]) / (_dist(g[pip], g[0]) or 1e-6)
            angs.append(ang)
            fars.append(far)
            if self.fingers[k]:
                up = ang < FINGER_OFF_ANG and far > FINGER_OFF_FAR
            else:
                up = ang < FINGER_ON_ANG and far > FINGER_ON_FAR
            fingers[k] = 1 if up else 0
        self.fingers = fingers

        span2 = _dist(p[0], p[9]) or 1e-6
        pinch = _dist(p[4], p[8]) / span2
        mid_pinch = _dist(p[4], p[12]) / span2
        palm_c = _mean([g[i] for i in (0, 5, 9, 13, 17)])
        pinch_palm = _dist(_mean([g[4], g[8]]), palm_c) / span_g
        mid_palm = _dist(_mean([g[4], g[12]]), palm_c) / span_g

        spread_ratio = _dist(g[4], g[20]) / palm_w
        spread = max(0.0, min(1.0, (spread_ratio - 1.05) / 2.15))

        ax = p[5][0] * 0.7 + p[9][0] * 0.3
        ay = p[5][1] * 0.7 + p[9][1] * 0.3
        palm = ((p[5][0] + p[17][0]) * 0.5, (p[5][1] + p[17][1]) * 0.5)
        size = max(span2, _dist(p[5], p[17]) * 1.25)
        return Features(
            fingers=fingers,
            pinch=pinch,
            pinch_palm=pinch_palm,
            index_ang=angs[0],
            mid_pinch=mid_pinch,
            mid_palm=mid_palm,
            mid_ang=angs[1],
            mid_far=fars[1],
            spread=spread,
            anchor=(ax, ay),
            palm=palm,
            size=size,
            aspect=obs.aspect,
            thumb_ratio=thumb_ratio,
        )


def classify_fingers(f) -> str | None:
    t, i, m, r, p = f
    n = i + m + r + p
    if n == 0:
        return "thumb" if t else "fist"
    if n == 4:
        return "palm" if t else "four"
    if i and not m and not r and not p:
        return "point"
    if i and m and not r and not p:
        return "victory"
    if i and m and r and not p:
        return "three"
    if i and p and not m and not r:
        return "ily" if t else "horns"
    if p and not i and not m and not r and t:
        return "shaka"
    return None


def window_engage(fingers, spread: float) -> bool:
    """Open palm: all 4 long fingers (or 3 + thumb) up and the thumb spread out.
    ILY / shaka / horns / three stay command poses."""
    t = fingers[0]
    other = sum(fingers[1:])
    return (other == 4 or (other == 3 and t == 1)) and spread >= WIN_ENGAGE_SPREAD


def window_keep(fingers, spread: float) -> bool:
    """While window mode is armed keep it at ANY open amount until fist/point/V."""
    t, i, m, r, p = fingers
    other = i + m + r + p
    total = t + other
    if total == 0:
            return False
    if other == 1 and i == 1 and t == 0:
        return False  # point
    if other == 2 and i == 1 and m == 1 and t == 0:
        return False  # victory / scroll
    return other >= 2 or spread >= WIN_KEEP_SPREAD or (t + p) >= 1


# =============================================================================
# Filters
# =============================================================================

class OneEuro2D:
    """One Euro filter (Casiez et al.): heavy smoothing when still, low lag when moving."""

    def __init__(self, min_cutoff: float, beta: float, d_cutoff: float) -> None:
        self.min_cutoff = min_cutoff
        self.beta = beta
        self.d_cutoff = d_cutoff
        self.reset()

    def reset(self) -> None:
        self.x = None
        self.dx = (0.0, 0.0)
        self.t = None

    @staticmethod
    def _alpha(cutoff: float, dt: float) -> float:
        tau = 1.0 / (2.0 * math.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)

    def __call__(self, x: tuple, t: float, scale: float = 1.0) -> tuple:
        """`scale` = units per "screen": beta is tuned for speed in screens/second,
        so the feel is the same on 1080p, 4K and multi-monitor desktops."""
        if self.x is None or self.t is None:
            self.x, self.t = x, t
            return x
        dt = max(1e-3, min(0.5, t - self.t))
        self.t = t
        raw_dx = ((x[0] - self.x[0]) / dt, (x[1] - self.x[1]) / dt)
        ad = self._alpha(self.d_cutoff, dt)
        self.dx = (
            ad * raw_dx[0] + (1 - ad) * self.dx[0],
            ad * raw_dx[1] + (1 - ad) * self.dx[1],
        )
        speed = math.hypot(*self.dx) / max(1e-6, scale)
        a = self._alpha(self.min_cutoff + self.beta * speed, dt)
        self.x = (a * x[0] + (1 - a) * self.x[0], a * x[1] + (1 - a) * self.x[1])
        return self.x


# =============================================================================
# Window controller (behaviour of the previous engine, now per-monitor + async)
# =============================================================================

def stage_rects(work: tuple, n: int) -> list[tuple[int, int, int, int]]:
    """Where each window goes, front to back.

    1 window  → centered card
    2 windows → card in front, large pane filling the right
    3 windows → card, left column, large right pane
    """
    left, top, right, bottom = work
    width = max(400, right - left)
    height = max(300, bottom - top)
    specs = [STAGE_CARD]
    if n >= 3:
        specs.append(STAGE_SIDE)
    if n >= 2:
        specs.append(STAGE_MAIN)
    out = []
    for fx, fy, fw, fh in specs[: max(1, n)]:
        w = max(240, int(round(width * fw)))
        h = max(160, int(round(height * fh)))
        x = left + int(round(width * fx))
        y = top + int(round(height * fy))
        if x + w > right:
            x = max(left, right - w)
        if y + h > bottom:
            y = max(top, bottom - h)
        out.append((x, y, w, h))
    return out


def _stabilize_delta(ddx: float, ddy: float) -> tuple[float, float]:
    """Kill micro-jitter, keep intentional palm moves."""
    mag = math.hypot(ddx, ddy)
    if mag < WIN_MOVE_DEAD:
        return 0.0, 0.0
    if mag < WIN_MOVE_SOFT:
        k = (mag - WIN_MOVE_DEAD) / max(WIN_MOVE_SOFT - WIN_MOVE_DEAD, 1e-6)
        k = max(0.0, min(1.0, k))
        k *= k
        return ddx * k, ddy * k
    return ddx, ddy


class WindowController:
    def __init__(self, desk: Desktop) -> None:
        self.desk = desk
        self.st: dict = {}
        self.hwnd = None

    @property
    def armed(self) -> bool:
        return self.hwnd is not None

    def arm(self) -> bool:
        hwnd = self.desk.foreground_target()
        if not hwnd:
                return False
        self.hwnd = hwnd
        self.st = {"work": self.desk.work_area(hwnd)}
            return True

    def disarm(self) -> None:
        self.hwnd = None
        self.st = {}

    def _targets(self) -> list:
        fn = getattr(self.desk, "visible_windows", None)
        wins = []
        if callable(fn):
            try:
                wins = list(fn(self.hwnd) or [])
        except Exception:
                wins = []
        if self.hwnd and self.hwnd not in wins:
            wins.insert(0, self.hwnd)
        return [h for h in wins if h][:3] or ([self.hwnd] if self.hwnd else [])

    def _place(self, hwnd, rect, z: str) -> None:
        x, y, w, h = rect
        fn = getattr(self.desk, "place_window", None)
        if callable(fn) and fn is not Desktop.place_window:
            fn(hwnd, x, y, w, h, z=z)
            return
        # Fake desktops only record set_rect. Real Desktop.set_rect places immediately.
        if z == "keep" or not hasattr(self.desk, "place_window"):
            self.desk.set_rect(hwnd, x, y, w, h)
            return
        self.desk.place_window(hwnd, x, y, w, h, z=z)

    def snap_stage(self) -> None:
        """Put the open windows into the stage layout in one shot."""
        wins = self._targets()
        if not wins:
            return
        work = self.st.get("work") or self.desk.work_area(wins[0])
        rects = stage_rects(work, len(wins))
        # Back pane first, card last, so the card stays in front.
        order = list(zip(wins, rects))
        for i, (hwnd, rect) in enumerate(reversed(order)):
            z = "bottom" if i == 0 and len(order) > 1 else "top"
            self._place(hwnd, rect, z)
        card = rects[0]
        self.st["card"] = card
        self.st["cx"] = card[0] + card[2] * 0.5
        self.st["cy"] = card[1] + card[3] * 0.5
        self.st["fw"], self.st["fh"] = float(card[2]), float(card[3])
        self.st["have"] = True
        self.st["is_max"] = False
        log("STAGE", len(wins))

    def update(self, open_s: float, nx: float, ny: float, now: float) -> str:
        hwnd = self.hwnd
        st = self.st
        if not hwnd or not self.desk.is_valid_window(hwnd):
            self.disarm()
            return "skip"

        raw = max(0.0, min(1.0, open_s))
        left, top, right, bottom = st["work"]
        aw = max(400, right - left)
        ah = max(300, bottom - top)

        if not st.get("snapped"):
            st["px"], st["py"] = nx, ny
            st["snapped"] = True
            if raw >= WIN_MAX_SPREAD:
                self.desk.maximize(hwnd)
                st["is_max"] = True
                st["t_set"] = now
                log("MAXIMIZE")
                return "maximize"
            self.snap_stage()
            st["t_set"] = now
            return "window"

        if raw >= WIN_MAX_SPREAD:
            if not st.get("is_max"):
                self.desk.maximize(hwnd)
                st["is_max"] = True
                st["t_set"] = now
                log("MAXIMIZE")
            st["px"], st["py"] = nx, ny
            return "maximize"

        if st.get("is_max"):
            self.desk.restore_if_zoomed(hwnd)
            st["is_max"] = False
            self.snap_stage()
            st["px"], st["py"] = nx, ny
            st["t_set"] = now
            return "window"

        card = st.get("card") or stage_rects(st["work"], 1)[0]
        ww, hh = int(card[2]), int(card[3])
        # A half-open palm keeps the card. Only a nearly closed hand shrinks it,
        # and it jumps there — it does not crawl for seconds.
        if raw < WIN_HOLD_SPREAD:
            frac = max(0.42, raw / max(WIN_HOLD_SPREAD, 1e-3))
            ww = max(240, int(card[2] * frac))
            hh = max(160, int(card[3] * frac))

        old_px = float(st.get("px", nx))
        old_py = float(st.get("py", ny))
        ddx, ddy = _stabilize_delta(nx - old_px, ny - old_py)
        st["px"], st["py"] = nx, ny
        cx = float(st.get("cx", card[0] + ww * 0.5))
        cy = float(st.get("cy", card[1] + hh * 0.5))
        cx += ddx * aw * WIN_MOVE_GAIN
        cy += ddy * ah * WIN_MOVE_GAIN
        x = int(round(cx - ww * 0.5))
        y = int(round(cy - hh * 0.5))
        x = max(left, min(right - ww, x))
        y = max(top, min(bottom - hh, y))
        st["cx"] = x + ww * 0.5
        st["cy"] = y + hh * 0.5
        st["fw"], st["fh"] = float(ww), float(hh)

        if (now - float(st.get("t_set", -1e9))) >= WIN_UPDATE_GAP_S:
            moved = (x, y, ww, hh) != st.get("placed")
            if moved:
                self.desk.set_rect(hwnd, x, y, ww, hh)
                st["placed"] = (x, y, ww, hh)
                st["t_set"] = now
        return "window"


class StageArranger:
    """When a window opens (camera running), drop the stack into the stage layout
    immediately. A stable set of windows is left where the user put it."""

    def __init__(self, desk) -> None:
        self.desk = desk
        self.last = None
        self.pending = None
        self.quiet_until = 0.0

    def _key(self, wins) -> tuple:
        # Membership only. Focusing another window changes z-order and must not
        # reflow the whole desktop.
        return tuple(sorted(int(h) for h in wins))

    def poll(self, paused: bool) -> None:
        fn = getattr(self.desk, "visible_windows", None)
        if not callable(fn):
            return
        try:
            wins = list(fn() or [])
        except Exception:
                        return
        key = self._key(wins)
        now = time.monotonic()
        if self.pending is None and now < self.quiet_until and not paused:
            # Absorb the resize animation, but don't miss a window that just opened.
            if self.last is not None and set(key) - set(self.last):
                self.pending = key
            else:
                self.last = key
                    return
        if paused:
            if self.last is not None and key != self.last:
                self.pending = key
            else:
                self.last = key
            return
        if self.pending is not None:
            self.pending = None
            try:
                wins = list(fn() or [])
                except Exception:
                return
            key = self._key(wins)
        if not wins or key == self.last:
            self.last = key
            return
        self.last = key
        self.quiet_until = now + 0.7
        self.apply(wins)

    def apply(self, wins) -> None:
        work = self.desk.work_area(wins[0])
        rects = stage_rects(work, len(wins))
        order = list(zip(wins, rects))
        for i, (hwnd, rect) in enumerate(reversed(order)):
            z = "bottom" if i == 0 and len(order) > 1 else "top"
            x, y, w, h = rect
            try:
                self.desk.place_window(hwnd, x, y, w, h, z=z)
            except Exception:
                log("stage place failed")
                return
        log("STAGE", len(wins))


# =============================================================================
# Gesture controller — pure state machine over Features (unit-testable)
# =============================================================================

@dataclass
class PinchState:
    state: str = "up"  # up | down | drag
    t_down: float = 0.0
    t_off: float | None = None
    t_last_on: float = 0.0
    frames_on: int = 0
    freeze: tuple | None = None


class GestureController:
    def __init__(self, desk, send_command=None) -> None:
        self.desk = desk
        self.send_command = send_command or (lambda cid: None)
        self.bindings: dict[str, str] = {}
        self.win = WindowController(desk)
        self.cursor_filter = OneEuro2D(CURSOR_MIN_CUTOFF, CURSOR_BETA, CURSOR_D_CUTOFF)
        self.reset_all()

    def reset_all(self) -> None:
        self.pose_cand = None
        self.pose_n = 0
        self.pose = None
        self.last_label = ""
        self.hand_size = None
        self.hand_size_t = None
        self.cursor_active = False
        self.cursor_last_px = None
        self.cursor_hist: collections.deque = collections.deque(maxlen=24)
        self.offset = (0.0, 0.0)
        self.offset_t = 0.0
        self.left = PinchState()
        self.right = PinchState()
        self.last_click_t = -1e9
        self.last_click_pos = None
        self.last_hand_t = -1e9
        self.engage_since = None
        self.scroll = None
        self.cmd_pose = None
        self.cmd_since = 0.0
        self.cmd_fired = False
        self.cmd_cool_until = 0.0
        self.fist_since = None
        self.fist_fired = False
        self.minimize_cool_until = 0.0
        self.win.disarm()
        self.cursor_filter.reset()

    # ---------------- helpers ----------------
    def _stable_pose(self, raw) -> str | None:
        if raw == self.pose_cand:
            self.pose_n += 1
    else:
            self.pose_cand = raw
            self.pose_n = 1
        if self.pose_n >= POSE_STABLE_FRAMES:
            self.pose = raw
        return self.pose

    def _update_hand_size(self, f: Features, now: float, force: bool = False) -> float:
        if self.hand_size is None:
            self.hand_size = f.size
        elif force:
            dt = max(0.0, now - (self.hand_size_t or now))
            a = 1.0 - math.exp(-dt / HAND_SIZE_TAU_S)
            self.hand_size += (f.size - self.hand_size) * a
        self.hand_size_t = now
        return self.hand_size

    def _screen_target(self, f: Features) -> tuple[float, float]:
        """Hand anchor → absolute screen pixel (float)."""
        sx0, sy0, sw, sh = self.desk.screen_rect()
        size = self.hand_size or f.size
        bw = max(CURSOR_BOX_MIN, min(CURSOR_BOX_MAX, size * CURSOR_BOX_K))
        # Same physical hand travel per pixel in x and y (per-monitor 16:9 feel).
        bh = min(0.9, bw * f.aspect * 0.5625)
        u = (f.anchor[0] - (0.5 - bw * 0.5)) / bw
        v = (f.anchor[1] - (CURSOR_BOX_CY - bh * 0.5)) / bh
        u = max(0.0, min(1.0, u))
        v = max(0.0, min(1.0, v))
        return sx0 + u * (sw - 1), sy0 + v * (sh - 1)

    def _current_offset(self, now: float) -> tuple[float, float]:
        ox, oy = self.offset
        if ox == 0.0 and oy == 0.0:
            return self.offset
        if self.left.state == "drag":
            return self.offset
        dt = max(0.0, now - self.offset_t)
        k = math.exp(-dt / OFFSET_DECAY_TAU_S)
        self.offset = (ox * k, oy * k)
        self.offset_t = now
        if abs(self.offset[0]) < 0.5 and abs(self.offset[1]) < 0.5:
            self.offset = (0.0, 0.0)
        return self.offset

    def _move_cursor(self, f: Features, now: float) -> None:
        tx, ty = self._screen_target(f)
        sx0, sy0, sw, sh = self.desk.screen_rect()
        fx, fy = self.cursor_filter((tx, ty), now, float(max(sw, sh)))
        self.cursor_hist.append((now, fx, fy))
        ox, oy = self._current_offset(now)
        x = int(round(max(sx0, min(sx0 + sw - 1, fx + ox))))
        y = int(round(max(sy0, min(sy0 + sh - 1, fy + oy))))
        last = self.cursor_last_px
        at_edge = x in (sx0, sx0 + sw - 1) or y in (sy0, sy0 + sh - 1)
        if (
            last is not None
            and not at_edge
            and math.hypot(x - last[0], y - last[1]) < CURSOR_DEADBAND_PX
        ):
            self.cursor_active = True
            return
        if last != (x, y):
            self.desk.set_cursor(x, y)
            self.cursor_last_px = (x, y)
        self.cursor_active = True

    def _rewound_cursor(self, now: float) -> tuple[int, int]:
        if not self.cursor_active or not self.cursor_hist:
            # Hand wasn't steering (or the real mouse moved since): click where the pointer is.
            return self.desk.cursor_pos()
        target = now - CURSOR_REWIND_S
        pos = self.cursor_hist[-1][1:]
        for t, x, y in self.cursor_hist:
            if t >= target:
                pos = (x, y)
                break
        ox, oy = self.offset
        return int(round(pos[0] + ox)), int(round(pos[1] + oy))

    def _release_cursor(self) -> None:
        self.cursor_active = False
        self.cursor_filter.reset()
        self.cursor_hist.clear()
        self.offset = (0.0, 0.0)

    # ---------------- pinch ----------------
    def _left_on(self, f: Features) -> bool:
        if self.left.state == "up":
            return (
                f.pinch < PINCH_ON
                and f.pinch_palm > PINCH_PALM_ON
                and f.index_ang < PINCH_INDEX_ANG_ON
                and f.pinch <= f.mid_pinch
            )
        return (
            f.pinch < PINCH_OFF
            and f.pinch_palm > PINCH_PALM_KEEP
            and f.index_ang < PINCH_INDEX_ANG_KEEP
        )

    def _right_on(self, f: Features) -> bool:
        if self.right.state == "up":
            return (
                f.mid_pinch < RIGHT_PINCH_ON
                and f.pinch > RIGHT_INDEX_CLEAR
                and f.mid_palm > RIGHT_PALM_ON
                and f.mid_ang < RIGHT_MID_ANG_MAX
                and f.mid_far > RIGHT_MID_FAR_MIN
            )
        return f.mid_pinch < RIGHT_PINCH_OFF and f.pinch > RIGHT_INDEX_CLEAR * 0.8

    def _press_start(self, ps: PinchState, now: float) -> None:
        ps.state = "down"
        ps.t_down = now
        ps.t_off = None
        ps.t_last_on = now
        ps.frames_on = 1
        pos = self._rewound_cursor(now)
        if (
            self.last_click_pos is not None
            and now - self.last_click_t <= self.desk.double_click_s
            and math.hypot(pos[0] - self.last_click_pos[0], pos[1] - self.last_click_pos[1])
            <= DOUBLE_CLICK_SNAP_PX
        ):
            pos = self.last_click_pos
        ps.freeze = pos
        self.desk.set_cursor(*pos)
        self.cursor_last_px = pos

    def _finish_left(self, now: float, cancel: bool = False) -> None:
        ps = self.left
        if ps.state == "drag":
            self.desk.mouse_button("left", False)
            self.last_label = "point"
            self.offset_t = now
            log("DROP")
            self.left = PinchState()
        return
        if ps.state == "down" and not cancel:
            dur = ps.t_last_on - ps.t_down + 1e-3
            if (
                ps.frames_on >= CLICK_MIN_FRAMES
                and dur >= CLICK_MIN_S - 1e-3
                and now - self.last_click_t >= CLICK_DEBOUNCE_S
            ):
                if ps.freeze:
                    self.desk.set_cursor(*ps.freeze)
                self.desk.click("left")
                self.last_click_t = now
                self.last_click_pos = ps.freeze
                self.last_label = "click"
                log("CLICK")
        if ps.freeze and self.cursor_hist:
            # Hand-anchor and frozen point differ slightly — fade that gap out.
            _, fx, fy = self.cursor_hist[-1]
            self.offset = (ps.freeze[0] - fx, ps.freeze[1] - fy)
            self.offset_t = now
        self.left = PinchState()

    def _finish_right(self, now: float, cancel: bool = False) -> None:
        ps = self.right
        if ps.state == "down" and not cancel:
            dur = ps.t_last_on - ps.t_down + 1e-3
            if ps.frames_on >= CLICK_MIN_FRAMES and CLICK_MIN_S - 1e-3 <= dur <= RIGHT_CLICK_MAX_S:
                if ps.freeze:
                    self.desk.set_cursor(*ps.freeze)
                self.desk.click("right")
                self.last_label = "right_click"
                log("RIGHT_CLICK")
        self.right = PinchState()

    def _update_pinches(self, f: Features, now: float) -> bool:
        """Returns True while a pinch owns the hand (cursor frozen or dragging)."""
        left_on = self._left_on(f) if self.right.state == "up" else False
        ps = self.left
        if left_on:
            if ps.state == "up":
                self._press_start(ps, now)
                self.last_label = "pinch"
            else:
                ps.t_off = None
                ps.t_last_on = now
                ps.frames_on += 1
                if ps.state == "down" and now - ps.t_down >= HOLD_ARM_S:
                    ps.state = "drag"
                    if ps.freeze:
                        self.desk.set_cursor(*ps.freeze)
                    self.desk.mouse_button("left", True)
                    log("HOLD")
                    # Drag starts exactly at the pressed point and then follows the hand.
                    self.cursor_filter.reset()
                    self.cursor_hist.clear()
                    fx, fy = self.cursor_filter(self._screen_target(f), now)
                    self.cursor_hist.append((now, fx, fy))
                    anchor = ps.freeze or (int(fx), int(fy))
                    self.offset = (anchor[0] - fx, anchor[1] - fy)
                    self.offset_t = now
                    self.cursor_active = True
                    self.last_label = "drag"
                    return True
            if ps.state == "drag":
                self._move_cursor(f, now)
            return True
        if ps.state != "up":
            if ps.t_off is None:
                ps.t_off = now
            if now - ps.t_off >= PINCH_RELEASE_S:
                self._finish_left(now)
                return False
            if ps.state == "drag":
                self._move_cursor(f, now)
            return True

        right_on = self._right_on(f)
        rs = self.right
        if right_on:
            if rs.state == "up":
                self._press_start(rs, now)
                self.last_label = "pinch"
            else:
                rs.t_off = None
                rs.t_last_on = now
                rs.frames_on += 1
            return True
        if rs.state != "up":
            if rs.t_off is None:
                rs.t_off = now
            if now - rs.t_off >= PINCH_RELEASE_S:
                self._finish_right(now)
                return False
            return True
        return False

    # ---------------- per-frame ----------------
    def on_no_hand(self, now: float) -> None:
        lost_for = now - self.last_hand_t
        if lost_for < HAND_LOST_GRACE_S:
        return
        if self.left.state != "up":
            self._finish_left(now, cancel=True)
        if self.right.state != "up":
            self._finish_right(now, cancel=True)
        if self.win.armed:
            self.win.disarm()
        self._release_cursor()
        self.pose = None
        self.pose_cand = None
        self.pose_n = 0
        self.engage_since = None
        self.scroll = None
        self.cmd_pose = None
        self.fist_since = None
        self.fist_fired = False

    def update(self, f: Features, now: float) -> None:
        self.last_hand_t = now
        raw_pose = classify_fingers(f.fingers)
        pose = self._stable_pose(raw_pose)

        # 1) Window mode is sticky once armed.
        if self.win.armed:
            if window_keep(f.fingers, f.spread):
                self.last_label = self.win.update(f.spread, f.palm[0], f.palm[1], now)
                return
            self.win.disarm()
            self.engage_since = None

        # 2) Pinches (left click / drag, right click).
        if self._update_pinches(f, now):
            self.engage_since = None
            self.scroll = None
            self.fist_since = None
            return

        # 3) Open palm held → window mode.
        if window_engage(f.fingers, f.spread):
            self.scroll = None
            self.fist_since = None
            if self.engage_since is None:
                self.engage_since = now
            elif now - self.engage_since >= WIN_ENGAGE_S:
                if self.win.arm():
                    self._release_cursor()
                    self.last_label = self.win.update(f.spread, f.palm[0], f.palm[1], now)
                else:
                    self.engage_since = now  # nothing to move; retry later
        return
        self.engage_since = None

        if pose != "victory":
            self.scroll = None
        if pose != "fist":
            self.fist_since = None
            self.fist_fired = False
        if pose not in COMMAND_POSES:
            self.cmd_pose = None

        if pose == "point":
            self._update_hand_size(f, now, force=True)
            self._move_cursor(f, now)
            if self.last_label not in ("click", "right_click"):
                self.last_label = "point"
        return

        self._release_cursor()
        if pose == "victory":
            self._victory(f, now)
        elif pose in COMMAND_POSES:
            self._command_pose(pose, now, CMD_HOLD_S)
        elif pose == "fist":
            self._fist(f, now)

    def _command_pose(self, pose: str, now: float, hold_s: float) -> bool:
        cid = self.bindings.get(pose)
        if self.cmd_pose != pose:
            self.cmd_pose = pose
            self.cmd_since = now
            self.cmd_fired = False
        if not cid:
            if self.last_label not in ("scroll_up", "scroll_down"):
                self.last_label = pose
            return False
        if (
            not self.cmd_fired
            and now >= self.cmd_cool_until
            and now - self.cmd_since >= hold_s
        ):
            self.cmd_fired = True
            self.cmd_cool_until = now + CMD_COOLDOWN_S
            self.last_label = pose
            log("CMD", pose, cid)
            self.send_command(cid)
            return True
        return False

    def _victory(self, f: Features, now: float) -> None:
        size = self._update_hand_size(f, now)
        y = f.anchor[1]
        sc = self.scroll
        if sc is None:
            sc = self.scroll = {"y0": y, "y": y, "t0": now, "t": now, "acc": 0.0, "moved": False}
            self.cmd_pose = None
        dt = max(0.0, min(0.2, now - sc["t"]))
        sc["t"] = now
        sc["y"] += (y - sc["y"]) * 0.5
        if now - sc["t0"] < SCROLL_SETTLE_S:
            sc["y0"] = sc["y"]
            return
        off = (sc["y0"] - sc["y"]) / max(size, 1e-3)  # hand up → positive → scroll up
        mag = abs(off)
        if mag <= SCROLL_DEAD:
            sc["acc"] = 0.0
            if not sc["moved"]:
                self._command_pose("victory", now, VICTORY_CMD_HOLD_S)
            elif self.last_label not in ("scroll_up", "scroll_down"):
                self.last_label = "victory"
            return
        sc["moved"] = True
        self.cmd_pose = None
        k = min(1.0, (mag - SCROLL_DEAD) / (SCROLL_FULL - SCROLL_DEAD))
        speed = SCROLL_MAX_NOTCHES_S * (k ** 1.5)
        sign = 1.0 if off > 0 else -1.0
        if sc["acc"] == 0.0 or (sc["acc"] > 0) != (sign > 0):
            sc["acc"] = sign * 0.7  # first notch right away, not after 1/speed
        sc["acc"] += sign * speed * dt
        notches = int(sc["acc"])  # truncates toward zero
        if notches:
            sc["acc"] -= notches
            self.desk.wheel(notches * 120)
            self.last_label = "scroll_up" if notches > 0 else "scroll_down"

    def _fist(self, f: Features, now: float) -> None:
        if self.fist_fired:
        return
        if f.thumb_ratio > FIST_THUMB_MAX:
            self.fist_since = None  # thumb half-out (thumbs-up/down seen at an angle)
        return
        if self.fist_since is None:
            self.fist_since = now
            return
        if now - self.fist_since >= FIST_MINIMIZE_S and now >= self.minimize_cool_until:
            self.fist_fired = True
            hwnd = self.desk.foreground_target()
            if hwnd and self.desk.minimize(hwnd):
                self.minimize_cool_until = now + MINIMIZE_COOLDOWN_S
                self.last_label = "minimize"
                log("MINIMIZE")

    def shutdown(self) -> None:
        if self.left.state == "drag":
            self.desk.mouse_button("left", False)
        self.left = PinchState()
        self.right = PinchState()


# =============================================================================
# IPC (constructor commands) — never blocks the tracking loop
# =============================================================================

def resolve_ipc_url() -> str:
    try:
        raw = IPC_PORT_FILE.read_text(encoding="utf-8")
        # Engine writes "port\\npid\\n" — use first non-empty line only.
        for line in raw.splitlines():
            line = line.strip()
            if not line:
                continue
            port = int(line)
            if 9712 <= port <= 9722:
                return f"ws://127.0.0.1:{port}"
            break
    except Exception:
        pass
    return "ws://127.0.0.1:9712"


def read_ipc_token() -> str | None:
    try:
        t = IPC_TOKEN_FILE.read_text(encoding="utf-8").strip()
        if len(t) >= 16:
            return t
        except Exception:
            pass
    return None


class IpcWorker:
    """One short-lived connection per command, on a background thread.

    The IPC server broadcasts voice/state events to every authenticated client;
    a long-lived socket that nobody reads eventually fills up and the server
    stops processing our commands. Connect → auth → send → close avoids that.
    """

    def __init__(self) -> None:
        self._q: queue.Queue = queue.Queue(maxsize=16)
        self._thread = threading.Thread(target=self._run, name="ipc", daemon=True)
        self._thread.start()

    def send_execute(self, command_id: str) -> None:
        if not command_id:
            return
        try:
            self._q.put_nowait(command_id)
        except queue.Full:
            log("IPC queue full — dropping", command_id)

    def _run(self) -> None:
        while True:
            cid = self._q.get()
            if cid is None:
                return
            for attempt in range(2):
                if self._deliver(cid):
                    break
                time.sleep(0.4)

    @staticmethod
    def _deliver(cid: str) -> bool:
        if websocket is None:
            log("IPC: websocket-client missing — command dropped", cid)
            return True
        token = read_ipc_token()
        if not token:
            log("IPC: no ipc.token — command dropped", cid)
            return True
        ws = None
        try:
            ws = websocket.create_connection(resolve_ipc_url(), timeout=2)
            ws.send(json.dumps({"action": "auth", "token": token}))
            deadline = time.monotonic() + 1.5
            authed = False
            while time.monotonic() < deadline:
                msg = ws.recv()
                if isinstance(msg, bytes):
                    msg = msg.decode("utf-8", "replace")
                if '"auth_ok"' in (msg or ""):
                    authed = True
                    break
            if not authed:
                log("IPC: auth not confirmed")
                return False
            ws.send(json.dumps({"action": "execute_command", "id": cid}))
            return True
        except Exception as e:
            log("IPC send failed:", e)
            return False
        finally:
            if ws is not None:
                try:
                    ws.close()
            except Exception:
                pass


class CommandBindings:
    def __init__(self) -> None:
        self._mtime = None
        self.map: dict[str, str] = {}

    def refresh(self) -> dict[str, str]:
        try:
            mtime = GESTURE_CMD_FILE.stat().st_mtime_ns
        except OSError:
            self._mtime = None
            self.map = {}
            return self.map
        if mtime == self._mtime:
            return self.map
        self._mtime = mtime
        try:
            raw = json.loads(GESTURE_CMD_FILE.read_text(encoding="utf-8"))
            out = {}
            if isinstance(raw, dict):
                for k, v in raw.items():
                    if k in COMMAND_POSES and isinstance(v, str) and v.strip():
                        out[k] = v.strip()
            self.map = out
    except Exception:
            pass
        return self.map


# =============================================================================
# Misc
# =============================================================================

def ensure_model() -> Path:
    for candidate in (MODEL_BUNDLED, MODEL_CACHE):
        try:
            if candidate.exists() and candidate.stat().st_size > 100_000:
                return candidate
        except OSError:
            pass
    MODEL_CACHE.parent.mkdir(parents=True, exist_ok=True)
    log("Downloading official MediaPipe hand_landmarker.task to", MODEL_CACHE)
    try:
        urllib.request.urlretrieve(MODEL_URL, MODEL_CACHE)
    except Exception as e:
        raise RuntimeError(
            "hand_landmarker.task missing and download failed. "
            "Reinstall JARVIS (resources/gestures must include the model). "
            f"Detail: {e}"
        ) from e
    if not MODEL_CACHE.exists() or MODEL_CACHE.stat().st_size < 100_000:
        raise RuntimeError("hand_landmarker.task download incomplete")
    return MODEL_CACHE


def should_stop() -> bool:
    """True when a real stop signal is present.

    Only APPDATA ``gestures.stop`` is authoritative. A leftover
    ``<install>/gestures.stop`` under Program Files often cannot be deleted by a
    normal user — treating that as a stop made the camera blink once then die
    forever after any elevated off/exit wrote the file.
    """
    hit = False
    try:
        if STOP_FILE.exists():
            hit = True
            try:
                STOP_FILE.unlink()
            except OSError:
                pass
    except OSError:
        pass
    # Legacy path: honor only if we can remove it (writable portable tree).
    # Unreadable/undeletable leftovers in Program Files are ignored.
    try:
        if LEGACY_STOP_FILE.exists():
            try:
                LEGACY_STOP_FILE.unlink()
                hit = True
            except OSError:
                pass
    except OSError:
        pass
    return hit


def persist_gestures_enabled(enabled: bool) -> None:
    """Keep Settings / next launch in sync when stopping via Esc."""
    path = STATUS_DIR / "app.db"
    if not path.is_file():
        return
    try:
        raw = path.read_text(encoding="utf-8-sig")
        data = json.loads(raw)
        if not isinstance(data, dict):
            return
        data["gestures_enabled"] = bool(enabled)
        tmp = path.with_suffix(".db.tmp")
        tmp.write_text(
            json.dumps(data, ensure_ascii=False, indent=4) + "\n",
            encoding="utf-8",
        )
        tmp.replace(path)
    except Exception:
        pass


def draw_preview(frame, obs: HandObs | None, text: str):
    disp = cv2.flip(frame, 1)
    h, w = disp.shape[:2]
    if obs is not None:
        pts = [(int(x * w), int(y * h)) for x, y in obs.pts]
        for a, b in HAND_CONNECTIONS:
            cv2.line(disp, pts[a], pts[b], (0, 255, 120), 2)
        for pt in pts:
            cv2.circle(disp, pt, 3, (0, 80, 255), -1)
    cv2.putText(disp, text, (12, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
    cv2.putText(
        disp,
        "index=cursor | pinch=click/drag | thumb+middle=right | V=scroll | palm=window | fist=min",
        (8, h - 14),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.42,
        (200, 200, 200),
        1,
    )
    return disp


# =============================================================================
# Main loop
# =============================================================================

def main() -> int:
    if not acquire_single_instance():
        log("gesture engine already running — exiting")
        return 0
    enable_dpi_awareness()
    disable_power_throttling()
    STATUS_DIR.mkdir(parents=True, exist_ok=True)
    cam_mode = read_camera_preference()

    try:
        model = ensure_model()
    except Exception as e:
        write_status(False, False, "", str(e), camera_mode=cam_mode)
        log(e)
        return 1

    try:
    PID_FILE.write_text(str(os.getpid()), encoding="ascii")
    except OSError:
        pass
    write_status(True, False, "", "starting camera", camera_mode=cam_mode)

    try:
        options = vision.HandLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=str(model)),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=1,
            min_hand_detection_confidence=0.55,
            min_hand_presence_confidence=0.55,
            min_tracking_confidence=0.5,
        )
        landmarker = vision.HandLandmarker.create_from_options(options)
    except Exception as e:
        write_status(False, False, "", f"mediapipe init failed: {e}", camera_mode=cam_mode)
        log("mediapipe init failed:", e)
        return 1

    t_open = time.monotonic()
    try:
        cand = open_camera()
    except Exception as e:
        write_status(False, False, "", f"camera error: {e}", camera_mode=cam_mode)
        log("camera error:", e)
        landmarker.close()
        return 1
    if cand is None:
        msg = (
            "no camera — enable Windows privacy: Settings → Privacy → Camera "
            "(allow desktop apps), plug in a USB webcam or free the built-in cam "
            "(close Zoom/Teams), then retry"
        )
        write_status(False, False, "", msg, camera_mode=cam_mode)
        log(msg)
        landmarker.close()
        return 1

    stream = CameraStream(cand)
    log(f"camera ready in {time.monotonic() - t_open:.1f}s")
    ready_msg = f"mediapipe ready ({stream.label})"
    if cand.dark:
        ready_msg = "camera image is black (privacy shutter closed or cover on the lens?)"
    write_status(True, True, "", ready_msg, camera_index=stream.index, camera_mode=cam_mode)

    desk = Desktop()
    stage = StageArranger(desk)
    ipc = IpcWorker()
    bindings = CommandBindings()
    ctl = GestureController(desk, ipc.send_execute)
    ctl.bindings = bindings.refresh()
    feats = FeatureTracker()
    esc = EscWatcher()

    win_name = "JARVIS Gestures (MediaPipe) - hold Esc to stop"
    if PREVIEW:
        cv2.namedWindow(win_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(win_name, 640, 480)

    stop_reason = "stopped"
    t0 = time.monotonic()
    last_ts = -1
    last_seq = 0
    last_proc = -1e9
    next_ctl = 0.0
    status_t = -1e9
    fps_n = 0
    fps_t = time.monotonic()
    fps = 0.0
    infer_ms = 0.0
    no_hand_since = time.monotonic()
    dark_since = None
    errors = 0
    last_err = ""
    have_hand = False

    try:
        while True:
            now = time.monotonic()
            if esc.poll(now):
                stop_reason = "stopped by Esc"
                persist_gestures_enabled(False)
                break
            if now >= next_ctl:
                next_ctl = now + CONTROL_EVERY_S
            if should_stop():
                stop_reason = "stopped"
                break
                ctl.bindings = bindings.refresh()
                try:
                    stage.poll(paused=ctl.win.armed or ctl.left.state == "drag")
                except Exception as e:
                    log("stage:", e)

            if stream.state == "lost":
                stop_reason = "stopped" if stream.stop_requested else "camera lost"
                break

            got = stream.wait_frame(last_seq, timeout=0.1)
            now = time.monotonic()
            if got is None:
                if stream.state == "reconnecting" and now - status_t > STATUS_EVERY_S:
                    write_status(
                        True, False, "", "reconnecting camera",
                        camera_index=stream.index, camera_mode=cam_mode,
                    )
                    status_t = now
                ctl.on_no_hand(now)
                continue
            seq, frame, t_cap = got
            last_seq = seq

            idle = now - no_hand_since > IDLE_AFTER_S
            interval = 1.0 / (IDLE_FPS if idle else MAX_FPS)
            if t_cap - last_proc < interval * 0.85:
                continue
            last_proc = t_cap

            if not frame_is_usable(frame):
                if dark_since is None:
                    dark_since = now
                ctl.on_no_hand(now)
                have_hand = False
                time.sleep(0.05)
                            else:
                dark_since = None
                obs = None
                try:
                    h, w = frame.shape[:2]
                    small = frame
                    if w > PROC_MAX_W:
                        small = cv2.resize(
                            frame, (PROC_MAX_W, max(1, int(h * PROC_MAX_W / w))),
                            interpolation=cv2.INTER_AREA,
                        )
                    rgb = cv2.cvtColor(small, cv2.COLOR_BGR2RGB)
                    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                    ts = int((t_cap - t0) * 1000)
                    if ts <= last_ts:
                        ts = last_ts + 1  # MediaPipe raises on non-increasing timestamps
                    last_ts = ts
                    ti = time.perf_counter()
                    result = landmarker.detect_for_video(image, ts)
                    infer_ms = infer_ms * 0.9 + (time.perf_counter() - ti) * 100.0
                    obs = HandObs.from_result(result, aspect=w / float(h))
                    if obs is None:
                        have_hand = False
                        feats.reset()
                        ctl.on_no_hand(t_cap)
                    else:
                        have_hand = True
                        no_hand_since = now
                        ctl.update(feats.update(obs), t_cap)
                    errors = 0
                except Exception as e:
                    errors += 1
                    sig = f"{type(e).__name__}: {e}"
                    if sig != last_err:
                        last_err = sig
                        log("frame error:", sig)
                        log(traceback.format_exc())
                    if errors > 150:
                        stop_reason = f"engine error: {sig}"
                        break
                fps_n += 1
            if PREVIEW:
                    disp = draw_preview(
                        frame, obs, f"{ctl.last_label or '-'}  {fps:.0f} fps  {infer_ms:.0f} ms"
                )
                    cv2.imshow(win_name, disp)
                key = cv2.waitKey(1) & 0xFF
                if key in (27, ord("q")):
                    stop_reason = "stopped by Esc"
                    persist_gestures_enabled(False)
                    break

            if now - fps_t >= 1.0:
                fps = fps_n / (now - fps_t)
                fps_n = 0
                fps_t = now
            if now - status_t > STATUS_EVERY_S:
                if dark_since is not None and now - dark_since > DARK_WARN_S:
                    msg = "camera image is black (privacy shutter closed or cover on the lens?)"
                else:
                    msg = "tracking"
                write_status(
                    True, True, ctl.last_label, msg,
                    camera_index=stream.index, camera_mode=cam_mode,
                    extra={
                        "fps": round(fps, 1),
                        "infer_ms": round(infer_ms, 1),
                        "hand": have_hand,
                        "camera_backend": stream.cand.backend,
                    },
                )
                status_t = now
    finally:
        try:
            ctl.shutdown()
        except Exception:
            pass
        stream.stop()
        try:
            landmarker.close()
        except Exception:
            pass
        if PREVIEW:
            try:
            cv2.destroyAllWindows()
            except Exception:
                pass
        write_status(False, False, "", stop_reason, camera_mode=cam_mode)
        try:
            PID_FILE.unlink(missing_ok=True)
        except Exception:
            pass
        log(stop_reason)
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ("--list-cameras", "list-cameras"):
        cams = probe_cameras()
        payload = {"cameras": cams, "preferred": read_camera_preference()}
        try:
            text = json.dumps(payload, ensure_ascii=False)
        except Exception:
            text = json.dumps(payload, ensure_ascii=True)
        try:
            print(text, flush=True)
        except UnicodeEncodeError:
            print(json.dumps(payload, ensure_ascii=True), flush=True)
        raise SystemExit(0)
    raise SystemExit(main())
