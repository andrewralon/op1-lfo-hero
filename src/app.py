"""
Entry point for the OP-1 MIDI Controller desktop app.

Run with:
    python -m src.app
    venv/bin/python -m src.app
"""

import sys

from PyQt6.QtWidgets import QApplication, QMessageBox

from src.midi_connection import connect
from src.clock import ClockListener
from src.controller import Controller
from src.ui import MainWindow, ClockBridge, apply_dark_theme


def main() -> None:
    app = QApplication(sys.argv)
    apply_dark_theme(app)

    try:
        in_port, out_port = connect()
    except Exception as exc:
        QMessageBox.critical(None, "MIDI Connection Failed", str(exc))
        sys.exit(1)

    port_name = in_port.name

    controller = Controller(out_port)
    bridge = ClockBridge()

    def on_beat(beat_num: int) -> None:
        # Runs on the clock daemon thread — only emit signals here.
        bridge.beat.emit(beat_num)

    clock = ClockListener(in_port, beat_callback=on_beat)
    clock.start()

    window = MainWindow(controller, clock, bridge, port_name)
    window.show()

    def on_quit() -> None:
        clock.stop()
        in_port.close()
        out_port.close()

    app.aboutToQuit.connect(on_quit)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
