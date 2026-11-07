import asyncio
import logging
import os
import tempfile
import threading
import time
from typing import Optional

from ..config import Config


log = logging.getLogger(__name__)


class Speaker:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.stop_event = threading.Event()
        self.interrupted = False
        self._pygame_ready = False

    def _init_pygame(self) -> bool:
        if self._pygame_ready:
            return True
        try:
            import pygame

            if not pygame.mixer.get_init():
                pygame.mixer.init()
            self._pygame_ready = True
            return True
        except Exception as exc:
            log.warning("pygame mixer unavailable: %s", exc)
            return False

    def stop(self) -> None:
        self.stop_event.set()
        self.interrupted = True
        try:
            if self._pygame_ready:
                import pygame

                pygame.mixer.music.stop()
        except Exception:
            pass

    def speak(self, text: str) -> None:
        if not self.cfg.get("tts.enabled", True):
            return

        text = (text or "").strip()
        if not text:
            return

        self.stop_event.clear()
        self.interrupted = False

        engine = str(self.cfg.get("tts.engine", "edge") or "edge").lower()

        if engine == "edge":
            if self._speak_edge(text):
                return

        self._speak_pyttsx3(text)

    def _speak_edge(self, text: str) -> bool:
        tmp_path: Optional[str] = None
        try:
            import edge_tts
            import pygame

            if not self._init_pygame():
                return False

            voice = str(self.cfg.get("tts.voice", "ru-RU-SvetlanaNeural"))
            rate = str(self.cfg.get("tts.edge_rate", "+0%") or "+0%")

            with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
                tmp_path = tmp.name

            async def save_audio():
                communicate = edge_tts.Communicate(text=text, voice=voice, rate=rate)
                await communicate.save(tmp_path)

            asyncio.run(save_audio())

            if self.stop_event.is_set():
                return True

            pygame.mixer.music.load(tmp_path)
            pygame.mixer.music.play()

            while pygame.mixer.music.get_busy():
                if self.stop_event.is_set():
                    self.interrupted = True
                    pygame.mixer.music.stop()
                    break
                time.sleep(0.05)

            return True

        except Exception as exc:
            log.warning("Edge TTS failed, fallback to pyttsx3: %s", exc)
            return False
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except Exception:
                    pass

    def _speak_pyttsx3(self, text: str) -> None:
        try:
            import pyttsx3

            engine = pyttsx3.init()
            rate = int(self.cfg.get("tts.pyttsx3_rate", 185) or 185)
            engine.setProperty("rate", rate)

            voice = str(self.cfg.get("tts.voice", "") or "")
            if voice:
                try:
                    engine.setProperty("voice", voice)
                except Exception:
                    pass

            engine.say(text)
            engine.runAndWait()
            engine.stop()

            if self.stop_event.is_set():
                self.interrupted = True

        except Exception as exc:
            log.error("pyttsx3 failed: %s", exc)
