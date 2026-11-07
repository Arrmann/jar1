from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QComboBox, QHBoxLayout, QLabel, QLineEdit, QPushButton,
    QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
)


GROUP_LABELS = {
    "basics": "Основные",
    "control": "Управление",
    "daily": "Ежедневные",
    "extras": "Дополнительные",
    "notes": "Заметки",
    "popular": "Популярные",
}
STATUS_LABELS = {
    "ready": "Работает",
    "setup": "Нужна настройка",
    "planned": "В плане",
}


class CommandsWidget(QWidget):
    """Searchable view of the imported JARVIS demo command catalog."""

    def __init__(self, orchestrator):
        super().__init__()
        self.orch = orchestrator
        self.catalog = orchestrator.jarvis_commands.catalog

        root = QVBoxLayout(self)
        root.setContentsMargins(18, 18, 18, 18)
        root.setSpacing(10)

        title = QLabel("БИБЛИОТЕКА КОМАНД")
        title.setObjectName("SectionTitle")
        subtitle = QLabel(
            "Каталог демо JARVIS: локальные команды доступны сразу; "
            "часть сценариев требует API, устройств или отдельной настройки."
        )
        subtitle.setObjectName("SubtitleLabel")
        subtitle.setWordWrap(True)

        root.addWidget(title)
        root.addWidget(subtitle)

        self.summary = QLabel()
        self.summary.setObjectName("CommandSummary")
        root.addWidget(self.summary)

        controls = QHBoxLayout()
        self.search = QLineEdit()
        self.search.setPlaceholderText("Найти команду или фразу…")
        self.group = QComboBox()
        self.group.addItem("Все категории", "")
        for key, label in GROUP_LABELS.items():
            self.group.addItem(label, key)
        self.status_filter = QComboBox()
        self.status_filter.addItem("Все статусы", "")
        self.status_filter.addItem("Работает", "ready")
        self.status_filter.addItem("Нужна настройка", "setup")
        self.status_filter.addItem("В плане", "planned")
        self.refresh_btn = QPushButton("Обновить")

        controls.addWidget(self.search, 3)
        controls.addWidget(self.group, 1)
        controls.addWidget(self.status_filter, 1)
        controls.addWidget(self.refresh_btn)
        root.addLayout(controls)

        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels(
            ["Категория", "Команда", "Назначение", "Примеры фраз", "Статус"]
        )
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.setWordWrap(True)
        self.table.verticalHeader().setVisible(False)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.setColumnWidth(0, 115)
        self.table.setColumnWidth(1, 165)
        self.table.setColumnWidth(2, 300)
        self.table.setColumnWidth(3, 330)
        self.table.setColumnWidth(4, 130)
        root.addWidget(self.table, 1)

        self.details = QLabel("Выбери команду, чтобы увидеть примеры её голосовых фраз.")
        self.details.setObjectName("SubtitleLabel")
        self.details.setWordWrap(True)
        root.addWidget(self.details)

        self.try_input = QLineEdit()
        self.try_input.setPlaceholderText("Проверить фразу, например: Джарвис, открой YouTube")
        self.try_button = QPushButton("Отправить в JARVIS")
        try_row = QHBoxLayout()
        try_row.addWidget(self.try_input, 1)
        try_row.addWidget(self.try_button)
        root.addLayout(try_row)

        self.search.textChanged.connect(self.refresh)
        self.group.currentIndexChanged.connect(self.refresh)
        self.status_filter.currentIndexChanged.connect(self.refresh)
        self.refresh_btn.clicked.connect(self.refresh)
        self.table.itemSelectionChanged.connect(self.show_selected)
        self.try_button.clicked.connect(self.try_phrase)
        self.try_input.returnPressed.connect(self.try_phrase)

        self.refresh()

    def refresh(self, *_):
        service = self.orch.jarvis_commands
        counts = service.counts()
        self.summary.setText(
            f"Всего: {len(self.catalog.commands)}    "
            f"Работает: {counts['ready']}    "
            f"Нужна настройка: {counts['setup']}    "
            f"В плане: {counts['planned']}"
        )

        query = self.search.text().strip()
        group = str(self.group.currentData() or "")
        selected_status = str(self.status_filter.currentData() or "")
        rows = self.catalog.search(query, group)

        if selected_status:
            rows = [
                row for row in rows
                if service.status(str(row.get("id", ""))) == selected_status
            ]

        self.table.setRowCount(len(rows))
        for index, command in enumerate(rows):
            command_id = str(command.get("id", ""))
            group_key = str(command.get("group", ""))
            phrases = list(command.get("phrases_ru") or [])[:3]
            description = str(command.get("description") or "")
            status = service.status(command_id)

            values = [
                GROUP_LABELS.get(group_key, group_key),
                command_id,
                description or "—",
                " · ".join(phrases) if phrases else "—",
                STATUS_LABELS.get(status, status),
            ]
            for column, value in enumerate(values):
                item = QTableWidgetItem(value)
                if column == 1:
                    item.setData(Qt.ItemDataRole.UserRole, command_id)
                self.table.setItem(index, column, item)

        self.table.resizeRowsToContents()

    def show_selected(self):
        row = self.table.currentRow()
        if row < 0:
            return
        command_id = self.table.item(row, 1).text()
        command = self.catalog.get(command_id) or {}
        ru = list(command.get("phrases_ru") or [])
        en = list(command.get("phrases_en") or [])
        status = STATUS_LABELS.get(
            self.orch.jarvis_commands.status(command_id), "В плане"
        )
        self.details.setText(
            f"{command_id} · {status}\n"
            f"Русские фразы: {', '.join(ru[:12]) or 'нет'}\n"
            f"English: {', '.join(en[:8]) or 'нет'}"
        )

    def try_phrase(self):
        phrase = self.try_input.text().strip()
        if not phrase:
            return
        self.try_input.clear()
        self.orch.submit_text(phrase)
