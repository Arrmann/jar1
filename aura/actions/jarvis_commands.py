from __future__ import annotations

import ctypes
import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import quote_plus

from ..config import app_dir
from ..core.command_catalog import CommandCatalog
from . import apps, browser, system


URLS = {
    "open_youtube": "https://www.youtube.com",
    "open_spotify": "https://open.spotify.com",
    "open_gmail": "https://mail.google.com",
    "open_maps": "https://maps.google.com",
    "open_yandex_maps": "https://yandex.ru/maps",
    "open_whatsapp": "https://web.whatsapp.com",
    "open_translate": "https://translate.google.com",
    "open_chatgpt": "https://chatgpt.com",
    "open_deepseek": "https://chat.deepseek.com",
    "open_claude": "https://claude.ai",
    "open_gemini": "https://gemini.google.com",
    "open_twitch": "https://www.twitch.tv",
    "open_tiktok": "https://www.tiktok.com",
    "open_instagram": "https://www.instagram.com",
    "open_kinopoisk": "https://www.kinopoisk.ru",
    "open_ivi": "https://www.ivi.ru",
    "open_wildberries": "https://www.wildberries.ru",
    "open_ozon": "https://www.ozon.ru",
    "open_avito": "https://www.avito.ru",
    "open_yandex": "https://ya.ru",
    "open_google_drive": "https://drive.google.com",
    "open_yandex_disk": "https://disk.yandex.ru",
    "open_weather": "https://yandex.ru/pogoda",
    "open_news": "https://news.google.com",
    "open_speedtest": "https://www.speedtest.net",
    "open_yandex_music": "https://music.yandex.ru",
    "open_youtube_music": "https://music.youtube.com",
    "open_epic": "https://store.epicgames.com",
    "open_obs": "https://obsproject.com",
    "open_zoom": "https://zoom.us",
    "open_teams": "https://teams.microsoft.com",
    "open_meet": "https://meet.google.com",
    "open_word": "https://www.office.com/launch/word",
    "open_excel": "https://www.office.com/launch/excel",
    "open_powerpoint": "https://www.office.com/launch/powerpoint",
    "open_notion": "https://www.notion.so",
    "open_github": "https://github.com",
    "open_rutube": "https://rutube.ru",
    "open_pinterest": "https://www.pinterest.com",
    "open_netflix": "https://www.netflix.com",
    "open_vk": "https://vk.com",
    "open_mail_ru": "https://e.mail.ru",
}

APPS = {
    "open_steam": ("Steam", "https://store.steampowered.com"),
    "open_telegram": ("Telegram", "https://web.telegram.org"),
    "open_discord": ("Discord", "https://discord.com/app"),
    "open_obs": ("OBS Studio", URLS["open_obs"]),
    "open_zoom": ("Zoom", URLS["open_zoom"]),
    "open_teams": ("Microsoft Teams", URLS["open_teams"]),
    "open_spotify": ("Spotify", URLS["open_spotify"]),
    "open_pubg": ("PUBG", "https://store.steampowered.com/app/578080/PUBG_BATTLEGROUNDS/"),
    "open_cursor": ("Cursor", "https://cursor.com"),
    "open_notepad": ("notepad", ""),
    "open_calculator": ("calculator", ""),
    "open_paint": ("paint", ""),
    "open_explorer": ("explorer", ""),
    "open_task_manager": ("Task Manager", ""),
    "open_terminal": ("Windows Terminal", ""),
}

FOLDERS = {
    "open_downloads": "Downloads",
    "open_documents": "Documents",
    "open_desktop_folder": "Desktop",
    "open_screenshots_folder": "Pictures/JARVIS Screenshots",
}

SETTINGS_URIS = {
    "open_settings": "ms-settings:",
    "open_wifi": "ms-settings:network-wifi",
    "open_bluetooth": "ms-settings:bluetooth",
    "open_sound_settings": "ms-settings:sound",
    "open_display_settings": "ms-settings:display",
    "open_night_light": "ms-settings:nightlight",
    "open_focus_assist": "ms-settings:quiethours",
    "open_apps_features": "ms-settings:appsfeatures",
    "open_startup_apps": "ms-settings:startupapps",
    "open_storage": "ms-settings:storagesense",
    "open_update": "ms-settings:windowsupdate",
    "open_about_pc": "ms-settings:about",
    "open_clock": "ms-clock:",
    "open_calendar": "outlookcal:",
    "open_photos": "ms-photos:",
    "open_camera": "microsoft.windows.camera:",
}

