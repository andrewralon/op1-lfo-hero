"""PyQt6 mixer UI for the OP-1 Field controller."""

import time

from PyQt6.QtWidgets import (
    QMainWindow, QWidget, QHBoxLayout, QVBoxLayout,
    QLabel, QPushButton, QSlider, QFrame, QSizePolicy,
    QApplication, QComboBox, QSpinBox, QCheckBox, QListWidget,
    QListWidgetItem,
)
from PyQt6.QtCore import Qt, QObject, pyqtSignal, QTimer
from PyQt6.QtGui import QFont, QColor

from src.controller import Controller
from src.automation import AutomationEngine, Clip, Parameter, CURVE_LABELS, PARAMETER_LABELS

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
    beat = pyqtSignal(int)                  # every 24 MIDI ticks (one beat)
    automation_update = pyqtSignal(int, str, int)  # (track, param_name, value)


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

    def set_automation_value(self, param_name: str, value: int) -> None:
        """Move a slider to reflect an automation value without sending CC."""
        if param_name == Parameter.VOLUME.value:
            self._vol_slider.blockSignals(True)
            self._vol_slider.setValue(value)
            self._vol_slider.blockSignals(False)
            self._vol_val.setText(str(value))
        elif param_name == Parameter.PAN.value:
            self._pan_slider.blockSignals(True)
            self._pan_slider.setValue(value)
            self._pan_slider.blockSignals(False)
            offset = value - 64
            self._pan_val.setText("C" if offset == 0 else f"{'L' if offset < 0 else 'R'}{abs(offset)}")


# ---------------------------------------------------------------------------
# Automation panel
# ---------------------------------------------------------------------------

class AutomationPanel(QFrame):
    def __init__(self, engine: AutomationEngine, clock, parent=None):
        super().__init__(parent)
        self._engine = engine
        self._clock = clock
        self._clip_objects: list[Clip] = []   # mirrors engine clips for display
        self._setup_ui()

    def _setup_ui(self) -> None:
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            f"AutomationPanel {{ background-color: {_PANEL}; border-radius: 8px; border: 1px solid #333; }}"
        )

        root = QVBoxLayout(self)
        root.setSpacing(8)
        root.setContentsMargins(14, 10, 14, 12)

        # Section title
        title = QLabel("AUTOMATION")
        tf = QFont()
        tf.setPointSize(8)
        tf.setBold(True)
        tf.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 2.0)
        title.setFont(tf)
        title.setStyleSheet(f"color: {_DIM};")
        root.addWidget(title)

        body = QHBoxLayout()
        body.setSpacing(16)

        # --- Left: form controls ---
        form = QVBoxLayout()
        form.setSpacing(6)

        # Row 1: Track, Parameter, Curve
        row1 = QHBoxLayout()
        row1.setSpacing(8)
        for lbl_text, widget in [
            ("Track",  self._make_combo([str(t) for t in (1, 2, 3, 4)], "_track_box")),
            ("Param",  self._make_combo(list(PARAMETER_LABELS), "_param_box")),
            ("Curve",  self._make_combo(list(CURVE_LABELS), "_curve_box")),
        ]:
            row1.addWidget(self._dim_label(lbl_text))
            row1.addWidget(widget)
        form.addLayout(row1)

        # Row 2: From, To, Duration, Loop
        row2 = QHBoxLayout()
        row2.setSpacing(8)

        self._from_spin = QSpinBox()
        self._from_spin.setRange(0, 127)
        self._from_spin.setValue(100)
        self._from_spin.setFixedWidth(52)

        self._to_spin = QSpinBox()
        self._to_spin.setRange(0, 127)
        self._to_spin.setValue(0)
        self._to_spin.setFixedWidth(52)

        self._dur_spin = QSpinBox()
        self._dur_spin.setRange(1, 128)
        self._dur_spin.setValue(8)
        self._dur_spin.setFixedWidth(52)

        self._loop_chk = QCheckBox("Loop")
        self._loop_chk.setStyleSheet(f"color: {_TEXT}; font-size: 9pt;")

        for lbl_text, widget in [
            ("From", self._from_spin),
            ("To",   self._to_spin),
            ("Dur",  self._dur_spin),
        ]:
            row2.addWidget(self._dim_label(lbl_text))
            row2.addWidget(widget)
        row2.addWidget(self._dim_label("beats"))
        row2.addSpacing(8)
        row2.addWidget(self._loop_chk)
        form.addLayout(row2)

        # Row 3: buttons
        row3 = QHBoxLayout()
        row3.setSpacing(8)

        add_btn = QPushButton("▶  Add")
        add_btn.setFixedHeight(28)
        add_btn.setStyleSheet(
            f"QPushButton {{ background-color: #2a5a2a; color: {_TEXT}; border: none; border-radius: 4px; font-size: 9pt; }}"
            f"QPushButton:hover {{ background-color: #336633; }}"
        )
        add_btn.clicked.connect(self._on_add)

        clear_btn = QPushButton("✕  Clear All")
        clear_btn.setFixedHeight(28)
        clear_btn.setStyleSheet(
            f"QPushButton {{ background-color: {_MUTE_OFF}; color: {_TEXT}; border: none; border-radius: 4px; font-size: 9pt; }}"
            f"QPushButton:hover {{ background-color: #444; }}"
        )
        clear_btn.clicked.connect(self._on_clear)

        row3.addWidget(add_btn)
        row3.addWidget(clear_btn)
        row3.addStretch()
        form.addLayout(row3)

        body.addLayout(form)

        # --- Right: active clip list ---
        right = QVBoxLayout()
        right.setSpacing(4)
        right.addWidget(self._dim_label("Active clips"))
        self._clip_list = QListWidget()
        self._clip_list.setStyleSheet(
            f"QListWidget {{ background-color: {_BG}; color: {_TEXT}; border: 1px solid #333; border-radius: 4px; font-size: 8pt; }}"
        )
        self._clip_list.setMinimumWidth(200)
        self._clip_list.setMaximumHeight(90)
        right.addWidget(self._clip_list)
        body.addLayout(right)

        root.addLayout(body)

    def _make_combo(self, items: list[str], attr: str) -> QComboBox:
        box = QComboBox()
        box.addItems(items)
        box.setStyleSheet(f"font-size: 9pt; color: {_TEXT}; background-color: {_BG};")
        setattr(self, attr, box)
        return box

    def _dim_label(self, text: str) -> QLabel:
        lbl = QLabel(text)
        lbl.setStyleSheet(f"color: {_DIM}; font-size: 8pt;")
        return lbl

    def _on_add(self) -> None:
        track    = int(self._track_box.currentText())
        param    = PARAMETER_LABELS[self._param_box.currentText()]
        curve    = CURVE_LABELS[self._curve_box.currentText()]
        from_val = self._from_spin.value()
        to_val   = self._to_spin.value()
        dur      = self._dur_spin.value()
        loop     = self._loop_chk.isChecked()

        # Start on the next beat so the clip is always beat-aligned
        start = max(1, self._clock.beat_count + 1)

        clip = Clip(
            track=track,
            parameter=param,
            start_beat=start,
            duration_beats=dur,
            start_value=from_val,
            end_value=to_val,
            curve=curve,
            loop=loop,
        )
        self._engine.add(clip)
        self._clip_objects.append(clip)
        self._refresh_list()

    def _on_clear(self) -> None:
        self._engine.clear()
        self._clip_objects.clear()
        self._clip_list.clear()

    def refresh(self) -> None:
        """Sync list display with engine state — call from _on_beat."""
        active = self._engine.clips
        active_ids = {id(c) for c in active}
        self._clip_objects = [c for c in self._clip_objects if id(c) in active_ids]
        self._refresh_list()

    def _refresh_list(self) -> None:
        self._clip_list.clear()
        for clip in self._clip_objects:
            curve_name = next(k for k, v in CURVE_LABELS.items() if v is clip.curve)
            loop_tag = " ↻" if clip.loop else ""
            label = (
                f"T{clip.track} {clip.parameter.value.upper()[:3]}  "
                f"{clip.start_value}→{clip.end_value}  "
                f"{clip.duration_beats}b  {curve_name}{loop_tag}"
            )
            self._clip_list.addItem(QListWidgetItem(label))


# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------

class MainWindow(QMainWindow):
    def __init__(
        self,
        controller: Controller,
        clock,
        engine: AutomationEngine,
        bridge: ClockBridge,
        port_name: str,
    ) -> None:
        super().__init__()
        self._clock = clock
        self._last_beat_time: float | None = None
        self._strips: dict[int, TrackStrip] = {}
        self._setup_ui(controller, engine, port_name)

        bridge.beat.connect(self._on_beat)
        bridge.automation_update.connect(self._on_automation_update)

        # Watchdog: clear BPM display if no beat received for 3 seconds
        self._watchdog = QTimer(self)
        self._watchdog.timeout.connect(self._check_clock_loss)
        self._watchdog.start(500)

    def _setup_ui(self, controller: Controller, engine: AutomationEngine, port_name: str) -> None:
        self.setWindowTitle("OP-1 MIDI Controller")
        self.setMinimumSize(640, 560)
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
            strip = TrackStrip(t, controller)
            self._strips[t] = strip
            tracks_row.addWidget(strip)
        tracks_row.addStretch()
        root.addLayout(tracks_row)

        # --- Separator ---
        sep2 = QFrame()
        sep2.setFrameShape(QFrame.Shape.HLine)
        sep2.setStyleSheet("border: none; background-color: #333333; max-height: 1px;")
        root.addWidget(sep2)

        # --- Automation panel ---
        self._auto_panel = AutomationPanel(engine, self._clock)
        root.addWidget(self._auto_panel)

    def _on_beat(self, _beat_num: int) -> None:
        self._last_beat_time = time.monotonic()
        bpm = self._clock.bpm
        if bpm is not None:
            self._bpm_label.setText(f"BPM: {bpm:.1f}")
        self._auto_panel.refresh()

    def _on_automation_update(self, track: int, param_name: str, value: int) -> None:
        strip = self._strips.get(track)
        if strip:
            strip.set_automation_value(param_name, value)

    def _check_clock_loss(self) -> None:
        if (
            self._last_beat_time is not None
            and time.monotonic() - self._last_beat_time > 3.0
        ):
            self._bpm_label.setText("BPM: --")
            self._last_beat_time = None
