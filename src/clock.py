"""
Listens for MIDI clock ticks from the OP-1 Field and calculates live BPM.

MIDI clock standard: 24 Pulse-Per-Quarter-Note (PPQN).
  - One beat = 24 clock ticks.
  - BPM = 60 / (seconds per beat) = 60 / (24 × average_tick_interval_seconds).

Threading model:
  - A dedicated daemon thread reads the input port in a tight loop.
  - Shared state (tick count, BPM) is protected by a threading.Lock.
  - The caller supplies an optional beat_callback that fires on every beat
    (i.e. every 24th tick).  The callback executes on the clock thread, so
    it must be fast / non-blocking.
  - threading.Event is used to signal shutdown — no time.sleep() anywhere.
"""

import threading
import time
from collections import deque
from typing import Callable

import mido

PPQN = 24               # MIDI spec: 24 ticks per quarter note
SMOOTH_N = 24           # number of tick intervals to average for BPM smoothing
MIN_TICKS_FOR_BPM = 4   # need at least this many intervals before reporting BPM


class ClockListener:
    def __init__(
        self,
        in_port: mido.ports.BaseInput,
        beat_callback: Callable[[int], None] | None = None,
    ) -> None:
        """
        Args:
            in_port:        Shared mido input port (already open).
            beat_callback:  Called with the beat number (1-based) on every beat.
                            Runs on the clock thread — keep it fast.
        """
        self._port = in_port
        self._beat_callback = beat_callback

        self._lock = threading.Lock()
        self._stop_event = threading.Event()

        self._tick_count: int = 0          # total ticks received since start
        self._beat_count: int = 0          # total beats (tick_count // PPQN)
        self._bpm: float | None = None     # None until enough ticks accumulated

        # Ring buffer of the last SMOOTH_N tick-to-tick intervals (seconds)
        self._intervals: deque[float] = deque(maxlen=SMOOTH_N)
        self._last_tick_time: float | None = None

        self._thread = threading.Thread(target=self._run, daemon=True, name="ClockListener")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        self._thread.join(timeout=2.0)

    @property
    def tick_count(self) -> int:
        with self._lock:
            return self._tick_count

    @property
    def beat_count(self) -> int:
        with self._lock:
            return self._beat_count

    @property
    def bpm(self) -> float | None:
        """Current BPM, or None if not enough ticks have been received yet."""
        with self._lock:
            return self._bpm

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _run(self) -> None:
        # iter_pending() returns messages already in the buffer without
        # blocking, so we interleave it with stop_event checks.
        while not self._stop_event.is_set():
            for msg in self._port.iter_pending():
                if msg.type == "clock":
                    self._handle_tick()
                # ignore note-on/off, CC, sysex, etc. for now
            # Yield the GIL briefly rather than busy-spinning
            # (Event.wait with a short timeout replaces time.sleep)
            self._stop_event.wait(timeout=0.001)

    def _handle_tick(self) -> None:
        now = time.perf_counter()  # high-resolution monotonic timer

        with self._lock:
            self._tick_count += 1

            if self._last_tick_time is not None:
                interval = now - self._last_tick_time
                self._intervals.append(interval)

                if len(self._intervals) >= MIN_TICKS_FOR_BPM:
                    avg_interval = sum(self._intervals) / len(self._intervals)
                    # 24 ticks = 1 beat; avg_interval is seconds per tick
                    self._bpm = 60.0 / (PPQN * avg_interval)

            self._last_tick_time = now

            # Fire beat callback every PPQN ticks
            is_beat = self._tick_count % PPQN == 0
            if is_beat:
                self._beat_count += 1
                beat_num = self._beat_count  # capture before releasing lock
            else:
                beat_num = 0

        # Call outside the lock so the callback can safely read .bpm / .tick_count
        if is_beat and self._beat_callback:
            self._beat_callback(beat_num)
