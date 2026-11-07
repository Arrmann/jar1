#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""JARVIS local Tuya / Smart Life Wi-Fi plug control.

Config: <JARVIS data dir>/tuya-plug.json
Actions: on | off | toggle | status | timer | timer_on | timer_cancel | setup | wizard
Timers: 10s | 30s | 1m | 5m | 10m | 30m | 1 | 2 | 3 | 4 (hours)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr, flush=True)


def config_dir() -> Path:
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
    appdata = Path(os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming"))
    return appdata / "com.jarvisn.assistant"


def cfg_path() -> Path:
    return config_dir() / "tuya-plug.json"


def default_cfg() -> dict:
    return {
        "version": 1,
        "default": "розетка",
        "devices": {},
        # Optional cloud keys for tinytuya wizard / scan:
        # "apiKey": "", "apiSecret": "", "apiRegion": "eu"
    }


def load_cfg() -> dict:
    path = cfg_path()
    if not path.is_file():
        return default_cfg()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return default_cfg()
        data.setdefault("version", 1)
        data.setdefault("default", "розетка")
        data.setdefault("devices", {})
        return data
    except Exception as ex:  # noqa: BLE001
        eprint(f"WARN:bad_cfg:{ex}")
        return default_cfg()


def save_cfg(cfg: dict) -> None:
    path = cfg_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def resolve_device(cfg: dict, name: str | None) -> tuple[str, dict]:
    devices = cfg.get("devices") or {}
    if not isinstance(devices, dict) or not devices:
        raise RuntimeError(
            "NO_DEVICE: сначала настрой розетку. Скажи «настрой розетку» "
            "или запусти: resources\\scripts\\tuya-plug.cmd setup"
        )
    key = (name or cfg.get("default") or "розетка").strip().lower()
    # Exact / alias match
    for k, v in devices.items():
        if not isinstance(v, dict):
            continue
        aliases = [str(k).lower()]
        aliases.extend(str(a).lower() for a in (v.get("aliases") or []) if a)
        if key in aliases:
            return str(k), v
    # Single device fallback
    if len(devices) == 1:
        only = next(iter(devices.items()))
        return str(only[0]), only[1] if isinstance(only[1], dict) else {}
    raise RuntimeError(f"UNKNOWN_DEVICE:{key}. Известны: {', '.join(devices.keys())}")


def parse_timer_seconds(value: str) -> int:
    raw = (value or "1").strip().lower().replace("ё", "е")
    if not raw:
        return 3600
    if raw.isdigit():
        n = int(raw)
        if 1 <= n <= 12:
            return n * 3600
        return max(1, n)
    m = re.match(
        r"^(\d+)\s*(s|sec|сек|секунд|секунды|секунду|m|min|мин|минут|минуты|минуту|"
        r"h|ч|hour|hours|час|часа|часов)$",
        raw,
    )
    if m:
        n = int(m.group(1))
        unit = m.group(2)
        if unit.startswith("s") or unit.startswith("сек"):
            return max(1, n)
        if unit.startswith("m") or unit.startswith("мин"):
            return max(1, n * 60)
        return max(1, n * 3600)
    return 3600


def make_device(dev: dict):
    try:
        import tinytuya  # type: ignore
    except ImportError as ex:
        raise RuntimeError(
            "NO_TINYTUYA: pip install tinytuya в runtime Python JARVIS"
        ) from ex

    device_id = str(dev.get("id") or dev.get("device_id") or "").strip()
    local_key = str(dev.get("local_key") or dev.get("key") or "").strip()
    ip = str(dev.get("ip") or "").strip()
    version = str(dev.get("version") or "3.3").strip() or "3.3"
    if not device_id or not local_key:
        raise RuntimeError("BAD_DEVICE: нужны id и local_key в tuya-plug.json")
    if not ip:
        # Try autodiscovers by id
        try:
            found = tinytuya.find_device(dev_id=device_id)
            if found and found.get("ip"):
                ip = found["ip"]
        except Exception:  # noqa: BLE001
            pass
    if not ip:
        raise RuntimeError("NO_IP: укажи ip розетки в конфиге (одна сеть с ПК)")

    d = tinytuya.OutletDevice(device_id, ip, local_key)
    d.set_version(float(version) if version.replace(".", "", 1).isdigit() else 3.3)
    d.set_socketTimeout(5)
    return d, device_id, ip


def switch_state(dev: dict, on: bool) -> dict:
    d, device_id, ip = make_device(dev)
    # DPS 1 is standard for plugs; some use 20/101
    dps_candidates = []
    if dev.get("dps") is not None:
        dps_candidates.append(int(dev["dps"]))
    dps_candidates.extend([1, 20, 101, 102])
    last_err = None
    for dps in dps_candidates:
        try:
            res = d.set_status(bool(on), switch=dps)
            return {
                "ok": True,
                "id": device_id,
                "ip": ip,
                "on": bool(on),
                "dps": dps,
                "raw": res,
            }
        except Exception as ex:  # noqa: BLE001
            last_err = ex
            continue
    raise RuntimeError(f"SET_FAILED:{last_err}")


def read_status(dev: dict) -> dict:
    d, device_id, ip = make_device(dev)
    try:
        data = d.status()
    except Exception as ex:  # noqa: BLE001
        raise RuntimeError(f"STATUS_FAILED:{ex}") from ex
    dps = (data or {}).get("dps") or {}
    on = None
    for key in ("1", "20", "101", "102"):
        if key in dps:
            on = bool(dps[key])
            break
    return {"ok": True, "id": device_id, "ip": ip, "on": on, "dps": dps, "raw": data}


def spawn_timer(seconds: int, fire_action: str, device_name: str) -> str:
    seconds = max(1, min(int(seconds), 7 * 24 * 3600))
    fire_action = "on" if str(fire_action).lower().strip() in ("on", "1", "enable") else "off"
    due = int(time.time()) + seconds
    timer_id = f"p{due}"
    cfg = load_cfg()
    cfg["timer_unix"] = due
    cfg["timer_id"] = timer_id
    cfg["timer_seconds"] = seconds
    cfg["timer_fire"] = fire_action
    cfg["timer_device"] = device_name
    save_cfg(cfg)

    script = str(Path(__file__).resolve())
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    if os.environ.get("JARVIS_CONFIG_DIR"):
        env["JARVIS_CONFIG_DIR"] = os.environ["JARVIS_CONFIG_DIR"]

    cmdline = (
        f'start /b "" "{sys.executable}" "{script}" '
        f'_timer_wait_sec {seconds} --device "{device_name}" '
        f"--timer-id {timer_id} --timer-action {fire_action}"
    )
    subprocess.Popen(
        ["cmd.exe", "/c", cmdline],
        cwd=str(Path(__file__).resolve().parent),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000),
        close_fds=True,
    )
    return timer_id


