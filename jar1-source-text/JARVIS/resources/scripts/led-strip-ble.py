#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
JARVIS universal BLE LED strip controller (Lotus Lantern / ELK-BLEDOM family).

Works with controllers that advertise names like:
  ELK-BLEDOM, ELK-BLEDOB, MELK-*, LEDBLE-*, BLEDOM, …

No cloud API — local Bluetooth LE GATT writes (same protocol as Lotus Lantern).
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Iterable, Optional, Sequence, Tuple

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    print("ERR:bleak_missing", flush=True)
    sys.exit(2)

WRITE_UUIDS = (
    "0000fff3-0000-1000-8000-00805f9b34fb",  # ELK / MELK / Lotus Lantern
    "0000ffe1-0000-1000-8000-00805f9b34fb",  # LEDBLE / XROCKER variants
)

NAME_HINTS = (
    "elk-bledom",
    "elk-bledob",
    "elk-",
    "melk",
    "ledble",
    "bledom",
    "triones",
    "ledcontroller",
    "led-controller",
    "sp110e",
    "lotus",
    "lantern",
    "glamixie",
)

# Cheap ELK / Magic Home clones often advertise with an empty name on WinRT.
ELK_OUI = (
    "BE:37:",
    "BE:11:",
    "BE:10:",
    "F8:33:",
    "A4:C1:38:",
    "10:00:00:",
    "7B:A0:",
)

# Known solid colors (name -> RGB) — remote palette + extras
COLORS = {
    "red": (255, 0, 0),
    "green": (0, 255, 0),
    "blue": (0, 0, 255),
    "white": (255, 255, 255),
    "warm": (255, 180, 80),
    "cold": (180, 210, 255),
    "yellow": (255, 220, 0),
    "orange": (255, 120, 0),
    "purple": (160, 0, 255),
    "pink": (255, 40, 160),
    "cyan": (0, 220, 255),
    "turquoise": (0, 200, 180),
    "magenta": (255, 0, 200),
    "lime": (140, 255, 0),
    "gold": (255, 190, 40),
    "sky": (80, 180, 255),
    "ice": (200, 240, 255),
    "violet": (120, 0, 200),
    "coral": (255, 90, 80),
    "mint": (80, 255, 180),
    "teal": (0, 160, 160),
    "lightpink": (255, 160, 200),
    "lavender": (180, 120, 255),
}

# Russian aliases -> English key
COLOR_ALIASES = {
    "красный": "red",
    "красная": "red",
    "красным": "red",
    "зеленый": "green",
    "зелёный": "green",
    "зеленая": "green",
    "зелёная": "green",
    "синий": "blue",
    "синяя": "blue",
    "синим": "blue",
    "белый": "white",
    "белая": "white",
    "белым": "white",
    "желтый": "yellow",
    "жёлтый": "yellow",
    "оранжевый": "orange",
    "фиолетовый": "purple",
    "розовый": "pink",
    "голубой": "cyan",
    "бирюзовый": "turquoise",
    "малиновый": "magenta",
    "салатовый": "lime",
    "золотой": "gold",
    "теплый": "warm",
    "тёплый": "warm",
    "холодный": "cold",
    "небо": "sky",
    "ледяной": "ice",
    "лёд": "ice",
    "сиреневый": "violet",
    "коралловый": "coral",
    "мятный": "mint",
    "янтарный": "amber",
    "бирюза": "teal",
    "светло-розовый": "lightpink",
    "лавандовый": "lavender",
}

# Lotus Lantern / ELK pattern index 0..28 (sent as index|0x80)
# Matches remote + app pattern list (PatternData / CommandUtils).
EFFECTS = {
    # Static palette (remote color modes via pattern)
    "static_red": 0,
    "static_blue": 1,
    "static_green": 2,
    "static_cyan": 3,
    "static_yellow": 4,
    "static_purple": 5,
    "static_white": 6,
    # Jump / flash family
    "jump3": 7,
    "jump7": 8,
    "jump": 8,
    "rainbow": 8,
    "smooth": 8,
    # Cross-fade / fade
    "fade3": 9,
    "fade7": 10,
    "fade": 10,
    "crossfade": 10,
    # Gradual (breathe-like) per color
    "gradual_red": 11,
    "gradual_green": 12,
    "gradual_blue": 13,
    "gradual_yellow": 14,
    "gradual_cyan": 15,
    "gradual_purple": 16,
    "gradual_white": 17,
    "breathe": 17,
    # Two-color cross fade
    "fade_rg": 18,
    "fade_rb": 19,
    "fade_gb": 20,
    # Strobe / flash
    "strobe7": 21,
    "strobe": 21,
    "flash": 21,
    "strobe_red": 22,
    "strobe_green": 23,
    "strobe_blue": 24,
    "strobe_yellow": 25,
    "strobe_cyan": 26,
    "strobe_purple": 27,
    "strobe_white": 28,
}

EFFECT_ALIASES = {
    "радуга": "rainbow",
    "прыжки": "jump",
    "прыжок": "jump",
    "плавно": "smooth",
    "плавный": "smooth",
    "smooth": "smooth",
    "мигание": "flash",
    "мигать": "flash",
    "вспышки": "strobe",
    "вспышка": "strobe",
    "строб": "strobe",
    "затухание": "fade",
    "фейд": "fade",
    "fade": "fade",
    "дыхание": "breathe",
    "перелив": "crossfade",
    "переливы": "crossfade",
    "флеш": "flash",
    "flash": "flash",
    "strobe": "strobe",
    "jump": "jump",
    "три прыжка": "jump3",
    "семь прыжков": "jump7",
    "три фейда": "fade3",
    "семь фейдов": "fade7",
}


