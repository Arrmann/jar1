import logging
from typing import Optional

import numpy as np

from ..config import Config


log = logging.getLogger(__name__)


class WhisperSTT:
    """Faster-Whisper loader with CUDA -> CPU fallback, including inference errors."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.model = None
        self.load_failed = False
        self.active_device = ""

    def reset(self) -> None:
        self.model = None
        self.load_failed = False
        self.active_device = ""

    @staticmethod
    def _is_cuda_error(exc: BaseException) -> bool:
        message = str(exc).casefold()
        return any(
            marker in message
            for marker in (
                "cuda", "cublas", "cudnn", "cudart", "cufft",
                "cudnn64", "cublas64", "dll load failed",
                "could not load library", "cannot load library",
            )
        )

    def _load(self, force_cpu: bool = False) -> None:
        if self.model is not None:
            return
        if self.load_failed and not force_cpu:
            raise RuntimeError(
                "Whisper не загрузился при предыдущей попытке. "
                "Перезапустите приложение после проверки зависимостей."
            )

        try:
            from faster_whisper import WhisperModel
        except Exception as exc:
            self.load_failed = True
            raise RuntimeError(f"Не удалось импортировать Faster-Whisper: {exc}") from exc

        model_size = str(self.cfg.get("stt.model", "small") or "small")
        requested = str(self.cfg.get("stt.device", "auto") or "auto").casefold()

        if force_cpu or requested == "cpu":
            attempts = [("cpu", "int8")]
        else:
            attempts = [("cuda", "float16"), ("cpu", "int8")]

        errors = []
        for device, compute_type in attempts:
            try:
                log.info(
                    "Loading Whisper model=%s device=%s compute_type=%s",
                    model_size, device, compute_type
                )
                self.model = WhisperModel(
                    model_size,
                    device=device,
                    compute_type=compute_type,
                )
                self.active_device = device
                self.load_failed = False
                log.info("Whisper is ready on %s", device)
                return
            except Exception as exc:
                errors.append(f"{device}: {exc}")
                log.warning("Whisper %s initialisation failed: %s", device, exc)
                self.model = None
                self.active_device = ""

        self.load_failed = True
        raise RuntimeError(
            "Не удалось загрузить модель распознавания.\n" + "\n".join(errors)
        )

    def _transcribe_loaded(self, audio: np.ndarray, language: Optional[str]) -> str:
        try:
            segments, _ = self.model.transcribe(
                audio,
                language=language,
                vad_filter=True,
            )
        except TypeError:
            segments, _ = self.model.transcribe(audio, language=language)

        # faster-whisper returns a generator: CUDA failures can occur while iterating.
        return " ".join(segment.text.strip() for segment in segments).strip()

    def transcribe(self, audio: np.ndarray) -> str:
        if audio is None or len(audio) < 1600:
            return ""

        language = str(self.cfg.get("stt.language", "auto") or "auto")
        lang = None if language.casefold() in ("auto", "") else language.casefold()

        self._load()
        try:
            return self._transcribe_loaded(audio, lang)
        except Exception as exc:
            if self.active_device != "cuda" or not self._is_cuda_error(exc):
                raise RuntimeError(f"Ошибка распознавания речи: {exc}") from exc

            gpu_error = str(exc)
            log.warning(
                "Whisper inference failed on CUDA; retrying once on CPU: %s",
                gpu_error,
            )
            self.model = None
            self.active_device = ""
            self.load_failed = False

            try:
                self._load(force_cpu=True)
                result = self._transcribe_loaded(audio, lang)
                log.info("Whisper successfully switched to CPU after CUDA failure")
                return result
            except Exception as cpu_error:
                self.load_failed = True
                raise RuntimeError(
                    "Распознавание не удалось ни на GPU, ни на CPU.\n"
                    f"CUDA: {gpu_error}\nCPU: {cpu_error}"
                ) from cpu_error