def cancel_timer() -> bool:
    cfg = load_cfg()
    had = bool(cfg.get("timer_unix") or cfg.get("timer_id"))
    for k in ("timer_unix", "timer_id", "timer_seconds", "timer_fire", "timer_device"):
        cfg.pop(k, None)
    save_cfg(cfg)
    return had


def wait_and_fire(seconds: int, timer_id: str, fire_action: str, device_name: str) -> int:
    seconds = max(1, int(seconds))
    deadline = time.time() + seconds
    while time.time() < deadline:
        cfg = load_cfg()
        if cfg.get("timer_id") != timer_id:
            print(f"OK:timer_cancelled:{timer_id}", flush=True)
            return 0
        time.sleep(min(1.0, max(0.2, deadline - time.time())))
    cfg = load_cfg()
    if cfg.get("timer_id") != timer_id:
        print(f"OK:timer_cancelled:{timer_id}", flush=True)
        return 0
    name, dev = resolve_device(cfg, device_name or cfg.get("timer_device"))
    on = fire_action == "on"
    switch_state(dev, on)
    for k in ("timer_unix", "timer_id", "timer_seconds", "timer_fire", "timer_device"):
        cfg.pop(k, None)
    cfg["last_action"] = f"timer_{fire_action}"
    save_cfg(cfg)
    print(f"OK:timer_fired:{fire_action}:{name}", flush=True)
    return 0


def cmd_setup_print() -> int:
    path = cfg_path()
    print("SETUP:Tuya/Smart Life plug for JARVIS", flush=True)
    print(
        "1) Вставь розетку в сеть, включи 2.4 GHz Wi‑Fi (5 GHz часто не видит).",
        flush=True,
    )
    print(
        "2) Поставь приложение Smart Life или Tuya Smart, зарегистрируй розетку.",
        flush=True,
    )
    print(
        "3) Нужны device_id + local_key. Проще всего: tinytuya wizard "
        "(нужен бесплатный проект на iot.tuya.com).",
        flush=True,
    )
    print(f"4) Конфиг JARVIS: {path}", flush=True)
    print(
        'Пример файла:\n'
        "{\n"
        '  "default": "розетка",\n'
        '  "devices": {\n'
        '    "розетка": {\n'
        '      "id": "bfxxxxxxxx",\n'
        '      "local_key": "xxxxxxxx",\n'
        '      "ip": "192.168.1.50",\n'
        '      "version": "3.3",\n'
        '      "dps": 1\n'
        "    }\n"
        "  }\n"
        "}",
        flush=True,
    )
    print(
        "5) После заполнения: tuya-plug.cmd on / off / status",
        flush=True,
    )
    print(
        "Голос: «включи розетку», «выключи розетку через 10 минут», "
        "«включи розетку через час».",
        flush=True,
    )
    # Ensure empty config exists
    if not path.is_file():
        save_cfg(default_cfg())
        print(f"OK:created_empty_cfg:{path}", flush=True)
    else:
        print(f"OK:cfg_exists:{path}", flush=True)
    return 0


