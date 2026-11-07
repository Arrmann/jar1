import sys
from pathlib import Path

from PySide6.QtWidgets import QApplication, QMessageBox

from .config import Config
from .core.logger import setup_logging
from .core.orchestrator import Orchestrator
from .ui.main_window import MainWindow


def run() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("AURA AI")
    app.setOrganizationName("AURA_AI")

    setup_logging()

    try:
        cfg = Config.load()

        qss_path = Path(__file__).parent.parent / "resources" / "style.qss"
        if qss_path.exists():
            app.setStyleSheet(qss_path.read_text(encoding="utf-8"))

        orchestrator = Orchestrator(cfg)
        window = MainWindow(cfg, orchestrator)

        orchestrator.start()
        window.show()

        return app.exec()

    except Exception as exc:
        QMessageBox.critical(None, "AURA AI", f"Критическая ошибка запуска:\n{exc}")
        raise
