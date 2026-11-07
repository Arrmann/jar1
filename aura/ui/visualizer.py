import math

from PySide6.QtCore import QTimer, Qt, QRectF, QPointF
from PySide6.QtGui import QColor, QFont, QPainter, QPen, QRadialGradient
from PySide6.QtWidgets import QWidget


class AuraVisualizer(QWidget):
    """JARVIS-style cyan HUD core, driven by the voice state machine."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._state = "idle"
        self.phase = 0.0
        self.setMinimumSize(210, 210)
        self.setMaximumHeight(310)

        self.timer = QTimer(self)
        self.timer.setInterval(33)
        self.timer.timeout.connect(self._tick)
        self.timer.start()

    def set_state(self, state: str) -> None:
        if state not in ("idle", "listening", "thinking", "speaking"):
            state = "idle"
        self._state = state
        self.update()

    def _tick(self) -> None:
        self.phase = (self.phase + 0.018) % (math.pi * 2)
        self.update()

    @staticmethod
    def _arc(painter, cx, cy, radius, start, span, color, width):
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.setPen(QPen(
            QColor(color), width,
            Qt.PenStyle.SolidLine,
            Qt.PenCapStyle.RoundCap
        ))
        rect = QRectF(cx - radius, cy - radius, radius * 2, radius * 2)
        painter.drawArc(rect, int(start * 16), int(span * 16))

    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        side = min(self.width(), self.height())
        cx = self.width() / 2
        cy = self.height() / 2
        radius = side * 0.43

        palette = {
            "idle": ("#5CF6F0", "#187C89", 0.30, 0.65),
            "listening": ("#8BFFFF", "#18C9E4", 0.90, 1.30),
            "thinking": ("#B1F7FF", "#469CC7", 0.65, 1.80),
            "speaking": ("#FFFFFF", "#39E6F0", 1.0, 2.10),
        }
        primary, secondary, intensity, speed = palette[self._state]
        pulse = math.sin(self.phase * 5.0)
        rotation = math.degrees(self.phase) * speed

        # Ambient central bloom.
        bloom = QRadialGradient(QPointF(cx, cy), radius * 1.75)
        bloom.setColorAt(0.0, QColor(35, 205, 221, int(35 * intensity)))
        bloom.setColorAt(0.46, QColor(22, 131, 160, int(18 * intensity)))
        bloom.setColorAt(1.0, QColor(0, 0, 0, 0))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(bloom)
        painter.drawEllipse(QRectF(
            cx - radius * 1.75, cy - radius * 1.75,
            radius * 3.5, radius * 3.5
        ))

        # Thin concentric rings.
        for factor, alpha, width in (
            (0.46, 80, 0.8),
            (0.61, 65, 0.8),
            (0.77, 100, 1.0),
            (0.94, 155, 1.2),
        ):
            color = QColor(primary)
            color.setAlpha(int(alpha * intensity))
            painter.setPen(QPen(color, width))
            painter.setBrush(Qt.BrushStyle.NoBrush)
            r = radius * factor
            painter.drawEllipse(QRectF(cx-r, cy-r, 2*r, 2*r))

        # Outer radial tick marks.
        for index in range(96):
            angle = math.radians(index * 3.75 - rotation * 0.12)
            major = index % 8 == 0
            inner = radius * (0.955 if major else 0.975)
            outer = radius * (1.005 if major else 0.992)
            color = QColor(primary)
            color.setAlpha(int((185 if major else 72) * intensity))
            painter.setPen(QPen(color, 1.3 if major else 0.65))
            painter.drawLine(
                QPointF(cx + math.cos(angle) * inner, cy + math.sin(angle) * inner),
                QPointF(cx + math.cos(angle) * outer, cy + math.sin(angle) * outer),
            )

        # Rotating broken arcs make the center feel like a live HUD, not a static logo.
        self._arc(painter, cx, cy, radius * 0.86, rotation, 67, primary, 2.1)
        self._arc(painter, cx, cy, radius * 0.82, -rotation * 1.37, 28, secondary, 2.8)
        self._arc(painter, cx, cy, radius * 0.69, rotation * 1.7 + 90, 103, primary, 1.1)
        self._arc(painter, cx, cy, radius * 0.56, -rotation * 0.8, 42, secondary, 1.5)

        # Dotted data ring.
        for index in range(64):
            angle = math.radians(index * 5.625 + rotation * 0.22)
            wave = (math.sin(index * 1.2 + self.phase * 7.0) + 1.0) * 0.5
            dot_radius = 1.0 + wave * (1.4 * intensity)
            distance = radius * 0.70
            x = cx + math.cos(angle) * distance
            y = cy + math.sin(angle) * distance
            color = QColor(primary)
            color.setAlpha(int((80 + 135 * wave) * intensity))
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(color)
            painter.drawEllipse(QPointF(x, y), dot_radius, dot_radius)

        # Core sphere.
        core_radius = side * (0.19 + abs(pulse) * 0.008 * intensity)
        gradient = QRadialGradient(
            QPointF(cx - core_radius * 0.30, cy - core_radius * 0.35),
            core_radius * 1.85
        )
        gradient.setColorAt(0.0, QColor("#F4FFFF"))
        gradient.setColorAt(0.13, QColor(primary))
        gradient.setColorAt(0.55, QColor(24, 142, 168))
        gradient.setColorAt(0.88, QColor(8, 40, 55))
        gradient.setColorAt(1.0, QColor(3, 13, 22))
        painter.setPen(QPen(QColor(primary), 1.1))
        painter.setBrush(gradient)
        painter.drawEllipse(QRectF(
            cx - core_radius, cy - core_radius,
            core_radius * 2, core_radius * 2
        ))

        # Core inner outline and central label.
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.setPen(QPen(QColor(220, 255, 255, 150), 0.9))
        painter.drawEllipse(QRectF(
            cx - core_radius * 0.76, cy - core_radius * 0.76,
            core_radius * 1.52, core_radius * 1.52
        ))

        font = QFont("Segoe UI")
        font.setPixelSize(max(10, int(side * 0.071)))
        font.setWeight(QFont.Weight.DemiBold)
        painter.setFont(font)
        painter.setPen(QColor("#F1FFFF"))
        painter.drawText(
            QRectF(cx - core_radius * 1.3, cy - side * 0.045,
                   core_radius * 2.6, side * 0.10),
            Qt.AlignmentFlag.AlignCenter, "JARVIS"
        )

        small = QFont("Segoe UI")
        small.setPixelSize(max(7, int(side * 0.030)))
        small.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 1.9)
        painter.setFont(small)
        painter.setPen(QColor("#B7EEF0"))
        painter.drawText(
            QRectF(cx - radius, cy + radius * 1.12,
                   radius * 2, side * 0.07),
            Qt.AlignmentFlag.AlignCenter,
            {
                "idle": "STANDBY",
                "listening": "LISTENING",
                "thinking": "PROCESSING",
                "speaking": "RESPONDING",
            }[self._state]
        )

        painter.end()