def cmd_add_device(args: argparse.Namespace) -> int:
    cfg = load_cfg()
    name = (args.name or "розетка").strip().lower() or "розетка"
    device_id = (args.id or "").strip()
    local_key = (args.key or "").strip()
    ip = (args.ip or "").strip()
    version = (args.version or "3.3").strip() or "3.3"
    if not device_id or not local_key or not ip:
        raise RuntimeError("USAGE: add --name розетка --id ID --key LOCAL_KEY --ip 192.168.x.x")
    cfg.setdefault("devices", {})
    cfg["devices"][name] = {
        "id": device_id,
        "local_key": local_key,
        "ip": ip,
        "version": version,
        "dps": int(args.dps) if args.dps is not None else 1,
        "aliases": ["розетка", "socket", "plug", name],
    }
    cfg["default"] = name
    save_cfg(cfg)
    print(f"OK:added:{name}:{ip}", flush=True)
    return 0


def cmd_wizard() -> int:
    """Launch tinytuya wizard interactively if possible."""
    try:
        import tinytuya  # noqa: F401
    except ImportError:
        print("ERR:NO_TINYTUYA", flush=True)
        return 3
    print(
        "Открой в терминале (интерактивно):\n"
        f'  "{sys.executable}" -m tinytuya wizard\n'
        "Потом скопируй id/key/ip в tuya-plug.json или:\n"
        "  tuya-plug.cmd add --name розетка --id ... --key ... --ip ...",
        flush=True,
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="JARVIS Tuya smart plug")
    parser.add_argument(
        "action",
        help="on|off|toggle|status|timer|timer_on|timer_cancel|setup|wizard|add|_timer_wait_sec",
    )
    parser.add_argument("value", nargs="?", default="", help="timer duration e.g. 10s 5m 1")
    parser.add_argument("--device", default="", help="Device name in config")
    parser.add_argument("--timer-id", default="")
    parser.add_argument("--timer-action", default="off")
    parser.add_argument("--name", default="розетка")
    parser.add_argument("--id", default="")
    parser.add_argument("--key", default="")
    parser.add_argument("--ip", default="")
    parser.add_argument("--version", default="3.3")
    parser.add_argument("--dps", type=int, default=None)
    args = parser.parse_args()
    action = (args.action or "").strip().lower()

    try:
        if action == "setup":
            return cmd_setup_print()
        if action == "wizard":
            return cmd_wizard()
        if action == "add":
            return cmd_add_device(args)
        if action == "_timer_wait_sec":
            return wait_and_fire(
                parse_timer_seconds(args.value or "1"),
                args.timer_id or "",
                args.timer_action or "off",
                args.device or "",
            )

        cfg = load_cfg()
        name, dev = resolve_device(cfg, args.device or None)

        if action in ("on", "1", "enable"):
            switch_state(dev, True)
            cfg["last_action"] = "on"
            save_cfg(cfg)
            print(f"OK:on:{name}", flush=True)
            return 0
        if action in ("off", "0", "disable"):
            switch_state(dev, False)
            cfg["last_action"] = "off"
            save_cfg(cfg)
            print(f"OK:off:{name}", flush=True)
            return 0
        if action == "toggle":
            st = read_status(dev)
            on = not bool(st.get("on"))
            switch_state(dev, on)
            cfg["last_action"] = "on" if on else "off"
            save_cfg(cfg)
            print(f"OK:toggle:{'on' if on else 'off'}:{name}", flush=True)
            return 0
        if action == "status":
            st = read_status(dev)
            state = "on" if st.get("on") else ("off" if st.get("on") is False else "unknown")
            print(f"OK:status:{state}:{name}:{st.get('ip')}", flush=True)
            return 0
        if action in ("timer", "delay_off"):
            seconds = parse_timer_seconds(args.value or "1")
            tid = spawn_timer(seconds, "off", name)
            print(f"OK:timer_off:{seconds}s:{name}:{tid}", flush=True)
            return 0
        if action in ("timer_on", "delay_on"):
            seconds = parse_timer_seconds(args.value or "1")
            tid = spawn_timer(seconds, "on", name)
            print(f"OK:timer_on:{seconds}s:{name}:{tid}", flush=True)
            return 0
        if action in ("timer_cancel", "cancel"):
            had = cancel_timer()
            print(f"OK:timer_cancel:{'yes' if had else 'none'}", flush=True)
            return 0

        print(f"ERR:unknown_action:{action}", flush=True)
        return 2
    except Exception as ex:  # noqa: BLE001
        msg = str(ex).replace("\n", " ")
        print(f"ERR:{type(ex).__name__}:{msg}", flush=True)
        return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
