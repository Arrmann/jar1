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
from .commands_widget import CommandsWidget
from .widgets import ActionsWidget, ChatWidget, MemoryWidget, SettingsWidget


class MainWindow(QMainWindow):
    def __init__(self, cfg: Config, orchestrator: Orchestrator):
        super().__init__()

        self.cfg = cfg
        self.orch = orchestrator

        self.setWindowTitle("JARVIS Assistant")
        self.resize(1480, 920)
        self.setMinimumSize(1120, 720)

        central = QWidget()
        self.setCentralWidget(central)

        root = QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        sidebar = QWidget()
        sidebar.setObjectName("Sidebar")
        sidebar.setMinimumWidth(224)
        sidebar.setMaximumWidth(260)
        sidebar_layout = QVBoxLayout(sidebar)
        sidebar_layout.setContentsMargins(18, 22, 18, 18)
        sidebar_layout.setSpacing(9)

        title = QLabel("JARVIS")
        title.setObjectName("TitleLabel")
        subtitle = QLabel("PERSONAL AI SYSTEM")
        subtitle.setObjectName("SubtitleLabel")
        subtitle.setWordWrap(True)

        sidebar_layout.addWidget(title)
        sidebar_layout.addWidget(subtitle)
        sidebar_layout.addSpacing(24)

        self.nav_group = QButtonGroup(self)
        self.nav_group.setExclusive(True)

        self.chat_btn = QPushButton("◉   Чат")
        self.commands_btn = QPushButton("⌘   Команды")
        self.memory_btn = QPushButton("◈   Память")
        self.actions_btn = QPushButton("▤   Журнал действий")
        self.settings_btn = QPushButton("⚙   Настройки")

        self.buttons = [
            self.chat_btn,
            self.commands_btn,
            self.memory_btn,
            self.actions_btn,
            self.settings_btn,
        ]

        for index, button in enumerate(self.buttons):
            button.setCheckable(True)
            button.setMinimumHeight(46)
            button.setCursor(Qt.CursorShape.PointingHandCursor)
            self.nav_group.addButton(button, index)
            sidebar_layout.addWidget(button)

        self.chat_btn.setChecked(True)
        sidebar_layout.addStretch(1)

        footer = QLabel("JARVIS CORE  ·  LOCAL CONTROL")
        footer.setObjectName("SidebarFooter")
        footer.setWordWrap(True)
        sidebar_layout.addWidget(footer)

        self.stack = QStackedWidget()
        self.chat_page = ChatWidget(orchestrator)
        self.commands_page = CommandsWidget(orchestrator)
        self.memory_page = MemoryWidget(orchestrator)
        self.actions_page = ActionsWidget(orchestrator)
        self.settings_page = SettingsWidget(orchestrator)

        self.stack.addWidget(self.chat_page)
        self.stack.addWidget(self.commands_page)
        self.stack.addWidget(self.memory_page)
        self.stack.addWidget(self.actions_page)
        self.stack.addWidget(self.settings_page)

        root.addWidget(sidebar)
        root.addWidget(self.stack, stretch=1)

        self.nav_group.idClicked.connect(self.stack.setCurrentIndex)

        self.statusBar().showMessage("JARVIS · STANDBY")
        self.orch.status_changed.connect(self.statusBar().showMessage)
        self.orch.error.connect(self._show_error)
        self.orch.confirmation_requested.connect(self._ask_confirmation)

    def _show_error(self, message: str) -> None:
        QMessageBox.warning(self, "JARVIS", str(message))

    def _ask_confirmation(self, request: dict) -> None:
        args_text = json.dumps(
            request.get("args", {}),
            ensure_ascii=False,
            indent=2,
        )
        text = (
            f"JARVIS запрашивает подтверждение действия.\n\n"
            f"Команда: {request.get('tool')}\n\n"
            f"Параметры:\n{args_text}\n\n"
            "Разрешить выполнение?"
        )

        reply = QMessageBox.question(
            self,
            "Подтверждение действия",
            text,
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )

        self.orch.resolve_confirmation(
            request["id"],
            reply == QMessageBox.StandardButton.Yes,
        )
