from __future__ import annotations

import json
import uuid

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QSplitter,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from ..core.command_catalog import normalize_phrase


STEP_LABELS = {
    "command": "Системная команда",
    "speak": "Голосовой ответ",
    "wait": "Пауза",
    "open_url": "Открыть ссылку",
}


class CustomCommandsWidget(QWidget):
    """No-code sequence editor for safe, reusable voice commands."""

    def __init__(self, orchestrator):
        super().__init__()
        self.orch = orchestrator
        self.store = orchestrator.custom_commands
        self.current_id: str | None = None
        self.steps: list[dict] = []

        root = QVBoxLayout(self)
        root.setContentsMargins(18, 18, 18, 18)
        root.setSpacing(10)

        title = QLabel("МОИ СЦЕНАРИИ")
        title.setObjectName("SectionTitle")
        subtitle = QLabel(
            "Создавай собственные голосовые команды из готовых безопасных действий. "
            "Никакого кода или произвольного PowerShell."
        )
        subtitle.setObjectName("SubtitleLabel")
        subtitle.setWordWrap(True)
        root.addWidget(title)
        root.addWidget(subtitle)

        toolbar = QHBoxLayout()
        self.new_btn = QPushButton("Новый сценарий")
        self.save_btn = QPushButton("Сохранить")
        self.delete_btn = QPushButton("Удалить")
        self.import_btn = QPushButton("Импорт")
        self.export_btn = QPushButton("Экспорт")
        for button in (self.new_btn, self.save_btn, self.delete_btn, self.import_btn, self.export_btn):
            toolbar.addWidget(button)
        root.addLayout(toolbar)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        left = QWidget()
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.addWidget(QLabel("СОХРАНЁННЫЕ СЦЕНАРИИ"))
        self.command_list = QListWidget()
        left_layout.addWidget(self.command_list)
        splitter.addWidget(left)

        editor = QWidget()
        editor_layout = QVBoxLayout(editor)
        editor_layout.setContentsMargins(8, 0, 0, 0)

        form = QFormLayout()
        self.name = QLineEdit()
        self.name.setPlaceholderText("Например: Рабочий режим")
        self.phrases = QLineEdit()
        self.phrases.setPlaceholderText("рабочий режим, собери рабочее место")
        self.enabled = QCheckBox("Сценарий включён")
        self.enabled.setChecked(True)
        form.addRow("Название", self.name)
        form.addRow("Фразы через запятую", self.phrases)
        form.addRow("", self.enabled)
        editor_layout.addLayout(form)

        editor_layout.addWidget(QLabel("ПОСЛЕДОВАТЕЛЬНОСТЬ ДЕЙСТВИЙ"))
        self.step_table = QTableWidget(0, 3)
        self.step_table.setHorizontalHeaderLabels(["Шаг", "Действие", "Параметр"])
        self.step_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.step_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.step_table.verticalHeader().setVisible(False)
        self.step_table.horizontalHeader().setStretchLastSection(True)
        self.step_table.setColumnWidth(0, 55)
        self.step_table.setColumnWidth(1, 180)
        editor_layout.addWidget(self.step_table, 1)

        add_row = QHBoxLayout()
        self.step_type = QComboBox()
        for key, label in STEP_LABELS.items():
            self.step_type.addItem(label, key)
        self.step_command = QComboBox()
        self.step_value = QLineEdit()
        self.step_value.setPlaceholderText("Параметр действия")
        self.add_step_btn = QPushButton("Добавить шаг")
        add_row.addWidget(self.step_type)
        add_row.addWidget(self.step_command, 2)
        add_row.addWidget(self.step_value, 2)
        add_row.addWidget(self.add_step_btn)
        editor_layout.addLayout(add_row)

        order_row = QHBoxLayout()
        self.up_btn = QPushButton("↑ Выше")
        self.down_btn = QPushButton("↓ Ниже")
        self.remove_step_btn = QPushButton("Убрать шаг")
        order_row.addWidget(self.up_btn)
        order_row.addWidget(self.down_btn)
        order_row.addWidget(self.remove_step_btn)
        order_row.addStretch(1)
        editor_layout.addLayout(order_row)

        self.help_label = QLabel(
            "Пример: открыть браузер → открыть Telegram → сказать «Рабочий режим готов». "
            "Опасные системные шаги отдельно запросят подтверждение."
        )
        self.help_label.setObjectName("SubtitleLabel")
        self.help_label.setWordWrap(True)
        editor_layout.addWidget(self.help_label)

        splitter.addWidget(editor)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 3)
        root.addWidget(splitter, 1)

        self.step_type.currentIndexChanged.connect(self._update_step_editor)
        self.add_step_btn.clicked.connect(self.add_step)
        self.remove_step_btn.clicked.connect(self.remove_step)
        self.up_btn.clicked.connect(lambda: self.move_step(-1))
        self.down_btn.clicked.connect(lambda: self.move_step(1))
        self.new_btn.clicked.connect(self.new_command)
        self.save_btn.clicked.connect(self.save_command)
        self.delete_btn.clicked.connect(self.delete_command)
        self.import_btn.clicked.connect(self.import_commands)
        self.export_btn.clicked.connect(self.export_commands)
        self.command_list.currentItemChanged.connect(self.select_command)

        self._update_step_editor()
        self.refresh_list()
        self.new_command()

    def refresh_list(self) -> None:
        selected = self.current_id
        self.command_list.clear()
        for command in self.store.commands:
            state = "●" if command.get("enabled", True) else "○"
            item = QListWidgetItem(f"{state}  {command['name']}")
            item.setData(Qt.ItemDataRole.UserRole, command["id"])
            self.command_list.addItem(item)
            if command["id"] == selected:
                self.command_list.setCurrentItem(item)

    def new_command(self) -> None:
        self.current_id = uuid.uuid4().hex
        self.name.clear()
        self.phrases.clear()
        self.enabled.setChecked(True)
        self.steps = []
        self._render_steps()
        self.command_list.clearSelection()

    def select_command(self, current, previous=None) -> None:
        if current is None:
            return
        command_id = str(current.data(Qt.ItemDataRole.UserRole) or "")
        command = self.store.get(command_id)
        if not command:
            return
        self.current_id = command_id
        self.name.setText(command["name"])
        self.phrases.setText(", ".join(command["phrases_ru"]))
        self.enabled.setChecked(bool(command.get("enabled", True)))
        self.steps = [dict(step) for step in command["steps"]]
        self._render_steps()

    def _update_step_editor(self, *_):
        kind = str(self.step_type.currentData() or "command")
        self.step_command.setVisible(kind == "command")
        placeholders = {
            "command": "Дополнительный параметр команды (необязательно)",
            "speak": "Текст, который произнесёт ассистент",
            "wait": "Секунды (0–30)",
            "open_url": "Полная ссылка https://...",
        }
        self.step_value.setPlaceholderText(placeholders.get(kind, "Параметр"))
        self.step_command.clear()
        if kind == "command":
            for command in self.orch.jarvis_commands.catalog.commands:
                command_id = str(command.get("id", ""))
                if self.orch.jarvis_commands.status(command_id) == "ready":
                    label = f"{command_id} — {str(command.get('description') or '')[:70]}"
                    self.step_command.addItem(label, command_id)

    def add_step(self) -> None:
        kind = str(self.step_type.currentData() or "command")
        value = self.step_value.text().strip()
        if kind == "command":
            command_id = str(self.step_command.currentData() or "")
            if not command_id:
                QMessageBox.warning(self, "Сценарии", "Нет доступных системных команд.")
                return
            step = {"type": "command", "command_id": command_id, "query": value}
            self.step_value.clear()
        elif kind == "speak":
            if not value:
                QMessageBox.warning(self, "Сценарии", "Укажи текст для голосового ответа.")
                return
            step = {"type": "speak", "text": value}
            self.step_value.clear()
        elif kind == "wait":
            try:
                seconds = float(value.replace(",", "."))
            except ValueError:
                QMessageBox.warning(self, "Сценарии", "Укажи длительность паузы числом от 0 до 30.")
                return
            if not 0 <= seconds <= 30:
                QMessageBox.warning(self, "Сценарии", "Пауза должна быть от 0 до 30 секунд.")
                return
            step = {"type": "wait", "seconds": seconds}
            self.step_value.clear()
        else:
            step = {"type": "open_url", "url": value}
            try:
                self.orch.custom_commands.validate({
                    "name": "Проверка", "phrases_ru": ["проверка"], "steps": [step]
                })
            except Exception as exc:
                QMessageBox.warning(self, "Сценарии", str(exc))
                return
            self.step_value.clear()

        self.steps.append(step)
        self._render_steps()

    def _step_summary(self, step: dict) -> tuple[str, str]:
        kind = str(step.get("type", ""))
        if kind == "command":
            command_id = str(step.get("command_id", ""))
            command = self.orch.jarvis_commands.catalog.get(command_id) or {}
            return str(command.get("description") or command_id), str(step.get("query", ""))
        if kind == "speak":
            return "Произнести ответ", str(step.get("text", ""))
        if kind == "wait":
            return "Подождать", f"{step.get('seconds', 0)} сек."
        if kind == "open_url":
            return "Открыть ссылку", str(step.get("url", ""))
        return "Неизвестный шаг", ""

    def _render_steps(self) -> None:
        self.step_table.setRowCount(len(self.steps))
        for index, step in enumerate(self.steps):
            label, parameter = self._step_summary(step)
            type_item = QTableWidgetItem(str(index + 1))
            type_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            action_item = QTableWidgetItem(label)
            action_item.setData(Qt.ItemDataRole.UserRole, dict(step))
            parameter_item = QTableWidgetItem(parameter)
            self.step_table.setItem(index, 0, type_item)
            self.step_table.setItem(index, 1, action_item)
            self.step_table.setItem(index, 2, parameter_item)
        self.step_table.resizeRowsToContents()

    def remove_step(self) -> None:
        row = self.step_table.currentRow()
        if 0 <= row < len(self.steps):
            self.steps.pop(row)
            self._render_steps()

    def move_step(self, delta: int) -> None:
        row = self.step_table.currentRow()
        target = row + delta
        if not (0 <= row < len(self.steps) and 0 <= target < len(self.steps)):
            return
        self.steps[row], self.steps[target] = self.steps[target], self.steps[row]
        self._render_steps()
        self.step_table.selectRow(target)

    def _phrase_conflict(self, phrases: list[str]) -> str | None:
        system_phrases = set()
        for command in self.orch.jarvis_commands.catalog.commands:
            if self.orch.jarvis_commands.status(str(command.get("id", ""))) != "ready":
                continue
            system_phrases.update(normalize_phrase(p) for p in command.get("phrases_ru", []))
        for phrase in phrases:
            key = normalize_phrase(phrase)
            for system_phrase in system_phrases:
                if (
                    key == system_phrase
                    or key.startswith(system_phrase + " ")
                    or system_phrase.startswith(key + " ")
                ):
                    return phrase
        return None

    def save_command(self) -> None:
        phrases = [p.strip() for p in self.phrases.text().replace(";", ",").split(",") if p.strip()]
        if not self.steps:
            QMessageBox.warning(self, "Сценарии", "Добавь хотя бы один шаг.")
            return
        conflict = self._phrase_conflict(phrases)
        if conflict:
            QMessageBox.warning(
                self, "Конфликт фразы",
                f"Фраза «{conflict}» уже используется системной командой. Выбери другую, чтобы голосовое управление не путалось."
            )
            return
        payload = {
            "id": self.current_id or uuid.uuid4().hex,
            "name": self.name.text().strip(),
            "phrases_ru": phrases,
            "enabled": self.enabled.isChecked(),
            "steps": self.steps,
        }
        try:
            saved = self.store.upsert(payload)
        except Exception as exc:
            QMessageBox.warning(self, "Сценарии", str(exc))
            return
        self.current_id = saved["id"]
        self.refresh_list()
        QMessageBox.information(self, "Сценарии", "Сценарий сохранён.")

    def delete_command(self) -> None:
        if not self.current_id or not self.store.get(self.current_id):
            return
        reply = QMessageBox.question(
            self, "Удалить сценарий", "Удалить выбранный сценарий?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        self.store.delete(self.current_id)
        self.current_id = None
        self.refresh_list()
        self.new_command()

    def import_commands(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Импорт сценариев", "", "JSON (*.json)")
        if not path:
            return
        try:
            payload = json.loads(open(path, "r", encoding="utf-8").read())
            count = self.store.import_data(payload)
        except Exception as exc:
            QMessageBox.warning(self, "Импорт", str(exc))
            return
        self.refresh_list()
        QMessageBox.information(self, "Импорт", f"Импортировано сценариев: {count}.")

    def export_commands(self) -> None:
        path, _ = QFileDialog.getSaveFileName(self, "Экспорт сценариев", "JARVIS-scenarios.json", "JSON (*.json)")
        if not path:
            return
        try:
            with open(path, "w", encoding="utf-8") as file:
                json.dump(self.store.export_data(), file, ensure_ascii=False, indent=2)
        except OSError as exc:
            QMessageBox.warning(self, "Экспорт", str(exc))
            return
        QMessageBox.information(self, "Экспорт", "Сценарии экспортированы.")