CHORDS = {
    "browser_back": ("alt", "left"),
    "browser_forward": ("alt", "right"),
    "browser_new_window": ("ctrl", "n"),
    "browser_new_tab": ("ctrl", "t"),
    "browser_close_tab": ("ctrl", "w"),
    "browser_reopen_tab": ("ctrl", "shift", "t"),
    "browser_next_tab": ("ctrl", "tab"),
    "browser_prev_tab": ("ctrl", "shift", "tab"),
    "browser_refresh": ("f5",),
    "browser_downloads": ("ctrl", "j"),
    "browser_history": ("ctrl", "h"),
    "browser_bookmark": ("ctrl", "d"),
    "browser_address": ("ctrl", "l"),
    "browser_find": ("ctrl", "f"),
    "browser_zoom_reset": ("ctrl", "0"),
    "browser_zoom_in_cmd": ("ctrl", "+"),
    "browser_zoom_out_cmd": ("ctrl", "-"),
    "browser_fullscreen": ("f11",),
    "browser_incognito": ("ctrl", "shift", "n"),
    "browser_escape": ("esc",),
    "input_switch_lang": ("win", "space"),
    "open_run_dialog": ("win", "r"),
    "open_emoji_panel": ("win", "."),
    "open_snip": ("win", "shift", "s"),
    "open_magnifier": ("win", "+"),
    "input_copy": ("ctrl", "c"),
    "input_paste": ("ctrl", "v"),
    "input_cut": ("ctrl", "x"),
    "input_select_all": ("ctrl", "a"),
    "input_undo": ("ctrl", "z"),
    "input_redo": ("ctrl", "y"),
    "input_save": ("ctrl", "s"),
    "input_save_as": ("ctrl", "shift", "s"),
    "input_find": ("ctrl", "f"),
    "input_print": ("ctrl", "p"),
    "input_new_doc": ("ctrl", "n"),
    "input_enter": ("enter",),
    "input_escape": ("esc",),
    "clipboard_history": ("win", "v"),
    "minimize_all": ("win", "m"),
    "show_desktop": ("win", "d"),
}

MEDIA_KEYS = {
    "media_pause": 0xB3,
    "media_resume": 0xB3,
    "media_play_pause": 0xB3,
    "media_next": 0xB0,
    "media_prev": 0xB1,
    "media_stop": 0xB2,
}

VOLUME_KEYS = {
    "volume_up": 0xAF,
    "volume_down": 0xAE,
    "volume_mute": 0xAD,
    "volume_unmute": 0xAD,
}

READY_IDS = (
    set(URLS) | set(APPS) | set(FOLDERS) | set(SETTINGS_URIS) |
    set(CHORDS) | set(MEDIA_KEYS) | set(VOLUME_KEYS) |
    {
        "browser_open", "close_active", "volume_set", "lock_pc",
        "screenshot", "screen_record_start", "screen_record_stop",
        "timer_set", "timer_list", "task_add", "task_list",
        "task_speak", "task_clear", "remind", "remind_cancel",
        "search_google", "search_yandex", "search_youtube", "search_wiki",
        "search_web", "brightness_set", "scroll_up", "scroll_down", "scroll_page_up",
        "scroll_page_down", "scroll_top", "scroll_bottom",
        "minimize_window", "maximize_window", "minimize_video",
        "maximize_video", "open_recycle_bin", "reload_explorer",
        "shutdown_pc", "shutdown_delayed", "restart_pc", "cancel_shutdown",
        "sleep_pc", "empty_trash", "open_translate",
        "browser_close", "switch_window", "brightness_up", "brightness_down",
        "translate", "speak", "speak_stop", "input_delete_word",
        "chitchat_hello", "chitchat_howare",
    } |
    {f"volume_{value}" for value in range(0, 101, 10)} |
    {f"brightness_{value}" for value in range(10, 101, 10)}
)

