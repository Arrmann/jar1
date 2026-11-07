"""Fast Win32 window inventory with UIA only for the foreground tree.

The upstream Desktop enumerates every background window through UIA and virtual
desktop COM on every read. Background trees/properties are irrelevant to actions.
Keep its tested tree/input machinery, replace only snapshot assembly.
"""
from __future__ import annotations


class ForegroundDesktop:
    def __init__(self, delegate):
        self.delegate = delegate

    def __getattr__(self, name):
        return getattr(self.delegate, name)

    def _inventory(self, active_handle):
        import ctypes
        import win32gui
        import win32process
        from windows_use.agent.desktop.views import Window, Status
        from windows_use.agent.tree.views import BoundingBox
        windows = []
        def inspect(hwnd, _):
            if not win32gui.IsWindowVisible(hwnd):
                return
            title = win32gui.GetWindowText(hwnd).strip()
            if not title or win32gui.GetClassName(hwnd) in ('Progman', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd'):
                return
            # DWM cloak includes windows on other virtual desktops. Avoid the
            # slow per-window virtual-desktop COM calls used by the upstream.
            cloaked = ctypes.c_uint(0)
            if ctypes.windll.dwmapi.DwmGetWindowAttribute(hwnd,14,ctypes.byref(cloaked),4)==0 and cloaked.value:
                return
            left, top, right, bottom = win32gui.GetWindowRect(hwnd)
            minimized = bool(win32gui.IsIconic(hwnd))
            if (right <= left or bottom <= top) and not minimized:
                return
            _, pid = win32process.GetWindowThreadProcessId(hwnd)
            status = Status.MINIMIZED if minimized else Status.MAXIMIZED if ctypes.windll.user32.IsZoomed(hwnd) else Status.NORMAL
            windows.append(Window(name=title,is_browser=False,depth=len(windows),status=status,
                bounding_box=BoundingBox(left=left,top=top,right=right,bottom=bottom,width=right-left,height=bottom-top),
                handle=hwnd,process_id=pid))
        def visit(hwnd, data):
            import pywintypes
            try:
                inspect(hwnd,data)
            except (OSError,pywintypes.error):
                pass  # A closing background window must not abort the active tree.
        win32gui.EnumWindows(visit,None)
        return windows

    def get_state(self, as_bytes=False):
        import win32gui
        from windows_use.agent.desktop.views import DesktopState
        from windows_use.agent.tree.views import TreeState
        foreground = win32gui.GetForegroundWindow()
        # Window titles can change with every search/document; refresh at each
        # planner snapshot. Win32 enumeration has no per-window UIA traversal.
        windows = self._inventory(foreground)
        active = next((w for w in windows if w.handle == foreground),None)
        tree = self.delegate.tree.get_state(foreground,[]) if active else TreeState()
        state = DesktopState(active_window=active,windows=[w for w in windows if w.handle != foreground],
            active_desktop={},all_desktops=[],tree_state=tree,screenshot=None)
        self.delegate.desktop_state = state
        return state

    def get_windows(self,controls_handles=None):
        import win32gui
        windows=self._inventory(win32gui.GetForegroundWindow())
        return windows,{w.handle for w in windows}


def target_is_current(node, expected, uia):
    """Read the exact observed UIA object, not every element in its window.

    Cached properties alone are insufficient here: these must be current.
    Failure means refresh/replan before input, never silently pick a new node.
    """
    control = getattr(node,'control',None)
    if control is None:
        return False
    try:
        rect=control.BoundingRectangle
        if [rect.left,rect.top,rect.right,rect.bottom] != expected['rect']:
            return False
        if str(control.Name or '')[:180] != expected.get('_native_name',expected['name']) or not control.IsEnabled or control.IsOffscreen or control.IsPassword:
            return False
        # Hit-testing also detects a popup covering a control in the same app.
        hit = uia.ControlFromPoint(node.center.x,node.center.y)
        identity = tuple(control.GetRuntimeId())
        for _ in range(8):
            if hit is None:
                return False
            if tuple(hit.GetRuntimeId()) == identity:
                return True
            hit=hit.GetParentControl()
    except Exception:
        return False
    return False
