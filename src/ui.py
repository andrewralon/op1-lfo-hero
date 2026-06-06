"""PyQt6 mixer UI for the OP-1 Field controller."""

import time

from PyQt6.QtWidgets import (
    QMainWindow, QWidget, QHBoxLayout, QVBoxLayout,
    QLabel, QPushButton, QSlider, QFrame, QSizePolicy,
    QApplication,
)
from PyQt6.QtCore import Qt, QObject, pyqtSignal, QTimer
from PyQt6.QtGui import QFont, QColor

from src.controller import Controller

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
_BG      = "#1a1a1a"
_PANEL   = "#252525"
_ACCENT  = "#e8541a"   # muted-active orange
_MUTE_OFF = "#333333"
_TEXT    = "#d0d0d0"
_DIM     = "#666666"
_GREEN   = "#4ec94e"


def apply_dark_theme(app: QApplication) -> None:
    app.setStyle("Fusion")
    p = app.palette()
    p.setColor(p.ColorRole.Window,      QColor(_BG))
    p.setColor(p.ColorRole.WindowText,  QColor(_TEXT))
    p.setColor(p.ColorRole.Base,        QColor(_PANEL))
    p.setColor(p.ColorRole.Button,      QColor(_PANEL))
    p.setColor(p.ColorRole.ButtonText,  QColor(_TEXT))
    p.setColor(p.ColorRole.Highlight,   QColor(_ACCENT))
    app.setPalette(p)


# ---------------------------------------------------------------------------
# Cross-thread bridge
# ---------------------------------------------------------------------------

class ClockBridge(QObject):
    """
    Emitted from the clock daemon thread; Qt delivers to the main thread via
    its default AutoConnection (queued when sender/receiver are in different
    threads).  Never touch widgets here — only emit signals.
    """
    beat = pyqtSignal(int)   # fired every 24 MIDI ticks (one musical beat)


# ---------------------------------------------------------------------------
# Per-track strip
# ---------------------------------------------------------------------------

class TrackStrip(QFrame):
    def __init__(self, track: int, controller: Controller, parent=None):
        super().__init__(parent)
        self._track = track
        self._ctrl = controller
        self._ready = False   # suppress CC sends during __init__ setup
        self._setup_ui()
        self._ready = True

    def _setup_ui(self) -> None:
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            f"TrackStrip {{ background-color: {_PANEL}; border-radius: 8px; border: 1px solid #333; }}"
        )
        self.setFixedWidth(130)

        layout = QVBoxLayout(self)
        layout.setSpacing(10)
        layout.setContentsMargins(12, 14, 12, 14)

        # --- Track label ---
        title = QLabel(f"TRACK {self._track}")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        f = QFont()
        f.setPointSize(8)
        f.setBold(True)
        f.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 2.0)
        title.setFont(f)
        title.setStyleSheet(f"color: {_DIM};")
        layout.addWidget(title)

        # --- Mute button ---
        self._mute_btn = QPushButton("MUTE")
        self._mute_btn.setCheckable(True)
        self._mute_btn.setFixedHeight(30)
        self._mute_btn.clicked.connect(self._on_mute_clicked)
        self._set_mute_style(False)
        layout.addWidget(self._mute_btn)

        # --- Pan ---
        pan_lbl = QLabel("PAN")
        pan_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        pan_lbl.setStyleSheet(f"color: {_DIM}; font-size: 8pt;")
        layout.addWidget(pan_lbl)

        pan_row = QHBoxLayout()
        pan_row.setContentsMargins(0, 0, 0, 0)
        for char in ("L", "R"):
            lbl = QLabel(char)
            lbl.setStyleSheet(f"color: {_DIM}; font-size: 7pt;")
            if char == "R":
                pan_row.addStretch()
            pan_row.addWidget(lbl)
            if char == "L":
                self._pan_slider = QSlider(Qt.Orientation.Horizontal)
                self._pan_slider.setRange(0, 127)
                self._pan_slider.setValue(64)
                self._pan_slider.valueChanged.connect(self._on_pan_changed)
                pan_row.addWidget(self._pan_slider)
        layout.addLayout(pan_row)

        self._pan_val = QLabel("C")
        self._pan_val.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._pan_val.setStyleSheet(f"color: {_DIM}; font-size: 8pt;")
        layout.addWidget(self._pan_val)

        # --- Volume ---
        vol_lbl = QLabel("VOLUME")
        vol_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        vol_lbl.setStyleSheet(f"color: {_DIM}; font-size: 8pt;")
        layout.addWidget(vol_lbl)

        # Vertical fader: Qt places min at bottom, max at top — correct for a fader
        self._vol_slider = QSlider(Qt.Orientation.Vertical)
        self._vol_slider.setRange(0, 127)
        self._vol_slider.setValue(100)
        self._vol_slider.setSizePolicy(
            QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Expanding
        )
        self._vol_slider.setMinimumHeight(120)
        self._vol_slider.valueChanged.connect(self._on_volume_changed)
        layout.addWidget(self._vol_slider, alignment=Qt.AlignmentFlag.AlignHCenter)

        self._vol_val = QLabel("100")
        self._vol_val.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._vol_val.setStyleSheet(f"color: {_DIM}; font-size: 8pt;")
        layout.addWidget(self._vol_val)

    # ------------------------------------------------------------------
    # Slots
    # ------------------------------------------------------------------

    def _on_mute_clicked(self, checked: bool) -> None:
        self._set_mute_style(checked)
        if checked:
            self._ctrl.mute(self._track)
        else:
            self._ctrl.unmute(self._track)

    def _set_mute_style(self, muted: bool) -> None:
        bg     = _ACCENT   if muted else _MUTE_OFF
        hover  = "#ff6a35" if muted else "#444444"
        self._mute_btn.setStyleSheet(
            f"QPushButton {{"
            f"  background-color: {bg}; color: {_TEXT};"
            f"  border: none; border-radius: 4px;"
            f"  font-weight: bold; font-size: 8pt; letter-spacing: 1px;"
            f"}}"
            f"QPushButton:hover {{ background-color: {hover}; }}"
        )

    def _on_pan_changed(self, value: int) -> None:
        offset = value - 64
        self._pan_val.setText("C" if offset == 0 else f"{'L' if offset < 0 else 'R'}{abs(offset)}")
        if self._ready:
            self._ctrl.set_pan(self._track, value)

    def _on_volume_changed(self, value: int) -> None:
        self._vol_val.setText(str(value))
        if self._ready:
            self._ctrl.set_volume(self._track, value)


# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------

class MainWindow(QMainWindow):
    def __init__(
        self,
        controller: Controller,
        clock,
        bridge: ClockBridge,
        port_name: str,
    ) -> None:
        super().__init__()
        self._clock = clock
        self._last_beat_time: float | None = None
        self._setup_ui(controller, port_name)

        bridge.beat.connect(self._on_beat)

        # Watchdog: clear BPM display if no beat received for 3 seconds
        self._watchdog = QTimer(self)
        self._watchdog.timeout.connect(self._check_clock_loss)
        self._watchdog.start(500)

    def _setup_ui(self, controller: Controller, port_name: str) -> None:
        self.setWindowTitle("OP-1 MIDI Controller")
        self.setMinimumSize(600, 480)
        self.setStyleSheet(f"QMainWindow {{ background-color: {_BG}; }}")

        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setSpacing(14)
        root.setContentsMargins(18, 16, 18, 16)

        # --- Header row ---
        header = QHBoxLayout()

        title_lbl = QLabel("OP-1 MIDI Controller")
        tf = QFont()
        tf.setPointSize(15)
        tf.setBold(True)
        title_lbl.setFont(tf)
        title_lbl.setStyleSheet(f"color: {_TEXT};")
        header.addWidget(title_lbl)
        header.addStretch()

        self._bpm_label = QLabel("BPM: --")
        bf = QFont("Menlo", 20)
        bf.setBold(True)
        self._bpm_label.setFont(bf)
        self._bpm_label.setStyleSheet(f"color: {_ACCENT};")
        header.addWidget(self._bpm_label)

        root.addLayout(header)

        # --- Status bar ---
        status = QLabel(f"● Connected: {port_name}")
        status.setStyleSheet(f"color: {_GREEN}; font-size: 9pt;")
        root.addWidget(status)

        # --- Separator ---
        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.HLine)
        sep.setStyleSheet("border: none; background-color: #333333; max-height: 1px;")
        root.addWidget(sep)

        # --- Track strips ---
        tracks_row = QHBoxLayout()
        tracks_row.setSpacing(12)
        for t in (1, 2, 3, 4):
            tracks_row.addWidget(TrackStrip(t, controller))
        tracks_row.addStretch()
        root.addLayout(tracks_row)

    def _on_beat(self, _beat_num: int) -> None:
        self._last_beat_time = time.monotonic()
        bpm = self._clock.bpm
        if bpm is not None:
            self._bpm_label.setText(f"BPM: {bpm:.1f}")

    def _check_clock_loss(self) -> None:
        if (
            self._last_beat_time is not None
            and time.monotonic() - self._last_beat_time > 3.0
        ):
            self._bpm_label.setText("BPM: --")
            self._last_beat_time = None
