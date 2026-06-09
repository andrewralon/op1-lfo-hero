# Startup Tempo Mode Detection Research

Goal: detect which of the OP-1 Field's 6 tempo modes is active at launch so the UI can set itself accordingly.

## Modes

| Mode | OP-1 role |
|---|---|
| FREE | Internal clock, no MIDI sync |
| MIDI Sync | Slave — follows incoming MIDI clock |
| Beat Match | Master — sends MIDI clock |
| PO Sync | Master — sends PO audio sync (and MIDI clock) |
| 1/16 | Master — sends 1/16 audio sync (and MIDI clock) |
| UNKNOWN | App default before detection resolves |

## Method

`ClockListener` captures all raw MIDI messages (including types normally ignored: `stop`, `continue`, `sysex`, `active_sensing`) for 5 seconds after launch. A Universal SysEx Identity Request (`F0 7E 7F 06 01 F7`) is sent to the OP-1 immediately after `clock.start()`. Results are printed to console 5.5 seconds after launch via `_print_startup_log()`.

## Results

### FREE
```
[startup] 4 total messages — counts by type: {'sysex': 4}
[startup] Non-clock messages:
  +0.002s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.023s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.060s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.102s  Message('sysex', data=(126, 127, 6, 1), time=0)
```
_(Earlier "no messages" result was from a cold/unresponsive OP-1, not a mode difference.)_

### MIDI Sync
```
[startup] 4 total messages — counts by type: {'sysex': 4}
[startup] Non-clock messages:
  +0.058s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.030s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.067s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.122s  Message('sysex', data=(126, 127, 6, 1), time=0)
```
_Identical to FREE — confirmed indistinguishable via MIDI._

### Beat Match (tape playing, ~78 BPM)
```
[startup] 160 total messages — counts by type: {'clock': 156, 'sysex': 4}
[startup] Clock jitter: mean=32.049ms  stddev=3.652ms  BPM≈78.0
[startup] Non-clock messages:
  +0.058s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.039s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.073s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.110s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

### PO Sync
```
[startup] 160 total messages — counts by type: {'sysex': 4, 'clock': 156}
[startup] Clock jitter: mean=31.738ms  stddev=4.027ms  BPM≈78.8
[startup] Non-clock messages:
  +0.002s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.021s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.061s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.104s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

### 1/16
```
[startup] 160 total messages — counts by type: {'sysex': 4, 'clock': 156}
[startup] Clock jitter: mean=31.838ms  stddev=3.670ms  BPM≈78.5
[startup] Non-clock messages:
  +0.055s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.026s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.065s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.118s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

## SysEx Decoding

**Identity Reply** (arrives ~0–60ms after our probe):
`F0 7E 02 06 02 00 20 76 02 01 02 00 00 00 00 F7`
- `7E 02 06 02` — Universal Non-Real Time, device ID 2, Identity Reply
- `00 20 76` — Teenage Engineering manufacturer ID
- `02 01 02 00` — device family / member codes
- `00 00 00 00` — firmware revision

**Periodic Identity Request** (~1 Hz, all modes):
`F0 7E 7F 06 01 F7` — the OP-1 broadcasts its own identity request at ~1 Hz regardless of mode. (Our probe echoed via MIDI thru would arrive once immediately, not repeatedly — so this is the OP-1 itself.)

## Findings So Far

| Mode | Clock ticks | SysEx |
|---|---|---|
| FREE | none | Identity Reply + periodic `06 01` (~1 Hz) |
| MIDI Sync | none | Identity Reply + periodic `06 01` (~1 Hz) — identical to FREE |
| Beat Match | yes (~24 PPQN) | Identity Reply + periodic `06 01` (~1 Hz) |
| PO Sync | yes (~24 PPQN, stddev=4.027ms) | Identity Reply + periodic `06 01` (~1 Hz) |
| 1/16 | yes (~24 PPQN, stddev=3.670ms) | Identity Reply + periodic `06 01` (~1 Hz) |

## Final Conclusions

**Two reliably distinguishable groups — nothing finer is possible via MIDI:**

| Signal | Modes | App behavior |
|---|---|---|
| Clock ticks received | Beat Match, PO Sync, 1/16 | OP-1 is clock master — app must not send clock, BPM display is read-only |
| No clock ticks, SysEx present | FREE, MIDI Sync | OP-1 is connected but silent — user must pick a mode manually |
| No messages at all | Device cold / unresponsive | OP-1 not ready |

**Jitter is not a viable discriminator:**

| Mode | stddev |
|---|---|
| Beat Match | 3.652ms |
| 1/16 | 3.670ms |
| PO Sync | 4.027ms |

All three are within 0.4ms — no threshold could distinguish them reliably across BPMs, cable quality, or system load.

**SysEx pattern is identical across all modes** — useful only for confirming the OP-1 is alive, not for identifying sync mode.

**FREE vs MIDI Sync are indistinguishable via MIDI.** No passive or active probe distinguishes them. User must select manually.

**Beat Match / PO Sync / 1/16 are indistinguishable via MIDI.** Functionally identical from the app's perspective: OP-1 is clock master, app follows.

## Remaining open question

Does the OP-1 only send clock ticks when the tape is actively rolling? One stopped-tape test showed nothing; rolling-tape tests showed ticks. If true, a Beat Match / PO Sync / 1/16 OP-1 with stopped tape would be misdetected as FREE/MIDI Sync until the user hits play.
