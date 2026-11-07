import logging
from typing import Optional

import numpy as np

from ..config import Config


log = logging.getLogger(__name__)


class WhisperSTT:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.model = None
        self.load_failed = False

    def reset(self) -> None:
        self.model = None
        self.load_failed = False

    def _load(self) -> None:
        if self.model is not None or self.load_failed:
            return

        from faster_whisper import WhisperModel

        model_size = str(self.cfg.get("stt.model", "small") or "small")
        device = str(self.cfg.get("stt.device", "auto") or "auto")

        try:
            self.model = WhisperModel(model_size, device=device, compute_type="default")
            log.info("Whisper loaded: model=%s device=%s", model_size, device)
        except Exception as exc:
            log.warning("Whisper GPU/auto load failed, falling back to CPU: %s", exc)
            try:
                self.model = WhisperModel(model_size, device="cpu", compute_type="int8")
            except Exception as exc2:
                self.load_failed = True
                raise RuntimeError(f"Не удалось загрузить Whisper: {exc2}") from exc2

    def transcribe(self, audio: np.ndarray) -> str:
        if audio is None or len(audio) < 1600:
            return ""

        self._load()

        language = str(self.cfg.get("stt.language", "auto") or "auto")
        lang = None if language.lower() in ("auto", "") else language.lower()

        try:
            segments, _ = self.model.transcribe(audio, language=lang, vad_filter=True)
        except TypeError:
            segments, _ = self.model.transcribe(audio, language=lang)
        except Exception as exc:
            raise RuntimeError(f"Ошибка распознавания речи: {exc}") from exc

        text = " ".join(segment.text.strip() for segment in segments).strip()
        return text
