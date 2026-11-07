import json

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QButtonGroup,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from ..config import Config
from ..core.orchestrator import Orchestrator
from .widgets import ActionsWidget, ChatWidget, MemoryWidget, SettingsWidget


class MainWindow(QMainWindow):
    def __init__(self, cfg: Config, orchestrator: Orchestrator):
        super().__init__()

        self.cfg = cfg
        self.orch = orchestrator

        self.setWindowTitle("AURA AI")
        self.resize(1360, 860)

        central = QWidget()
        self.setCentralWidget(central)

        root = QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # Sidebar
        sidebar = QWidget()
        sidebar.setMinimumWidth(220)
        sidebar_layout = QVBoxLayout(sidebar)

        title = QLabel("AURA AI")
        title.setObjectName("TitleLabel")
        subtitle = QLabel("Персональный голосовой ассистент")
        subtitle.setObjectName("SubtitleLabel")
        subtitle.setWordWrap(True)

        self.nav_group = QButtonGroup(self)
        self.chat_btn = QPushButton("Чаты")
        self.memory_btn = QPushButton("Память")
        self.actions_btn = QPushButton("Управление и действия")
        self.settings_btn = QPushButton("Настройки")

        for index, button in enumerate([self.chat_btn, self.memory_btn, self.actions_btn, self.settings_btn]):
            button.setCheckable(True)
            button.setMinimumHeight(42)
            self.nav_group.addButton(button, index)
            sidebar_layout.addWidget(button)

        self.chat_btn.setChecked(True)

        sidebar_layout.addStretch(1)

        # Content
        self.stack = QStackedWidget()

        self.chat_page = ChatWidget(orchestrator)
        self.memory_page = MemoryWidget(orchestrator)
        self.actions_page = ActionsWidget(orchestrator)
        self.settings_page = SettingsWidget(orchestrator)

        self.stack.addWidget(self.chat_page)
        self.stack.addWidget(self.memory_page)
        self.stack.addWidget(self.actions_page)
        self.stack.addWidget(self.settings_page)

        root.addWidget(sidebar)
        root.addWidget(self.stack, stretch=1)

        self.nav_group.idClicked.connect(self.stack.setCurrentIndex)

        self.statusBar().showMessage("Готов")

        self.orch.status_changed.connect(self.statusBar().showMessage)
        self.orch.error.connect(self._show_error)
        self.orch.confirmation_requested.connect(self._ask_confirmation)

    def _show_error(self, message: str) -> None:
        QMessageBox.warning(self, "AURA AI", str(message))

    def _ask_confirmation(self, request: dict) -> None:
        args_text = json.dumps(request.get("args", {}), ensure_ascii=False, indent=2)
        text = (
            f"AURA хочет выполнить действие:\n\n"
            f"Инструмент: {request.get('tool')}\n\n"
            f"Параметры:\n{args_text}\n\n"
            f"Разрешить выполнение?"
        )

        reply = QMessageBox.question(
            self,
            "Подтверждение опасного действия",
            text,
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )

        self.orch.resolve_confirmation(request["id"], reply == QMessageBox.StandardButton.Yes)