def config_path() -> Path:
    override = os.environ.get("JARVIS_CONFIG_DIR", "").strip()
    if override:
        base = Path(override)
    else:
        local = (os.environ.get("LOCALAPPDATA") or "").strip()
        base = None
        if local:
            pointer = Path(local) / "JARVIS" / "active-config-dir.txt"
            try:
                lines = pointer.read_text(encoding="utf-8").splitlines()
            except OSError:
                lines = []
            line = lines[0].strip() if lines else ""
            if line and Path(line).is_dir():
                base = Path(line)
        if base is None:
            appdata = Path(os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming"))
            base = appdata / "com.jarvisn.assistant"
    base.mkdir(parents=True, exist_ok=True)
    return base / "led-strip.json"


def load_cfg() -> dict:
    path = config_path()
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_cfg(cfg: dict) -> None:
    path = config_path()
    path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


def name_matches(name: Optional[str]) -> bool:
    if not name:
        return False
    low = name.strip().lower()
    return any(h in low for h in NAME_HINTS)


def _norm_addr(address: Optional[str]) -> str:
    return (address or "").strip().upper().replace("-", ":")


def _oui_matches(address: Optional[str]) -> bool:
    addr = _norm_addr(address)
    return any(addr.startswith(p) for p in ELK_OUI)


def cmd_on() -> bytes:
    return bytes.fromhex("7e0404f00001ff00ef")


def cmd_off() -> bytes:
    return bytes.fromhex("7e0404000000ff00ef")


def cmd_color(r: int, g: int, b: int) -> bytes:
    r = max(0, min(255, int(r)))
    g = max(0, min(255, int(g)))
    b = max(0, min(255, int(b)))
    return bytes([0x7E, 0x07, 0x05, 0x03, r, g, b, 0x10, 0xEF])


def cmd_brightness(pct: int) -> bytes:
    pct = max(1, min(100, int(pct)))
    # Lotus util sends percent 0..100 directly
    return bytes([0x7E, 0x04, 0x01, pct, 0xFF, 0xFF, 0xFF, 0x00, 0xEF])


def cmd_speed(pct: int) -> bytes:
    pct = max(0, min(100, int(pct)))
    return bytes([0x7E, 0x04, 0x02, pct, 0xFF, 0xFF, 0xFF, 0x00, 0xEF])


def cmd_effect(effect_id: int) -> bytes:
    # Pattern index 0..28 → mode byte with high bit (Lotus / CommandUtils)
    idx = max(0, min(28, int(effect_id)))
    mode = idx | 0x80
    return bytes([0x7E, 0x05, 0x03, mode, 0x03, 0xFF, 0xFF, 0x00, 0xEF])


def cmd_color_temp(warm: int, cold: int) -> bytes:
    warm = max(0, min(255, int(warm)))
    cold = max(0, min(255, int(cold)))
    return bytes([0x7E, 0x06, 0x05, 0x02, warm, cold, 0xFF, 0x08, 0xEF])


def cmd_mic(on: bool) -> bytes:
    return bytes([0x7E, 0x04, 0x07, 1 if on else 0, 0xFF, 0xFF, 0xFF, 0x00, 0xEF])


def cmd_mic_eq(mode: int) -> bytes:
    # 0 classic, 1 soft, 2 dynamic, 3 disco
    mode = max(0, min(3, int(mode)))
    return bytes([0x7E, 0x05, 0x03, mode | 0x80, 0x04, 0xFF, 0xFF, 0x00, 0xEF])


def cmd_mic_sensitivity(pct: int) -> bytes:
    pct = max(0, min(100, int(pct)))
    return bytes([0x7E, 0x04, 0x06, pct, 0xFF, 0xFF, 0xFF, 0x00, 0xEF])


def _adv_service_uuids(adv) -> list[str]:
    try:
        return [str(u).lower() for u in (getattr(adv, "service_uuids", None) or [])]
    except Exception:
        return []


def _looks_like_led_strip(name: Optional[str], adv=None, address: Optional[str] = None) -> bool:
    if name_matches(name) or name_matches(getattr(adv, "local_name", None) if adv is not None else None):
        return True
    if _oui_matches(address):
        return True
    if adv is None:
        return False
    uuids = _adv_service_uuids(adv)
    return any("fff0" in u or "ffe0" in u or "ffd5" in u or "fff3" in u for u in uuids)


async def _safe_disconnect(client: Optional[BleakClient]) -> None:
    if client is None:
        return
    try:
        await asyncio.wait_for(client.disconnect(), timeout=2.5)
    except Exception:
        pass


async def connect_led(
    address: str,
    timeout: float = 22.0,
    tries: int = 1,
    disconnected_callback=None,
) -> BleakClient:
    """Wake via advertisement, then give WinRT time to finish GATT.

    ELK-BLEDOM on Windows flaps ACTIVE/CLOSED for ~15s (UNREACHABLE retries).
    A 8s timeout looks like 'нашёл и сразу отвалилась'.
    """
    last: Optional[BaseException] = None
    addr = (address or "").strip()
    if not addr:
        raise RuntimeError("no_address")
    timeout = max(18.0, float(timeout))
    for i in range(max(1, tries)):
        target: object = addr
        try:
            found = await asyncio.wait_for(
                BleakScanner.find_device_by_address(addr, timeout=4.0),
                timeout=5.5,
            )
            if found is not None:
                target = found
        except Exception as e:
            last = e
        await asyncio.sleep(0.7)
        client = BleakClient(
            target,
            disconnected_callback=disconnected_callback,
            timeout=timeout,
            pair=False,
            winrt={"use_cached_services": False},
        )
        try:
            await client.connect()
            if client.is_connected:
                return client
            last = RuntimeError("not_connected")
        except Exception as e:
            last = e
        await _safe_disconnect(client)
        await asyncio.sleep(0.6 * (i + 1))
    raise RuntimeError(f"connect_failed:{last}")


async def probe_address(address: str, name: str = "LED") -> Optional[dict]:
    """Advertisement-only check. GATT connect+drop puts ELK chips to sleep."""
    addr = (address or "").strip()
    if not addr:
        return None
    try:
        dev = await asyncio.wait_for(
            BleakScanner.find_device_by_address(addr, timeout=4.0),
            timeout=5.5,
        )
    except Exception:
        return None
    if dev is None:
        return None
    label = (getattr(dev, "name", None) or name or "LED").strip() or "LED"
    return {"address": getattr(dev, "address", None) or addr, "name": label}


def _rank_led(dev: dict, cached: str) -> tuple:
    addr = _norm_addr(dev.get("address"))
    name = (dev.get("name") or "").lower()
    return (
        0 if cached and addr == cached else 1,
        0 if "bledom" in name or "lotus" in name else 1,
        0 if _oui_matches(addr) else 1,
        name,
    )


async def scan_devices(timeout: float = 10.0) -> list[dict]:
    """Find ELK / Lotus via advertisements. Never GATT-connect during a scan.

    A sleeping chip may not advertise. If we already know the MAC, keep it as
    a last-resort candidate so the next connect() can wake it.
    """
    cfg = load_cfg()
    cached = _norm_addr(cfg.get("address"))
    cached_name = (cfg.get("name") or "LED").strip() or "LED"
    timeout = max(5.0, float(timeout))

    found: dict[str, dict] = {}

    def consider(address: Optional[str], name: Optional[str], adv=None) -> None:
        if not address:
            return
        nm = (name or "").strip()
        if adv is not None and not nm:
            nm = (getattr(adv, "local_name", None) or "").strip()
        key = _norm_addr(address)
        is_cached = bool(cached and key == cached)
        if not is_cached and not _looks_like_led_strip(nm, adv, address):
            return
        label = nm or (cached_name if is_cached else "LED")
        prev = found.get(key)
        if not prev or (label not in ("", "LED") and (not prev.get("name") or prev["name"] == "LED")):
            found[key] = {"address": address, "name": label}

    def on_detect(device, advertisement_data) -> None:
        consider(
            getattr(device, "address", None),
            getattr(device, "name", None),
            advertisement_data,
        )

    if cached:
        hit = await probe_address(cfg.get("address") or "", cached_name)
        if hit:
            consider(hit.get("address"), hit.get("name"), None)
            if found:
                return [found[next(iter(found))]]

    try:
        async with BleakScanner(detection_callback=on_detect) as _scanner:
            await asyncio.sleep(timeout)
    except Exception:
        try:
            devices = await BleakScanner.discover(timeout=timeout)
            for d in devices:
                consider(d.address, d.name, None)
        except Exception:
            pass

    if not found and cached:
        found[cached] = {"address": (cfg.get("address") or "").strip(), "name": cached_name}

    items = list(found.values())
    items.sort(key=lambda x: _rank_led(x, cached))
    return items


async def resolve_address(preferred: Optional[str] = None) -> Tuple[str, str]:
    cfg = load_cfg()
    if preferred:
        return preferred, cfg.get("name") or "LED"

    cached = (cfg.get("address") or "").strip()
    cached_name = cfg.get("name") or "LED"
    if cached:
        return cached, cached_name

    found = await scan_devices()
    if not found:
        raise RuntimeError("no_device")
    found.sort(
        key=lambda x: (
            0 if "bledom" in (x["name"] or "").lower() else 1,
            0 if _oui_matches(x.get("address")) else 1,
            x["name"],
        )
    )
    pick = found[0]
    cfg["address"] = pick["address"]
    cfg["name"] = pick["name"]
    save_cfg(cfg)
    return pick["address"], pick["name"]


def _char_props(char) -> set[str]:
    raw = char.properties or []
    out = set()
    for p in raw:
        out.add(str(p).lower().replace("_", "-"))
    return out


def _pick_write_uuid(client: BleakClient, preferred: Optional[str] = None) -> str:
    """Pick GATT write characteristic for ELK / Lotus family."""
    preferred_l = (preferred or "").lower().strip()
    if preferred_l:
        return preferred_l

    services = getattr(client, "services", None)
    if services is None:
        return WRITE_UUIDS[0]

    candidates: list[tuple[int, str]] = []
    for svc in services:
        for char in svc.characteristics:
            props = _char_props(char)
            writable = ("write" in props) or ("write-without-response" in props)
            if not writable:
                continue
            uid = str(char.uuid).lower()
            if uid.startswith("0000fff3-"):
                score = 1
            elif uid.startswith("0000ffe1-"):
                score = 2
            elif "fff0" in str(getattr(svc, "uuid", "")).lower():
                score = 3
            else:
                score = 10
            candidates.append((score, uid))

    if not candidates:
        return WRITE_UUIDS[0]
    candidates.sort(key=lambda x: x[0])
    return candidates[0][1]


async def _write_once(client: BleakClient, uuid: str, payload: bytes) -> None:
    await asyncio.wait_for(client.write_gatt_char(uuid, payload, response=False), timeout=3.0)


async def write_payloads(address: str, payloads: Sequence[bytes]) -> str:
    """One BLE session, multiple writes. Returns address used."""
    if not payloads:
        return address

    cfg = load_cfg()
    cached_uuid = (cfg.get("write_uuid") or "").strip() or WRITE_UUIDS[0]
    last_err: Optional[BaseException] = None
    addr = address

    for attempt in range(1, 6):
        client = None
        try:
            if attempt == 1:
                release_radio(wait_s=0.45)
            if attempt >= 4:
                found = await scan_devices(timeout=6.0)
                if found:
                    addr = found[0]["address"]
                    cfg["address"] = addr
                    cfg["name"] = found[0].get("name") or cfg.get("name") or "LED"
                    save_cfg(cfg)

            client = await connect_led(addr, timeout=22.0, tries=1)
            uuid = cached_uuid
            wrote = False
            try:
                for i, payload in enumerate(payloads):
                    await _write_once(client, uuid, payload)
                    if i + 1 < len(payloads):
                        await asyncio.sleep(0.04)
                wrote = True
            except Exception:
                uuid = _pick_write_uuid(client, None)
                for i, payload in enumerate(payloads):
                    try:
                        await _write_once(client, uuid, payload)
                    except Exception:
                        await asyncio.wait_for(
                            client.write_gatt_char(uuid, payload, response=True),
                            timeout=3.0,
                        )
                    if i + 1 < len(payloads):
                        await asyncio.sleep(0.04)
                wrote = True

            if wrote:
                if cfg.get("write_uuid") != uuid or cfg.get("address") != addr:
                    cfg["write_uuid"] = uuid
                    cfg["address"] = addr
                    save_cfg(cfg)
                return addr
        except Exception as e:
            last_err = e
            cached_uuid = WRITE_UUIDS[0]
            await asyncio.sleep(0.4 * attempt)
        finally:
            if client is not None:
                await _safe_disconnect(client)

    raise RuntimeError(f"write_failed:{last_err}")


async def write_payload(address: str, payload: bytes) -> str:
    return await write_payloads(address, [payload])


def parse_color(name: str) -> Tuple[int, int, int]:
    raw = (name or "").strip().lower()
    if not raw:
        raise ValueError("empty_color")
    # #RRGGBB
    m = re.fullmatch(r"#?([0-9a-f]{6})", raw)
    if m:
        hx = m.group(1)
        return int(hx[0:2], 16), int(hx[2:4], 16), int(hx[4:6], 16)
    # r,g,b
    m = re.fullmatch(r"(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})", raw)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    key = COLOR_ALIASES.get(raw, raw)
    if key in COLORS:
        return COLORS[key]
    raise ValueError(f"unknown_color:{name}")


def parse_effect(name: str) -> int:
    raw = (name or "").strip().lower()
    if not raw:
        raise ValueError("empty_effect")
    if re.fullmatch(r"\d{1,2}", raw):
        return max(0, min(28, int(raw)))
    key = EFFECT_ALIASES.get(raw, raw)
    if key in EFFECTS:
        return EFFECTS[key]
    for alias, target in EFFECT_ALIASES.items():
        if alias in raw and target in EFFECTS:
            return EFFECTS[target]
    for ename, eid in EFFECTS.items():
        if ename.replace("_", " ") in raw or ename in raw:
            return eid
    raise ValueError(f"unknown_effect:{name}")


def parse_speed(value: str) -> int:
    raw = (value or "").strip().lower()
    if raw in ("faster", "быстрее", "быстро", "max", "макс"):
        cfg = load_cfg()
        cur = int(cfg.get("last_speed") or 50)
        return min(100, cur + 20)
    if raw in ("slower", "медленнее", "медленно", "min", "мин"):
        cfg = load_cfg()
        cur = int(cfg.get("last_speed") or 50)
        return max(0, cur - 20)
    m = re.search(r"(\d{1,3})", raw)
    if m:
        return max(0, min(100, int(m.group(1))))
    return 50


def parse_brightness_value(value: str) -> int:
    raw = (value or "").strip().lower().replace("ё", "е")
    cfg = load_cfg()
    cur = int(cfg.get("last_brightness") or 80)
    if raw in ("up", "ярче", "+", "plus"):
        return min(100, cur + 15)
    if raw in ("down", "тусклее", "темнее", "-", "minus"):
        return max(1, cur - 15)
    if raw in ("max", "макс", "максимум", "полная", "максимальная"):
        return 100
    if raw in ("min", "мин", "минимум", "минимальная"):
        return 10
    # Explicit levels L1..L5 (voice: яркость ленты 1..5)
    m_lvl = re.fullmatch(r"l(?:evel)?\s*([1-5])", raw)
    if m_lvl:
        return {1: 20, 2: 40, 3: 60, 4: 80, 5: 100}[int(m_lvl.group(1))]
    m = re.search(r"(\d{1,3})", raw)
    if m:
        return max(1, min(100, int(m.group(1))))
    return cur


async def run_action(args: argparse.Namespace) -> int:
    action = args.action.lower().strip()

    if action == "_timer_wait_sec":
        seconds = max(1, min(7 * 24 * 3600, int(args.value or "1")))
        timer_id = (getattr(args, "timer_id", "") or "").strip()
        fire = (getattr(args, "timer_action", "") or "").strip().lower()
        if fire not in ("on", "off"):
            cfg0 = load_cfg()
            fire = str(cfg0.get("timer_fire") or "off").lower()
        if fire not in ("on", "off"):
            fire = "off"
        payload = cmd_on() if fire == "on" else cmd_off()
        end = time.time() + seconds
        while time.time() < end:
            cfg = load_cfg()
            if not cfg.get("timer_off_unix"):
                print("OK:timer_aborted", flush=True)
                return 0
            if timer_id and cfg.get("timer_id") and str(cfg.get("timer_id")) != timer_id:
                print("OK:timer_superseded", flush=True)
                return 0
            await asyncio.sleep(min(0.5, max(0.05, end - time.time())))

        cfg = load_cfg()
        if not cfg.get("timer_off_unix"):
            print("OK:timer_aborted", flush=True)
            return 0
        if timer_id and cfg.get("timer_id") and str(cfg.get("timer_id")) != timer_id:
            print("OK:timer_superseded", flush=True)
            return 0

        used = None
        last_err: Optional[BaseException] = None
        # Prefer warm daemon — it already owns the BLE link on Windows.
        # A second direct BleakClient often fails with "Device was not found".
        if ensure_daemon(wait_s=2.5):
            for _try in range(4):
                cfg = load_cfg()
                if not cfg.get("timer_off_unix"):
                    print("OK:timer_aborted", flush=True)
                    return 0
                resp = try_daemon_request(fire, "", "", timeout=0.8)
                if resp and resp.startswith("OK:"):
                    cancel_led_timer()
                    print(f"OK:timer_{fire}_daemon:{resp}", flush=True)
                    return 0
                if resp:
                    last_err = RuntimeError(resp)
                await asyncio.sleep(0.6)

        deadline = time.time() + 45.0
        attempt = 0
        while time.time() < deadline:
            cfg = load_cfg()
            if not cfg.get("timer_off_unix"):
                print("OK:timer_aborted", flush=True)
                return 0
            attempt += 1
            try:
                # Always rescan — cached address goes stale under Windows BLE
                found = await scan_devices(timeout=3.5)
                if found:
                    address = found[0]["address"]
                    cfg = load_cfg()
                    cfg["address"] = address
                    cfg["name"] = found[0].get("name") or cfg.get("name") or "LED"
                    save_cfg(cfg)
                else:
                    address, _name = await resolve_address(None)
                used = await write_payloads(address, [payload])
                last_err = None
                break
            except Exception as e:
                last_err = e
                await asyncio.sleep(1.0)

        cancel_led_timer()
        if used is None:
            print(f"ERR:timer_{fire}_failed:{last_err}", flush=True)
            return 1
        print(f"OK:timer_{fire}:{used}", flush=True)
        return 0

    if action == "_timer_wait":
        # Legacy hours path
        hours = max(1, min(12, int(args.value or "1")))
        args.value = str(hours * 3600)
        args.action = "_timer_wait_sec"
        return await run_action(args)

    if action in ("timer_cancel", "cancel_timer"):
        had = cancel_led_timer()
        print("OK:timer_cancelled" if had else "OK:timer_none", flush=True)
        return 0

    if action == "scan":
        release_radio(wait_s=0.55)
        found = await scan_devices(timeout=float(args.timeout))
        print(json.dumps({"ok": True, "devices": found}, ensure_ascii=False), flush=True)
        if args.save and found:
            cfg = load_cfg()
            cfg["address"] = found[0]["address"]
            cfg["name"] = found[0]["name"]
            save_cfg(cfg)
            print(f"OK:saved:{found[0]['address']}", flush=True)
        elif not found:
            print("ERR:no_device", flush=True)
            return 1
        return 0

    if action == "forget":
        path = config_path()
        if path.exists():
            path.unlink()
        print("OK:forgotten", flush=True)
        return 0

    if action == "status":
        cfg = load_cfg()
        print(json.dumps({"ok": True, "config": cfg, "path": str(config_path())}, ensure_ascii=False), flush=True)
        return 0

    address, name = await resolve_address(args.address)
    payloads: list[bytes] = []
    value = args.value or ""

    if action in ("on", "enable", "включить"):
        payloads = [cmd_on()]
    elif action in ("off", "disable", "выключить"):
        payloads = [cmd_off()]
    elif action in ("color", "цвет"):
        r, g, b = parse_color(value or args.color or "")
        payloads = [cmd_on(), cmd_color(r, g, b)]
    elif action in ("brightness", "яркость"):
        pct = parse_brightness_value(value or args.brightness or "80")
        payloads = [cmd_on(), cmd_brightness(pct)]
        cfg0 = load_cfg()
        cfg0["last_brightness"] = pct
        save_cfg(cfg0)
    elif action in ("speed", "скорость"):
        pct = parse_speed(value or "50")
        payloads = [cmd_speed(pct)]
        cfg0 = load_cfg()
        cfg0["last_speed"] = pct
        save_cfg(cfg0)
    elif action in ("effect", "эффект", "mode", "режим", "pattern"):
        eid = parse_effect(value or args.effect or "rainbow")
        payloads = [cmd_on(), cmd_effect(eid)]
    elif action in ("warm", "тёплый", "теплый"):
        payloads = [cmd_on(), cmd_color_temp(255, 40)]
    elif action in ("cold", "холодный", "cool"):
        payloads = [cmd_on(), cmd_color_temp(40, 255)]
    elif action in ("colortemp", "temp", "температура"):
        # value "warm,cold" or single word
        raw = (value or "200,80").lower()
        if "холод" in raw or raw == "cold":
            payloads = [cmd_on(), cmd_color_temp(40, 255)]
        elif "тепл" in raw or "тёпл" in raw or raw == "warm":
            payloads = [cmd_on(), cmd_color_temp(255, 40)]
        else:
            parts = raw.replace(" ", "").split(",")
            if len(parts) == 2:
                payloads = [cmd_on(), cmd_color_temp(int(parts[0]), int(parts[1]))]
            else:
                payloads = [cmd_on(), cmd_color_temp(200, 80)]
    elif action in ("mic_on", "микрофон"):
        payloads = [cmd_mic(True), cmd_mic_eq(int(value or "2")), cmd_mic_sensitivity(30)]
    elif action in ("mic_off",):
        payloads = [cmd_mic(False)]
    elif action in ("mic_eq", "music"):
        mode = int(value or "1")
        if mode >= 1:
            mode = mode - 1
        mode = max(0, min(3, mode))
        payloads = [cmd_mic(True), cmd_mic_eq(mode), cmd_mic_sensitivity(35)]
    elif action in ("mic_sens", "mic_sensitivity"):
        payloads = [cmd_mic_sensitivity(int(value or "30"))]
    elif action in ("auto",):
        payloads = [cmd_on(), cmd_effect(EFFECTS["fade7"])]
    elif action in ("quick",):
        payloads = [cmd_speed(100)]
        cfg0 = load_cfg()
        cfg0["last_speed"] = 100
        save_cfg(cfg0)
    elif action in ("slow",):
        payloads = [cmd_speed(10)]
        cfg0 = load_cfg()
        cfg0["last_speed"] = 10
        save_cfg(cfg0)
    elif action in ("moon", "night"):
        level = int(value or "1")
        pct = {1: 15, 2: 40, 3: 70, 4: 100}.get(level, 40)
        payloads = [cmd_on(), cmd_brightness(pct)]
        cfg0 = load_cfg()
        cfg0["last_brightness"] = pct
        save_cfg(cfg0)
    elif action == "timer":
        seconds = parse_timer_seconds(value or "1")
        tid = spawn_timer(seconds, "off")
        used = address
        try:
            used = await write_payloads(address, [cmd_on()])
        except Exception as e:
            print(f"WARN:timer_on_failed:{e}", flush=True)
        cfg = load_cfg()
        cfg["address"] = used
        cfg["name"] = name
        cfg["last_action"] = f"timer_off_{seconds}s"
        if not cfg.get("timer_id"):
            cfg["timer_id"] = tid
            cfg["timer_seconds"] = seconds
            cfg["timer_off_unix"] = int(time.time()) + seconds
            cfg["timer_fire"] = "off"
        save_cfg(cfg)
        print(f"OK:timer:{seconds}s:{used}:{tid}", flush=True)
        return 0
    elif action in ("timer_on", "delay_on"):
        seconds = parse_timer_seconds(value or "1")
        tid = spawn_timer(seconds, "on")
        cfg = load_cfg()
        cfg["address"] = address
        cfg["name"] = name
        cfg["last_action"] = f"timer_on_{seconds}s"
        if not cfg.get("timer_id"):
            cfg["timer_id"] = tid
            cfg["timer_seconds"] = seconds
            cfg["timer_off_unix"] = int(time.time()) + seconds
            cfg["timer_fire"] = "on"
        save_cfg(cfg)
        print(f"OK:timer_on:{seconds}s:{address}:{tid}", flush=True)
        return 0
    elif action in ("timer_cancel", "cancel_timer"):
        had = cancel_led_timer()
        print("OK:timer_cancelled" if had else "OK:timer_none", flush=True)
        return 0
    elif action == "rgb":
        parts = (value or "").replace(" ", "").split(",")
        if len(parts) != 3:
            raise ValueError("rgb_needs_r,g,b")
        r, g, b = (int(parts[0]), int(parts[1]), int(parts[2]))
        payloads = [cmd_on(), cmd_color(r, g, b)]
    else:
        raise ValueError(f"unknown_action:{action}")

    used = await write_payloads(address, payloads)
    cfg = load_cfg()
    cfg["address"] = used
    cfg["name"] = name
    cfg["last_action"] = action
    if action in ("effect", "эффект", "mode", "режим", "pattern"):
        cfg["last_effect"] = value or args.effect or "rainbow"
    save_cfg(cfg)
    print(f"OK:{action}:{used}", flush=True)
    return 0


DAEMON_HOST = "127.0.0.1"
DAEMON_PORT = 38473
# Keep the GATT link. ELK-BLEDOM sleeps after a drop and WinRT often cannot
# reconnect for tens of seconds. A 25s idle disconnect looked like "отвалилась".
DAEMON_KEEPALIVE_S = 8.0
DAEMON_EXIT_IDLE_S = 1800.0


def daemon_port_file() -> Path:
    return config_path().with_name("led-strip-daemon.port")


def try_daemon_request(
    action: str,
    value: str = "",
    address: str = "",
    timeout: float = 0.2,
    recv_timeout: float = 12.0,
) -> Optional[str]:
    """Send one command to warm daemon. Returns response line or None if daemon down."""
    try:
        with socket.create_connection((DAEMON_HOST, DAEMON_PORT), timeout=timeout) as sock:
            sock.settimeout(max(4.0, float(recv_timeout)))
            req = json.dumps(
                {"action": action, "value": value or "", "address": address or ""},
                ensure_ascii=False,
            ) + "\n"
            sock.sendall(req.encode("utf-8"))
            buf = b""
            while b"\n" not in buf:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                buf += chunk
            return buf.decode("utf-8", errors="replace").strip()
    except OSError:
        return None


def release_radio(wait_s: float = 0.55) -> None:
    """Drop the daemon GATT session so WinRT scan/connect can use the radio."""
    resp = try_daemon_request("disconnect", timeout=0.4, recv_timeout=4.0)
    if resp is None:
        return
    time.sleep(max(0.25, float(wait_s)))


def spawn_daemon() -> None:
    flags = 0
    if sys.platform == "win32":
        flags = getattr(subprocess, "DETACHED_PROCESS", 0x00000008) | getattr(
            subprocess, "CREATE_NO_WINDOW", 0x08000000
        )
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "daemon"],
        cwd=str(Path(__file__).resolve().parent),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=flags,
        close_fds=True,
    )