OPTIONAL_IDS = {
    "ask_screen", "create_photo", "dictate", "dictate_stop",
    "screen_record_start", "screen_record_stop",
    "led_on", "led_off", "led_color", "led_brightness",
    "plug_on", "plug_off", "plug_status", "plug_timer",
    "obsidian_write", "obsidian_daily", "obsidian_search", "obsidian_open",
    "companion_show", "companion_hide", "companion_dance",
    "companion_dance_stop", "companion_sleep", "companion_wake",
    "set_wallpaper", "set_wallpaper_screenshot", "set_wallpaper_random",
}

DANGEROUS_IDS = {
    "close_active", "browser_close", "shutdown_pc", "shutdown_delayed",
    "restart_pc", "sleep_pc", "empty_trash", "task_clear",
    "screen_record_start",
}

WAKE_WORDS = ("джарвис", "джервис", "гарвис", "jarvis", "hey jarvis")


class JarvisCommandService:
    """AURA-side implementation of safe, common commands from the JARVIS demo.

    The imported command manifest is metadata only. This service deliberately
    does not execute the original Lua/PowerShell command files or native binaries.
    """

    def __init__(self, db, speaker):
        self.db = db
        self.speaker = speaker
        self.catalog = CommandCatalog()
        self.active_timers: dict[str, dict[str, Any]] = {}
        self._timers_lock = threading.RLock()
        self.timer_file = app_dir() / "jarvis-timers.json"
        self.recording_process: subprocess.Popen | None = None
        self._load_timers()

    @property
    def ready_ids(self) -> set[str]:
        ready = set(READY_IDS)
        if not shutil.which("ffmpeg"):
            ready.discard("screen_record_start")
            ready.discard("screen_record_stop")
        return ready

    def status(self, command_id: str) -> str:
        if command_id in self.ready_ids:
            return "ready"
        if command_id in OPTIONAL_IDS:
            return "setup"
        return "planned"

    def counts(self) -> dict[str, int]:
        result = {"ready": 0, "setup": 0, "planned": 0}
        for command in self.catalog.commands:
            result[self.status(str(command.get("id", "")))] += 1
        return result

    def llm_context(self, limit: int = 150) -> str:
        rows = []
        priority = {
            "popular": 0,
            "basics": 1,
            "daily": 2,
            "control": 3,
            "extras": 4,
            "notes": 5,
        }
        ordered = sorted(
            self.catalog.commands,
            key=lambda item: (
                priority.get(str(item.get("group", "")), 99),
                str(item.get("id", "")),
            ),
        )
        for item in ordered:
            command_id = str(item.get("id", ""))
            if command_id not in self.ready_ids:
                continue
            aliases = list(item.get("phrases_ru") or [])[:2]
            desc = str(item.get("description", "")).strip()
            rows.append(f"- {command_id}: {desc}; фразы: {', '.join(aliases)}")
            if len(rows) >= limit:
                break
        return "Команды JARVIS, которые можно выполнять через инструмент run_jarvis_command:\n" + "\n".join(rows)

    def match(self, utterance: str) -> dict[str, Any] | None:
        return self.catalog.match(
            utterance,
            enabled_ids=self.ready_ids,
            wake_phrase="джарвис",
        )

    def is_dangerous(self, command_id: str) -> bool:
        return command_id in DANGEROUS_IDS

    @staticmethod
    def _open_url(url: str) -> dict[str, Any]:
        return browser.open_url({"url": url})

    @staticmethod
    def _press(keys: tuple[str, ...] | list[str]) -> dict[str, Any]:
        try:
            from pynput.keyboard import Controller, Key, KeyCode
            controller = Controller()
            special = {
                "ctrl": Key.ctrl, "shift": Key.shift, "alt": Key.alt,
                "win": Key.cmd, "enter": Key.enter, "esc": Key.esc,
                "tab": Key.tab, "left": Key.left, "right": Key.right,
                "up": Key.up, "down": Key.down, "f5": Key.f5,
                "f11": Key.f11, "space": Key.space, "backspace": Key.backspace,
            }
            pressed = []
            try:
                for token in keys:
                    value = special.get(token)
                    if value is None:
                        value = KeyCode.from_char(token)
                    controller.press(value)
                    pressed.append(value)
                time.sleep(0.04)
            finally:
                for value in reversed(pressed):
                    try:
                        controller.release(value)
                    except Exception:
                        pass
            return {"success": True, "message": "Команда клавиатуры выполнена."}
        except Exception as exc:
            return {"success": False, "message": f"Не удалось отправить сочетание клавиш: {exc}"}

    @staticmethod
    def _set_muted(muted: bool) -> dict[str, Any]:
        try:
            from ctypes import POINTER, cast
            from comtypes import CLSCTX_ALL
            from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume

            devices = AudioUtilities.GetSpeakers()
            interface = devices.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
            volume = cast(interface, POINTER(IAudioEndpointVolume))
            volume.SetMute(1 if muted else 0, None)
            label = "выключен" if muted else "включен"
            return {"success": True, "message": f"Звук {label}."}
        except Exception as exc:
            return {"success": False, "message": f"Не удалось изменить состояние звука: {exc}"}

    @staticmethod
    def _media_key(vk: int) -> dict[str, Any]:
        try:
            user32 = ctypes.windll.user32
            user32.keybd_event(vk, 0, 0, 0)
            user32.keybd_event(vk, 0, 0x0002, 0)
            return {"success": True, "message": "Медиа-команда отправлена."}
        except Exception as exc:
            return {"success": False, "message": f"Не удалось отправить медиа-команду: {exc}"}

    @staticmethod
    def _require_browser() -> tuple[bool, str]:
        try:
            import pygetwindow as gw
            active = gw.getActiveWindow()
            title = str(active.title or "") if active else ""
            if not title:
                return False, "Нет активного окна."
            if not re.search(r"chrome|edge|firefox|opera|vivaldi|browser|браузер", title, re.I):
                return False, "Сначала откройте и активируйте окно браузера."
            return True, title
        except Exception as exc:
            return False, f"Не удалось проверить активное окно: {exc}"

    @staticmethod
    def _open_folder(folder: str) -> dict[str, Any]:
        try:
            path = Path.home() / folder
            if not path.exists():
                path.mkdir(parents=True, exist_ok=True)
            os.startfile(str(path))
            return {"success": True, "message": f"Открыта папка: {path}"}
        except Exception as exc:
            return {"success": False, "message": f"Не удалось открыть папку: {exc}"}

    @staticmethod
    def _open_uri(uri: str) -> dict[str, Any]:
        try:
            os.startfile(uri)
            return {"success": True, "message": f"Открыто: {uri}"}
        except Exception as exc:
            return {"success": False, "message": f"Не удалось открыть системный раздел: {exc}"}

    @staticmethod
    def _number(text: str) -> int | None:
        words = {
            "ноль": 0, "один": 1, "одна": 1, "одно": 1, "одну": 1,
            "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
            "шесть": 6, "семь": 7, "восемь": 8, "девять": 9,
            "десять": 10, "пятнадцать": 15, "двадцать": 20,
            "тридцать": 30, "сорок": 40, "пятьдесят": 50,
            "шестьдесят": 60, "девяносто": 90, "сто": 100,
        }
        m = re.search(r"\b(\d{1,3})\b", text or "")
        if m:
            return int(m.group(1))
        for word, value in words.items():
            if re.search(rf"\b{word}\b", (text or "").casefold()):
                return value
        return None

    @classmethod
    def _duration_seconds(cls, text: str) -> int | None:
        value = (text or "").casefold().replace("ё", "е")
        number = cls._number(value)
        if number is None:
            return None
        if re.search(r"секунд|\bсек\b|\bс\b", value):
            multiplier = 1
        elif re.search(r"минут|\bмин\b", value):
            multiplier = 60
        elif re.search(r"час|\bч\b", value):
            multiplier = 3600
        elif re.search(r"дн|сут", value):
            multiplier = 86400
        else:
            return None
        return max(1, min(number * multiplier, 30 * 86400))

    def _save_timers(self) -> None:
        with self._timers_lock:
            rows = [
                {"id": key, "due": item["due"], "message": item["message"], "kind": item["kind"]}
                for key, item in self.active_timers.items()
            ]
        try:
            self.timer_file.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError:
            pass

    def _load_timers(self) -> None:
        try:
            rows = json.loads(self.timer_file.read_text(encoding="utf-8"))
            if not isinstance(rows, list):
                return
        except (OSError, json.JSONDecodeError):
            return
        for item in rows:
            try:
                self._schedule_timer(
                    str(item["message"]), max(0, float(item["due"]) - time.time()),
                    kind=str(item.get("kind", "reminder")), timer_id=str(item["id"]), due=float(item["due"])
                )
            except (KeyError, TypeError, ValueError):
                continue

    def _schedule_timer(self, message: str, seconds: float, kind: str, timer_id: str | None = None, due: float | None = None) -> str:
        timer_id = timer_id or uuid.uuid4().hex[:8]
        due = due if due is not None else time.time() + seconds
        timer = threading.Timer(max(0.1, seconds), self._timer_fired, args=(timer_id,))
        timer.daemon = True
        with self._timers_lock:
            self.active_timers[timer_id] = {
                "timer": timer, "due": due, "message": message, "kind": kind
            }
        timer.start()
        self._save_timers()
        return timer_id

    def _timer_fired(self, timer_id: str) -> None:
        with self._timers_lock:
            item = self.active_timers.pop(timer_id, None)
        self._save_timers()
        if item:
            try:
                self.speaker.speak(str(item.get("message") or "Время вышло."))
            except Exception:
                pass

    def _set_timer(self, query: str, kind: str) -> dict[str, Any]:
        seconds = self._duration_seconds(query)
        if seconds is None:
            return {"success": False, "message": "Не понял время. Скажи, например: 5 минут или 30 секунд."}
        message = "Время вышло." if kind == "timer" else (query.strip() or "Напоминание.")
        timer_id = self._schedule_timer(message, seconds, kind)
        return {
            "success": True,
            "message": f"{'Таймер' if kind == 'timer' else 'Напоминание'} поставлен на {seconds} сек. (ID {timer_id}).",
        }

    def _cancel_timers(self) -> dict[str, Any]:
        with self._timers_lock:
            items = list(self.active_timers.values())
            self.active_timers.clear()
        for item in items:
            try:
                item["timer"].cancel()
            except Exception:
                pass
        self._save_timers()
        return {"success": True, "message": f"Отменено таймеров и напоминаний: {len(items)}."}

    def _list_timers(self) -> dict[str, Any]:
        with self._timers_lock:
            rows = list(self.active_timers.items())
        if not rows:
            return {"success": True, "message": "Активных таймеров и напоминаний нет."}
        labels = []
        for timer_id, item in rows:
            left = max(0, int(item["due"] - time.time()))
            labels.append(f"{timer_id}: {item['message']} (осталось {left} сек.)")
        return {"success": True, "message": "\n".join(labels)}

    def _tasks(self) -> list[dict[str, Any]]:
        return [m for m in self.db.get_memories() if str(m.get("category", "")).casefold() == "task"]

    def _task_command(self, command_id: str, query: str) -> dict[str, Any]:
        if command_id == "task_add":
            text = query.strip()
            for prefix in ("добавь задачу", "добавить задачу", "создай задачу", "задача"):
                if text.casefold().startswith(prefix):
                    text = text[len(prefix):].strip(" ,.:;-")
                    break
            if not text:
                return {"success": False, "message": "Скажи, какую задачу добавить."}
            self.db.add_memory("task", text)
            return {"success": True, "message": f"Задача добавлена: {text}"}
        tasks = self._tasks()
        if command_id == "task_clear":
            for task in tasks:
                self.db.delete_memory(int(task["id"]))
            return {"success": True, "message": f"Список задач очищен. Удалено: {len(tasks)}."}
        if not tasks:
            return {"success": True, "message": "Список задач пока пуст."}
        text = "\n".join(f"{i + 1}. {task['content']}" for i, task in enumerate(tasks))
        return {"success": True, "message": "Твои задачи:\n" + text}

    def execute(self, command_id: str, utterance: str = "", query: str = "") -> dict[str, Any]:
        command_id = str(command_id)
        utterance = str(utterance or "")
        query = str(query or "")
        if command_id not in self.ready_ids:
            return {"success": False, "message": f"Команда {command_id} пока не подключена или требует дополнительных настроек."}

        if command_id in URLS:
            return self._open_url(URLS[command_id])
        if command_id in APPS:
            app_name, fallback_url = APPS[command_id]
            result = apps.open_app({"query": app_name})
            if result.get("success") or not fallback_url:
                return result
            return self._open_url(fallback_url)
        if command_id in FOLDERS:
            return self._open_folder(FOLDERS[command_id])
        if command_id in SETTINGS_URIS:
            return self._open_uri(SETTINGS_URIS[command_id])
        if command_id in CHORDS:
            if command_id.startswith("browser_"):
                ok, title = self._require_browser()
                if not ok:
                    return {"success": False, "message": title}
            return self._press(CHORDS[command_id])
        if command_id in MEDIA_KEYS:
            return self._media_key(MEDIA_KEYS[command_id])
        if command_id == "volume_mute":
            return self._set_muted(True)
        if command_id == "volume_unmute":
            return self._set_muted(False)
        if command_id in VOLUME_KEYS:
            return self._media_key(VOLUME_KEYS[command_id])

        if command_id == "browser_open":
            return self._open_url("https://www.google.com")
        if command_id == "browser_close":
            ok, title = self._require_browser()
            if not ok:
                return {"success": False, "message": title}
            try:
                import pygetwindow as gw
                active = gw.getActiveWindow()
                if active:
                    active.close()
                    return {"success": True, "message": "Окно браузера закрыто."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось закрыть браузер: {exc}"}
            return {"success": False, "message": "Активное окно браузера не найдено."}
        if command_id in {"search_google", "search_web"}:
            return browser.search_web({"query": query or utterance, "engine": "google"})
        if command_id == "search_yandex":
            return browser.search_web({"query": query or utterance, "engine": "yandex"})
        if command_id == "search_youtube":
            return browser.youtube_search({"query": query or utterance})
        if command_id == "search_wiki":
            term = query or utterance
            return self._open_url("https://ru.wikipedia.org/w/index.php?search=" + quote_plus(term))
        if command_id == "translate":
            term = query or utterance
            if not term.strip():
                return self._open_url("https://translate.google.com")
            return self._open_url("https://translate.google.com/?sl=auto&tl=ru&text=" + quote_plus(term) + "&op=translate")

        if command_id == "volume_set":
            percent = self._number(query or utterance)
            if percent is None:
                return {"success": False, "message": "Назови громкость в процентах от 0 до 100."}
            return apps.set_volume({"percent": max(0, min(100, percent))})
        if command_id == "brightness_set":
            percent = self._number(query or utterance)
            if percent is None:
                return {"success": False, "message": "Назови яркость в процентах от 0 до 100."}
            return self._set_brightness(percent)

        if command_id.startswith("volume_") and command_id[7:].isdigit():
            return apps.set_volume({"percent": int(command_id[7:])})
        if command_id.startswith("brightness_") and command_id[11:].isdigit():
            return self._set_brightness(int(command_id[11:]))
        if command_id in {"brightness_up", "brightness_down"}:
            current = self._get_brightness()
            if current is None:
                return {"success": False, "message": "Не удалось прочитать яркость. Возможно, монитор не поддерживает WMI brightness."}
            step = 10 if command_id == "brightness_up" else -10
            return self._set_brightness(max(0, min(100, current + step)))

        if command_id in {"timer_set", "timer_list", "remind", "remind_cancel"}:
            if command_id == "timer_list":
                return self._list_timers()
            if command_id == "remind_cancel":
                return self._cancel_timers()
            kind = "timer" if command_id == "timer_set" else "reminder"
            return self._set_timer(query or utterance, kind)
        if command_id in {"task_add", "task_list", "task_speak", "task_clear"}:
            result = self._task_command(command_id, query or utterance)
            if command_id == "task_speak" and result.get("success"):
                self.speaker.speak(str(result.get("message", "")))
            return result

        if command_id == "speak":
            text = (query or utterance).strip()
            if not text:
                return {"success": False, "message": "Скажи, какой текст произнести."}
            self.speaker.speak(text)
            return {"success": True, "message": "Текст озвучен."}
        if command_id == "speak_stop":
            self.speaker.stop()
            return {"success": True, "message": "Озвучивание остановлено."}
        if command_id == "chitchat_hello":
            self.speaker.speak("Здравствуйте. Я слушаю вас.")
            return {"success": True, "message": "Здравствуйте. Я слушаю вас."}
        if command_id == "chitchat_howare":
            self.speaker.speak("Все системы работают штатно. Чем могу помочь?")
            return {"success": True, "message": "Все системы работают штатно. Чем могу помочь?"}

        if command_id == "lock_pc":
            try:
                ctypes.windll.user32.LockWorkStation()
                return {"success": True, "message": "Компьютер заблокирован."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось заблокировать компьютер: {exc}"}
        if command_id == "sleep_pc":
            try:
                ctypes.windll.powrprof.SetSuspendState(False, True, True)
                return {"success": True, "message": "Переход в спящий режим инициирован."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось перевести ПК в сон: {exc}"}
        if command_id == "shutdown_pc":
            return system.shutdown({})
        if command_id == "restart_pc":
            return system.restart({})
        if command_id == "shutdown_delayed":
            seconds = self._duration_seconds(query or utterance)
            if seconds is None:
                return {"success": False, "message": "Назови задержку, например: через 10 минут."}
            try:
                subprocess.run(["shutdown", "/s", "/t", str(seconds)], check=True, timeout=10)
                return {"success": True, "message": f"Выключение запланировано через {seconds} секунд."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось запланировать выключение: {exc}"}
        if command_id == "cancel_shutdown":
            try:
                subprocess.run(["shutdown", "/a"], check=True, timeout=10)
                return {"success": True, "message": "Отложенное выключение отменено."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось отменить выключение: {exc}"}
        if command_id == "empty_trash":
            try:
                ctypes.windll.shell32.SHEmptyRecycleBinW(None, None, 0x00000001 | 0x00000002 | 0x00000004)
                return {"success": True, "message": "Корзина очищена."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось очистить корзину: {exc}"}
        if command_id == "open_recycle_bin":
            try:
                subprocess.Popen(["explorer.exe", "shell:RecycleBinFolder"])
                return {"success": True, "message": "Корзина открыта."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось открыть корзину: {exc}"}

        if command_id == "switch_window":
            title = (query or utterance).strip()
            for prefix in ("переключись на окно", "переключи окно", "перейди в окно", "switch window"):
                if title.casefold().startswith(prefix):
                    title = title[len(prefix):].strip(" ,.:;-")
                    break
            if not title:
                return {"success": False, "message": "Назови окно, на которое нужно переключиться."}
            return apps.switch_window({"title": title})

        if command_id in {"close_active", "minimize_window", "maximize_window"}:
            try:
                import pygetwindow as gw
                active = gw.getActiveWindow()
                if not active:
                    return {"success": False, "message": "Активное окно не найдено."}
                if command_id == "close_active":
                    active.close()
                    return {"success": True, "message": "Активное окно закрыто."}
                if command_id == "minimize_window":
                    active.minimize()
                    return {"success": True, "message": "Окно свёрнуто."}
                active.maximize()
                return {"success": True, "message": "Окно развёрнуто."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось выполнить действие с окном: {exc}"}

        if command_id == "screenshot":
            return self._screenshot()
        if command_id == "screen_record_start":
            return self._record_start()
        if command_id == "screen_record_stop":
            return self._record_stop()
        if command_id == "reload_explorer":
            try:
                subprocess.run(["taskkill", "/f", "/im", "explorer.exe"], check=False, timeout=10,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                subprocess.Popen(["explorer.exe"])
                return {"success": True, "message": "Проводник Windows перезапущен."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось перезапустить Проводник: {exc}"}

        if command_id in {"scroll_up", "scroll_down", "scroll_page_up", "scroll_page_down", "scroll_top", "scroll_bottom"}:
            try:
                from pynput.mouse import Controller
                mouse = Controller()
                if command_id == "scroll_up":
                    mouse.scroll(0, 3)
                elif command_id == "scroll_down":
                    mouse.scroll(0, -3)
                elif command_id == "scroll_page_up":
                    mouse.scroll(0, 8)
                elif command_id == "scroll_page_down":
                    mouse.scroll(0, -8)
                elif command_id == "scroll_top":
                    self._press(("ctrl", "home"))
                else:
                    self._press(("ctrl", "end"))
                return {"success": True, "message": "Прокрутка выполнена."}
            except Exception as exc:
                return {"success": False, "message": f"Не удалось прокрутить страницу: {exc}"}

        if command_id == "input_delete_word":
            return self._press(("ctrl", "backspace"))

        if command_id == "minimize_video":
            return self._press(("esc",))
        if command_id == "maximize_video":
            ok, title = self._require_browser()
            if not ok:
                return {"success": False, "message": title}
            return self._press(("f",))

        return {"success": False, "message": f"Обработчик команды {command_id} ещё не добавлен."}

    @staticmethod
    def _get_brightness() -> int | None:
        script = (
            "$b=Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction Stop | "
            "Select-Object -First 1 -ExpandProperty CurrentBrightness; "
            "if($null -eq $b){exit 2}; [Console]::Write([int]$b)"
        )
        try:
            result = subprocess.run(
                ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                capture_output=True, text=True, timeout=10,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            if result.returncode != 0:
                return None
            return max(0, min(100, int(result.stdout.strip())))
        except (OSError, ValueError, subprocess.TimeoutExpired):
            return None

    @staticmethod
    def _set_brightness(percent: int) -> dict[str, Any]:
        percent = max(0, min(100, int(percent)))
        script = (
            "$m=Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop | Select-Object -First 1; "
            "if($null -eq $m){throw 'Монитор не поддерживает WMI brightness'}; "
            f"$m | Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{{Timeout=1;Brightness={percent}}} | Out-Null"
        )
        try:
            result = subprocess.run(
                ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script],
                capture_output=True, text=True, timeout=15,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "WMI brightness недоступен").strip()
                return {"success": False, "message": f"Не удалось изменить яркость: {detail[:300]}"}
            return {"success": True, "message": f"Яркость установлена на {percent}%."}
        except Exception as exc:
            return {"success": False, "message": f"Не удалось изменить яркость: {exc}"}

    @staticmethod
    def _screenshot() -> dict[str, Any]:
        try:
            from PIL import ImageGrab
            folder = Path.home() / "Pictures" / "JARVIS Screenshots"
            folder.mkdir(parents=True, exist_ok=True)
            filename = time.strftime("screenshot_%Y-%m-%d_%H-%M-%S.png")
            path = folder / filename
            ImageGrab.grab(all_screens=True).save(path)
            return {"success": True, "message": f"Снимок экрана сохранён: {path}"}
        except Exception as exc:
            return {"success": False, "message": f"Не удалось сделать снимок экрана: {exc}"}

    def _record_start(self) -> dict[str, Any]:
        if self.recording_process and self.recording_process.poll() is None:
            return {"success": False, "message": "Запись экрана уже идёт."}
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            return {"success": False, "message": "Для записи экрана установите FFmpeg и добавьте его в PATH."}
        folder = Path.home() / "Videos" / "JARVIS Screen Records"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / time.strftime("recording_%Y-%m-%d_%H-%M-%S.mp4")
        try:
            self.recording_process = subprocess.Popen(
                [ffmpeg, "-y", "-f", "gdigrab", "-framerate", "30", "-i", "desktop",
                 "-c:v", "libx264", "-preset", "ultrafast", str(path)],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0),
            )
            return {"success": True, "message": f"Запись экрана началась: {path}"}
        except Exception as exc:
            self.recording_process = None
            return {"success": False, "message": f"Не удалось начать запись: {exc}"}

    def _record_stop(self) -> dict[str, Any]:
        proc = self.recording_process
        if not proc or proc.poll() is not None:
            self.recording_process = None
            return {"success": False, "message": "Активная запись экрана не найдена."}
        try:
            if os.name == "nt":
                proc.send_signal(getattr(signal, "CTRL_BREAK_EVENT", signal.SIGTERM))
            else:
                proc.terminate()
            proc.wait(timeout=10)
            self.recording_process = None
            return {"success": True, "message": "Запись экрана остановлена."}
        except Exception as exc:
            try:
                proc.terminate()
            except Exception:
                pass
            self.recording_process = None
            return {"success": False, "message": f"Не удалось корректно остановить запись: {exc}"}
