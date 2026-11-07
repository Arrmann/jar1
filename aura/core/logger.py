import logging
from pathlib import Path

from ..config import app_dir


def setup_logging() -> None:
    log_dir = app_dir() / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        handlers=[
            logging.FileHandler(log_dir / "aura.log", encoding="utf-8"),
            logging.StreamHandler(),
        ],
    )

    for noisy in ("urllib3", "requests", "faster_whisper", "numba"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