def parse_timer_seconds(value: str) -> int:
    """Parse remote '1'..'4' as hours, or '30m' / '10s' / '2h' / plain seconds."""
    raw = (value or "1").strip().lower().replace("ё", "е")
    if not raw:
        return 3600
    if raw.isdigit():
        n = int(raw)
        if 1 <= n <= 4:
            return n * 3600
        return max(1, n)
    m = re.match(
        r"^(\d+)\s*(s|sec|сек|секунд|секунды|секунду|m|min|мин|минут|минуты|минуту|h|ч|hour|hours|час|часа|часов)$",
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


def spawn_timer(seconds: int, fire_action: str = "off") -> str:
    """Durable background ON/OFF timer: detached Python waiter + due in config."""
    seconds = max(1, min(int(seconds), 7 * 24 * 3600))
    fire_action = "on" if str(fire_action).lower().strip() in ("on", "1", "enable") else "off"
    due = int(time.time()) + seconds
    timer_id = f"t{due}"
    cfg = load_cfg()
    cfg["timer_off_unix"] = due
    cfg["timer_id"] = timer_id
    cfg["timer_seconds"] = seconds
    cfg["timer_fire"] = fire_action
    save_cfg(cfg)

    script = str(Path(__file__).resolve())
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    if os.environ.get("JARVIS_CONFIG_DIR"):
        env["JARVIS_CONFIG_DIR"] = os.environ["JARVIS_CONFIG_DIR"]

    if sys.platform == "win32":
        cmdline = (
            f'start /b "" "{sys.executable}" "{script}" '
            f'_timer_wait_sec {seconds} --direct --timer-id {timer_id} --timer-action {fire_action}'
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
    else:
        subprocess.Popen(
            [
                sys.executable,
                script,
                "_timer_wait_sec",
                str(seconds),
                "--direct",
                "--timer-id",
                timer_id,
                "--timer-action",
                fire_action,
            ],
            cwd=str(Path(__file__).resolve().parent),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    return timer_id


def cancel_led_timer() -> bool:
    cfg = load_cfg()
    had = bool(cfg.get("timer_off_unix") or cfg.get("timer_id"))
    cfg.pop("timer_off_unix", None)
    cfg.pop("timer_id", None)
    cfg.pop("timer_hours", None)
    cfg.pop("timer_seconds", None)
    cfg.pop("timer_fire", None)
    save_cfg(cfg)
    return had


def ensure_daemon(wait_s: float = 2.0) -> bool:
    if try_daemon_request("ping", timeout=0.15) is not None:
        return True
    spawn_daemon()
    deadline = time.time() + wait_s
    while time.time() < deadline:
        if try_daemon_request("ping", timeout=0.15) is not None:
            return True
        time.sleep(0.08)
    return False


class LedSession:
    """Warm BLE session shared by daemon requests."""

    def __init__(self) -> None:
        self.client: Optional[BleakClient] = None
        self.address: str = ""
        self.uuid: str = WRITE_UUIDS[0]
        self.last_used = time.time()
        self.last_command = time.time()
        self.last_keepalive = 0.0
        self.timer_task: Optional[asyncio.Task] = None
        self.timer_id: str = ""
        self.lock = asyncio.Lock()
        self.want_exit = False
        self.last_drop = time.time()
        self._reconnecting = False
        self.ever_connected = False

    def is_live(self) -> bool:
        c = self.client
        try:
            return c is not None and bool(c.is_connected)
        except Exception:
            return False

    def _on_ble_drop(self, client=None) -> None:
        if self.client is client or client is None:
            self.client = None
        self.last_drop = time.time()

    async def close(self) -> None:
        c = self.client
        self.client = None
        self.address = ""
        await _safe_disconnect(c)

    async def ensure(self, address: str) -> BleakClient:
        self.last_used = time.time()
        if self.is_live() and _norm_addr(self.address) == _norm_addr(address):
            return self.client  # type: ignore[return-value]
        await self.close()
        client = await connect_led(
            address,
            timeout=22.0,
            tries=1,
            disconnected_callback=self._on_ble_drop,
        )
        cfg = load_cfg()
        uuid = (cfg.get("write_uuid") or "").strip() or WRITE_UUIDS[0]
        self.client = client
        self.address = address
        self.uuid = uuid
        self.last_keepalive = time.time()
        self.ever_connected = True
        return client

    async def keepalive_tick(self) -> None:
        if not self.is_live() or self.client is None:
            return
        cfg = load_cfg()
        last = str(cfg.get("last_action") or "").lower()
        if last in ("off", "disable", "выключить"):
            self.last_keepalive = time.time()
            return
        try:
            pct = int(cfg.get("last_brightness") or 80)
            await asyncio.wait_for(
                self.client.write_gatt_char(self.uuid, cmd_brightness(pct), response=False),
                timeout=3.0,
            )
            now = time.time()
            self.last_keepalive = now
            self.last_used = now
        except Exception:
            await self.close()

    async def write_many(self, address: str, payloads: Sequence[bytes]) -> str:
        last_err: Optional[BaseException] = None
        for attempt in range(1, 3):
            try:
                if attempt > 1:
                    await self.close()
                    await asyncio.sleep(0.35 * attempt)
                client = await self.ensure(address)
                candidates: list[str] = []
                for u in [self.uuid, *WRITE_UUIDS]:
                    u = (u or "").strip()
                    if u and u not in candidates:
                        candidates.append(u)
                try:
                    discovered = _pick_write_uuid(client, None)
                    if discovered and discovered not in candidates:
                        candidates.insert(0, discovered)
                except Exception:
                    pass

                for uuid in candidates:
                    try:
                        for i, payload in enumerate(payloads):
                            try:
                                await asyncio.wait_for(
                                    client.write_gatt_char(uuid, payload, response=False),
                                    timeout=3.0,
                                )
                            except Exception:
                                await asyncio.wait_for(
                                    client.write_gatt_char(uuid, payload, response=True),
                                    timeout=3.0,
                                )
                            if i + 1 < len(payloads):
                                await asyncio.sleep(0.02)
                        self.uuid = uuid
                        cfg = load_cfg()
                        cfg["address"] = address
                        cfg["write_uuid"] = uuid
                        save_cfg(cfg)
                        now = time.time()
                        self.last_used = now
                        self.last_keepalive = now
                        return address
                    except Exception as e:
                        last_err = e
                        continue
                raise RuntimeError(f"write_failed:{last_err}")
            except Exception as e:
                last_err = e
                await self.close()
        raise RuntimeError(f"write_failed:{last_err}")

    def cancel_timer_task(self) -> None:
        t = self.timer_task
        self.timer_task = None
        self.timer_id = ""
        if t is not None and not t.done():
            t.cancel()


async def daemon_schedule_timer(
    session: LedSession,
    address: str,
    name: str,
    seconds: int,
    fire: str,
) -> str:
    """Schedule ON/OFF inside the daemon — same BLE session, reliable on Windows."""
    seconds = max(1, min(int(seconds), 7 * 24 * 3600))
    fire = "on" if fire == "on" else "off"
    session.cancel_timer_task()
    due = int(time.time()) + seconds
    tid = f"t{due}"
    cfg = load_cfg()
    cfg["timer_off_unix"] = due
    cfg["timer_id"] = tid
    cfg["timer_seconds"] = seconds
    cfg["timer_fire"] = fire
    cfg["address"] = address
    cfg["name"] = name
    save_cfg(cfg)
    session.timer_id = tid

    async def _fire() -> None:
        try:
            end = time.time() + seconds
            while time.time() < end:
                cfg_now = load_cfg()
                if not cfg_now.get("timer_off_unix") or str(cfg_now.get("timer_id") or "") != tid:
                    return
                await asyncio.sleep(min(0.5, max(0.05, end - time.time())))
            cfg_now = load_cfg()
            if not cfg_now.get("timer_off_unix") or str(cfg_now.get("timer_id") or "") != tid:
                return
            payload = cmd_on() if fire == "on" else cmd_off()
            addr = address
            last_err: Optional[BaseException] = None
            for attempt in range(6):
                try:
                    async with session.lock:
                        await session.write_many(addr, [payload])
                    cfg_done = load_cfg()
                    cfg_done["last_action"] = fire
                    save_cfg(cfg_done)
                    cancel_led_timer()
                    session.timer_task = None
                    session.timer_id = ""
                    return
                except Exception as e:
                    last_err = e
                    await asyncio.sleep(1.0)
            cancel_led_timer()
            session.timer_task = None
            session.timer_id = ""
            print(f"ERR:daemon_timer_{fire}:{last_err}", flush=True)
        except asyncio.CancelledError:
            return

    session.timer_task = asyncio.create_task(_fire())
    # Keep daemon warm while timer is pending
    session.last_used = time.time()
    return tid


async def build_payloads(action: str, value: str = "") -> list[bytes]:
    action = action.lower().strip()
    if action in ("on", "enable", "включить"):
        return [cmd_on()]
    if action in ("off", "disable", "выключить"):
        return [cmd_off()]
    if action in ("color", "цвет"):
        r, g, b = parse_color(value)
        return [cmd_on(), cmd_color(r, g, b)]
    if action in ("brightness", "яркость"):
        pct = parse_brightness_value(value or "80")
        cfg = load_cfg()
        cfg["last_brightness"] = pct
        save_cfg(cfg)
        return [cmd_on(), cmd_brightness(pct)]
    if action in ("speed", "скорость"):
        pct = parse_speed(value or "50")
        cfg = load_cfg()
        cfg["last_speed"] = pct
        save_cfg(cfg)
        return [cmd_speed(pct)]
    if action in ("effect", "эффект", "mode", "режим", "pattern"):
        return [cmd_on(), cmd_effect(parse_effect(value or "rainbow"))]
    if action in ("warm", "тёплый", "теплый"):
        return [cmd_on(), cmd_color_temp(255, 40)]
    if action in ("cold", "холодный", "cool"):
        return [cmd_on(), cmd_color_temp(40, 255)]
    if action in ("colortemp", "temp", "температура"):
        raw = (value or "200,80").lower()
        if "холод" in raw or raw == "cold":
            return [cmd_on(), cmd_color_temp(40, 255)]
        if "тепл" in raw or "тёпл" in raw or raw == "warm":
            return [cmd_on(), cmd_color_temp(255, 40)]
        parts = raw.replace(" ", "").split(",")
        if len(parts) == 2:
            return [cmd_on(), cmd_color_temp(int(parts[0]), int(parts[1]))]
        return [cmd_on(), cmd_color_temp(200, 80)]
    if action in ("mic_on", "микрофон"):
        return [cmd_mic(True), cmd_mic_eq(int(value or "2")), cmd_mic_sensitivity(30)]
    if action in ("mic_off",):
        return [cmd_mic(False)]
    if action in ("mic_eq", "music"):
        # Remote music buttons 1..4 → eq 0..3
        mode = int(value or "1")
        if mode >= 1:
            mode = mode - 1
        mode = max(0, min(3, mode))
        return [cmd_mic(True), cmd_mic_eq(mode), cmd_mic_sensitivity(35)]
    if action in ("mic_sens", "mic_sensitivity"):
        return [cmd_mic_sensitivity(int(value or "30"))]
    if action in ("auto",):
        return [cmd_on(), cmd_effect(EFFECTS["fade7"])]
    if action in ("quick",):
        cfg = load_cfg()
        cfg["last_speed"] = 100
        save_cfg(cfg)
        return [cmd_speed(100)]
    if action in ("slow",):
        cfg = load_cfg()
        cfg["last_speed"] = 10
        save_cfg(cfg)
        return [cmd_speed(10)]
    if action in ("moon", "night"):
        # Remote moon buttons: 1..4 → dim levels
        level = int(value or "1")
        pct = {1: 15, 2: 40, 3: 70, 4: 100}.get(level, 40)
        cfg = load_cfg()
        cfg["last_brightness"] = pct
        save_cfg(cfg)
        return [cmd_on(), cmd_brightness(pct)]
    if action == "timer":
        # Handled specially in run_action / daemon (no BLE payload alone)
        raise ValueError("timer_needs_handler")
    if action == "rgb":
        parts = (value or "").replace(" ", "").split(",")
        if len(parts) != 3:
            raise ValueError("rgb_needs_r,g,b")
        r, g, b = (int(parts[0]), int(parts[1]), int(parts[2]))
        return [cmd_on(), cmd_color(r, g, b)]
    raise ValueError(f"unknown_action:{action}")


async def daemon_handle(session: LedSession, req: dict) -> str:
    action = str(req.get("action") or "").lower().strip()
    value = str(req.get("value") or "")
    address_override = str(req.get("address") or "").strip()
    session.last_used = time.time()
    if action not in ("ping", "health"):
        session.last_command = time.time()

    if action in ("ping", "health"):
        return "OK:pong"

    if action in ("shutdown", "exit"):
        session.want_exit = True
        await session.close()
        return "OK:shutdown"

    if action in ("disconnect", "release"):
        await session.close()
        return "OK:disconnected"

    if action == "scan":
        if session.is_live() and session.address:
            return f"OK:saved:{session.address}"
        await session.close()
        await asyncio.sleep(0.35)
        found = await scan_devices(timeout=8.0)
        if not found:
            return "ERR:no_device"
        cfg = load_cfg()
        cfg["address"] = found[0]["address"]
        cfg["name"] = found[0]["name"]
        save_cfg(cfg)
        try:
            await asyncio.wait_for(session.ensure(found[0]["address"]), timeout=32.0)
            return f"OK:saved:{found[0]['address']}"
        except Exception as e:
            return f"ERR:connect_failed:{e}"

    if action == "status":
        body = json.dumps(
            {
                "ok": True,
                "connected": session.is_live(),
                "address": session.address,
                "config": load_cfg(),
            },
            ensure_ascii=False,
        )
        return f"OK:{body}"

    if action == "forget":
        await session.close()
        path = config_path()
        if path.exists():
            path.unlink()
        return "OK:forgotten"

    if action in ("timer_cancel", "cancel_timer"):
        session.cancel_timer_task()
        had = cancel_led_timer()
        return "OK:timer_cancelled" if had else "OK:timer_none"

    # Do not open a second GATT client while the warm session already holds the strip.
    if (
        not address_override
        and session.is_live()
        and session.address
    ):
        address = session.address
        name = load_cfg().get("name") or "LED"
    else:
        if session.client is not None:
            await session.close()
            await asyncio.sleep(0.4)
        address, name = await resolve_address(address_override or None)
    if action == "timer":
        seconds = parse_timer_seconds(value or "1")
        tid = await daemon_schedule_timer(session, address, name, seconds, "off")
        used = address
        try:
            used = await session.write_many(address, [cmd_on()])
        except Exception as e:
            return f"OK:timer:{seconds}s:{address}:{tid}:warn_on:{e}"
        cfg = load_cfg()
        cfg["address"] = used
        cfg["name"] = name
        cfg["last_action"] = f"timer_off_{seconds}s"
        save_cfg(cfg)
        return f"OK:timer:{seconds}s:{used}:{tid}"

    if action in ("timer_on", "delay_on"):
        seconds = parse_timer_seconds(value or "1")
        tid = await daemon_schedule_timer(session, address, name, seconds, "on")
        cfg = load_cfg()
        cfg["address"] = address
        cfg["name"] = name
        cfg["last_action"] = f"timer_on_{seconds}s"
        save_cfg(cfg)
        return f"OK:timer_on:{seconds}s:{address}:{tid}"

    payloads = await build_payloads(action, value)
    used = await session.write_many(address, payloads)
    cfg = load_cfg()
    cfg["address"] = used
    cfg["name"] = name
    cfg["last_action"] = action
    save_cfg(cfg)
    return f"OK:{action}:{used}"


async def run_daemon() -> int:
    session = LedSession()

    async def _on_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        await _daemon_client(session, reader, writer)

    try:
        server = await asyncio.start_server(_on_client, DAEMON_HOST, DAEMON_PORT)
    except OSError as e:
        print(f"ERR:daemon_bind:{e}", flush=True)
        return 1

    daemon_port_file().write_text(str(DAEMON_PORT), encoding="ascii")
    print(f"OK:daemon:{DAEMON_PORT}", flush=True)

    async def idle_watch() -> None:
        while True:
            await asyncio.sleep(1.0)
            if session.want_exit:
                server.close()
                return
            now = time.time()
            if session.is_live() and (now - session.last_keepalive) >= DAEMON_KEEPALIVE_S:
                if not session.lock.locked():
                    async with session.lock:
                        await session.keepalive_tick()
            elif (
                not session.is_live()
                and not session.want_exit
                and not session._reconnecting
                and not session.lock.locked()
                and session.ever_connected
                and (now - session.last_drop) >= 4.0
                and (now - session.last_command) < 600.0
            ):
                cfg_now = load_cfg()
                last = str(cfg_now.get("last_action") or "").lower()
                addr = (cfg_now.get("address") or session.address or "").strip()
                if addr and last not in ("off", "disable", "выключить", ""):
                    session._reconnecting = True

                    async def _bg() -> None:
                        try:
                            async with session.lock:
                                if session.is_live() or session.want_exit:
                                    return
                                await session.ensure(addr)
                        except Exception:
                            pass
                        finally:
                            session._reconnecting = False

                    asyncio.create_task(_bg())
            cfg = load_cfg()
            timer_pending = False
            try:
                due = int(cfg.get("timer_off_unix") or 0)
                timer_pending = due > int(time.time())
            except Exception:
                timer_pending = False
            # Keep GATT while the daemon lives. Exit the process only after a long
            # stretch with no user commands (keepalives do not count).
            idle = now - session.last_command
            if idle >= DAEMON_EXIT_IDLE_S and not timer_pending:
                server.close()
                return

    watcher = asyncio.create_task(idle_watch())
    async with server:
        await server.serve_forever()
    watcher.cancel()
    await session.close()
    try:
        p = daemon_port_file()
        if p.exists():
            p.unlink()
    except Exception:
        pass
    return 0


async def _daemon_client(session: LedSession, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        line = await asyncio.wait_for(reader.readline(), timeout=5.0)
        if not line:
            return
        req = json.loads(line.decode("utf-8", errors="replace"))
        if not isinstance(req, dict):
            req = {}
        action = str(req.get("action") or "").lower().strip()
        try:
            if action in ("ping", "health"):
                resp = await daemon_handle(session, req)
            else:
                async with session.lock:
                    resp = await asyncio.wait_for(daemon_handle(session, req), timeout=42.0)
        except asyncio.TimeoutError:
            resp = "ERR:TimeoutError:ble_timeout"
        except Exception as e:
            resp = f"ERR:{type(e).__name__}:{e}"
        writer.write((resp + "\n").encode("utf-8"))
        await writer.drain()
    except Exception as e:
        try:
            writer.write((f"ERR:{type(e).__name__}:{e}\n").encode("utf-8"))
            await writer.drain()
        except Exception:
            pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="JARVIS BLE LED strip (Lotus Lantern / ELK-BLEDOM)")
    p.add_argument(
        "action",
        help="on|off|color|brightness|effect|rgb|scan|status|forget|daemon",
    )
    p.add_argument("value", nargs="?", default="", help="color name / percent / effect / r,g,b")
    p.add_argument("--color", default="")
    p.add_argument("--brightness", default="")
    p.add_argument("--effect", default="")
    p.add_argument("--address", default="", help="force BLE address")
    p.add_argument("--timeout", default="10", help="scan timeout seconds")
    p.add_argument("--save", action="store_true", help="save first scan result")
    p.add_argument("--direct", action="store_true", help="skip warm daemon")
    p.add_argument("--timer-id", default="", help="LED timer id for waiter")
    p.add_argument("--timer-action", default="off", help="on|off when timer fires")
    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except Exception:
        pass
    args = build_parser().parse_args(argv)

    if args.action.lower().strip() == "daemon":
        try:
            return asyncio.run(run_daemon())
        except OSError as e:
            # Port already in use = another daemon is up
            print(f"ERR:daemon:{e}", flush=True)
            return 1

    # Fast path: warm daemon (connect once, reuse for next commands).
    # Never fall through to a second GATT client while the daemon is alive —
    # that race is what made the strip connect and immediately drop.
    action_l = args.action.lower().strip()
    if not args.direct and action_l not in ("_timer_wait", "_timer_wait_sec", "daemon"):
        if ensure_daemon(wait_s=2.5):
            val = args.value or args.color or args.brightness or args.effect or ""
            recv_s = 44.0 if action_l == "scan" else 40.0
            resp = try_daemon_request(
                args.action, val, args.address or "", timeout=0.5, recv_timeout=recv_s
            )
            if resp and resp.startswith("OK:"):
                print(resp, flush=True)
                return 0
            if resp is None:
                resp = try_daemon_request(
                    args.action, val, args.address or "", timeout=0.5, recv_timeout=recv_s
                )
            if resp and resp.startswith("OK:"):
                print(resp, flush=True)
                return 0
            if resp and resp.startswith("ERR:"):
                time.sleep(0.5)
                resp2 = try_daemon_request(
                    args.action, val, args.address or "", timeout=0.5, recv_timeout=recv_s
                )
                if resp2 and resp2.startswith("OK:"):
                    print(resp2, flush=True)
                    return 0
                print(resp2 or resp, flush=True)
                return 1
            if resp:
                print(resp, flush=True)
                return 1
            print("ERR:daemon_timeout", flush=True)
            return 1

    try:
        return asyncio.run(run_action(args))
    except RuntimeError as e:
        msg = str(e)
        if msg == "no_device":
            print("ERR:no_device", flush=True)
        else:
            print(f"ERR:{msg}", flush=True)
        return 1
    except ValueError as e:
        print(f"ERR:{e}", flush=True)
        return 1
    except Exception as e:
        print(f"ERR:{type(e).__name__}:{e}", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
