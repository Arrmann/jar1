import time
from typing import Callable, List, Optional

import numpy as np
import sounddevice as sd


class Recorder:
    SAMPLE_RATE = 16000

    def __init__(self, cfg):
        self.cfg = cfg
        self.active = False
        self.frames: List[np.ndarray] = []
        self.stream: Optional[sd.InputStream] = None
        self.auto_stop = False
        self.autostop_triggered = False
        self.speech_started = False
        self.last_sound_at = 0.0

    def is_active(self) -> bool:
        return self.active

    def start(self, auto_stop: bool = False) -> None:
        if self.active:
            return

        self.frames = []
        self.active = True
        self.auto_stop = auto_stop
        self.autostop_triggered = False
        self.speech_started = False
        self.last_sound_at = time.monotonic()

        self.stream = sd.InputStream(
            samplerate=self.SAMPLE_RATE,
            channels=1,
            dtype="float32",
            callback=self._callback,
        )
        self.stream.start()

    def _callback(self, indata, frames, time_info, status) -> None:
        if not self.active:
            return

        self.frames.append(indata.copy())

        if self.auto_stop:
            try:
                rms = float(np.sqrt(np.mean(np.square(indata))))
            except Exception:
                rms = 0.0

            threshold = float(self.cfg.get("voice.silence_threshold", 0.01) or 0.01)
            silence_seconds = float(self.cfg.get("voice.silence_seconds", 1.2) or 1.2)
            now = time.monotonic()

            if rms > threshold:
                self.speech_started = True
                self.last_sound_at = now
            elif self.speech_started and (now - self.last_sound_at) >= silence_seconds:
                self.autostop_triggered = True

    def stop(self) -> np.ndarray:
        if not self.active:
            return np.array([], dtype=np.float32)

        self.active = False

        try:
            if self.stream is not None:
                self.stream.stop()
                self.stream.close()
        except Exception:
            pass
        finally:
            self.stream = None

        if not self.frames:
            return np.array([], dtype=np.float32)

        audio = np.concatenate(self.frames, axis=0).astype(np.float32)
        self.frames = []
        return audio
