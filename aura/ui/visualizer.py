import math

from PySide6.QtCore import QTimer, Qt, QRectF
from PySide6.QtGui import QColor, QPainter, QRadialGradient
from PySide6.QtWidgets import QWidget


class AuraVisualizer(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._state = "idle"
        self.phase = 0.0
        self.setMinimumSize(180, 180)

        self.timer = QTimer(self)
        self.timer.setInterval(33)
        self.timer.timeout.connect(self._tick)
        self.timer.start()

    def set_state(self, state: str) -> None:
        self._state = state
        self.update()

    def _tick(self) -> None:
        self.phase += 0.14
        self.update()

    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        side = min(self.width(), self.height())
        center_x = self.width() / 2
        center_y = self.height() / 2

        if self._state == "listening":
            color1 = QColor("#38bdf8")
            color2 = QColor("#2563eb")
            amplitude = side * 0.045
            speed = 1.25
        elif self._state == "thinking":
            color1 = QColor("#a78bfa")
            color2 = QColor("#7c3aed")
            amplitude = side * 0.035
            speed = 1.8
        elif self._state == "speaking":
            color1 = QColor("#60a5fa")
            color2 = QColor("#9333ea")
            amplitude = side * 0.06
            speed = 2.1
        else:
            color1 = QColor("#334155")
            color2 = QColor("#1d4ed8")
            amplitude = side * 0.015
            speed = 0.7

        radius = side * 0.24 + math.sin(self.phase * speed) * amplitude

        gradient = QRadialGradient(center_x, center_y, radius * 1.5)
        gradient.setColorAt(0.0, color1)
        gradient.setColorAt(0.65, color2)
        gradient.setColorAt(1.0, QColor(7, 11, 20, 0))

        painter.setBrush(gradient)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawEllipse(QRectF(center_x - radius, center_y - radius, radius * 2, radius * 2))
