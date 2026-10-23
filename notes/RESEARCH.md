# Startup Tempo Mode Detection Research

Goal: detect which of the OP-1 Field's 6 tempo modes is active at launch so the UI can set itself accordingly.

## Tempo Modes

| Mode | OP-1 role |
|---|---|
| FREE | Internal clock, no MIDI sync |
| MIDI SYNC | Slave — follows incoming MIDI clock |
| BEAT MATCH | Master — sends MIDI clock |
| PO SYNC | Master — sends PO audio sync (and MIDI clock) |
| 1/16 SYNC | Master — sends 1/16 audio sync (and MIDI clock) |
| UNKNOWN | App default before detection resolves |

## Method

`ClockListener` captures all raw MIDI messages (including types normally ignored: `stop`, `continue`, `sysex`, `active_sensing`) for 5 seconds after launch. A Universal SysEx Identity Request (`F0 7E 7F 06 01 F7`) is sent to the OP-1 immediately after `clock.start()`. Results are printed to console 5.5 seconds after launch via `_print_startup_log()`.

## Results by Tempo Mode

### FREE
```
[startup] 4 total messages — counts by type: {'sysex': 4}
[startup] Non-clock messages:
  +0.002s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.023s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.060s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.102s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

### MIDI SYNC
```
[startup] 4 total messages — counts by type: {'sysex': 4}
[startup] Non-clock messages:
  +0.058s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.030s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.067s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.122s  Message('sysex', data=(126, 127, 6, 1), time=0)
```
_Identical to FREE — confirmed indistinguishable via MIDI._

### BEAT MATCH
```
[startup] 160 total messages — counts by type: {'clock': 156, 'sysex': 4}
[startup] Clock jitter: mean=32.049ms  stddev=3.652ms  BPM≈78.0
[startup] Non-clock messages:
  +0.058s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.039s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.073s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.110s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

BEAT MATCH take 2:
```
[startup] 160 total messages — counts by type: {'sysex': 4, 'clock': 156}
[startup] Clock jitter: mean=31.871ms  stddev=3.400ms  BPM≈78.4
[startup] Non-clock messages:
  +0.059s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.047s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.101s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.132s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

### PO SYNC
```
[startup] 160 total messages — counts by type: {'sysex': 4, 'clock': 156}
[startup] Clock jitter: mean=31.738ms  stddev=4.027ms  BPM≈78.8
[startup] Non-clock messages:
  +0.002s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.021s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.061s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.104s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

PO SYNC take 2:
```
[startup] 160 total messages — counts by type: {'sysex': 4, 'clock': 156}
[startup] Clock jitter: mean=31.808ms  stddev=3.652ms  BPM≈78.6
[startup] Non-clock messages:
  +0.059s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.043s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.085s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.127s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

### 1/16 SYNC
```
[startup] 160 total messages — counts by type: {'sysex': 4, 'clock': 156}
[startup] Clock jitter: mean=31.838ms  stddev=3.670ms  BPM≈78.5
[startup] Non-clock messages:
  +0.055s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.026s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.065s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.118s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

1/16 SYNC take 2:
```
[startup] 160 total messages — counts by type: {'sysex': 4, 'clock': 156}
[startup] Clock jitter: mean=31.861ms  stddev=3.130ms  BPM≈78.5
[startup] Non-clock messages:
  +0.058s  Message('sysex', data=(126, 2, 6, 2, 0, 32, 118, 2, 1, 2, 0, 0, 0, 0, 0), time=0)
  +1.055s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +2.088s  Message('sysex', data=(126, 127, 6, 1), time=0)
  +3.130s  Message('sysex', data=(126, 127, 6, 1), time=0)
```

## SysEx Decoding

**Identity Reply** (arrives ~0-60ms after our probe):
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
| PO Sync | yes (~24 PPQN, stddev 3.652-4.027ms) | Identity Reply + periodic `06 01` (~1 Hz) |
| 1/16 | yes (~24 PPQN, stddev 3.130-3.670ms) | Identity Reply + periodic `06 01` (~1 Hz) |

## Final Conclusions

**Two reliably distinguishable groups — nothing finer is possible via MIDI:**

| Signal | Modes | App behavior |
|---|---|---|
| Clock ticks received | Beat Match, PO Sync, 1/16 | OP-1 is clock master — app must not send clock, BPM display is read-only |
| No clock ticks, SysEx present | FREE, MIDI Sync | OP-1 is connected but silent — user must pick a mode manually |
| No messages at all | Device cold / unresponsive | OP-1 not ready |

**Jitter is not a viable discriminator:**

| Mode | Take 1 stddev | Take 2 stddev | Range |
|---|---|---|---|
| Beat Match | 3.652ms | 3.400ms | 0.252ms |
| PO Sync | 4.027ms | 3.652ms | 0.375ms |
| 1/16 | 3.670ms | 3.130ms | 0.540ms |

All three ranges overlap completely (1/16 take 2 is the lowest reading overall at 3.130ms; PO Sync take 1 is the highest at 4.027ms). Within-mode variance is as large as between-mode variance. No threshold survives this overlap.

**SysEx pattern is identical across all modes** — useful only for confirming the OP-1 is alive, not for identifying sync mode.

**FREE vs MIDI Sync are indistinguishable via MIDI.** No passive or active probe distinguishes them. User must select manually.

**Beat Match / PO Sync / 1/16 are indistinguishable via MIDI.** Functionally identical from the app's perspective: OP-1 is clock master, app follows.

## Beat Match: Start and Stop are real transport presses (corrected 2026-10-16)

An earlier version of this section claimed the OP-1 sends Start and Stop at bar boundaries as
position beacons, even with the tape stopped, so a real press could not be told apart. **That does
not hold** on the OP-1 Field over USB in beat match, measured from a Mac with `tools/midi/anymidi`
(5 s windows, a 1 s drain window first — see the backlog note below):

| What was done | Clock | Start `0xFA` | Stop `0xFC` |
|---|---|---|---|
| nothing, tape stopped | 221 | 0 | 0 |
| nothing, tape rolling the whole window (90 BPM) | 180 | 0 | 0 |
| press **play** on the OP-1 | 221 | **1** | 0 |
| press **stop** on the OP-1 | 181 | 0 | **1** |

So a play press is one Start and a stop press is one Stop, and nothing else produces them. The
app uses the Start to restart every active LFO from the beginning of its cycle
(`ClockEngine.onPlay` -> `AutomationEngine.restartAll`). The windows are short (about 2 bars), so
a rarer periodic beacon is not strictly excluded.

**Measurement trap — USB backlog.** A listener that connects after a gap is first handed the
clock the driver queued while nothing was listening: about 22 s of ticks after a 22 s gap, 44 s
after a 44 s gap (970 and 1930 extra ticks), plus any Start/Stop from that gap. It is not live
traffic, and a running app never sees it. Run a 1 s throwaway window first and count the next one.

## Resolved: tape state does not affect clock output

Beat Match with tape stopped:
```
[startup] 160 total messages — counts by type: {'sysex': 4, 'clock': 156}
[startup] Clock jitter: mean=31.792ms  stddev=3.836ms  BPM≈78.6
```

156 clock ticks received with tape fully stopped, and again with tape playing — identical counts and jitter in both cases. The OP-1 sends MIDI clock continuously in Beat Match mode regardless of tape state. The earlier zero-result was from a cold/unresponsive device, not from the tape being stopped. By extension, PO Sync and 1/16 (which showed the same tick counts in all tests) are expected to behave the same way.

---

# Multi-device MIDI mapping (op-1 field / tx-6 / tp-7)

## At a glance — where the published references are wrong

Everything below was measured on real hardware. The pattern: the guides are accurate about
*single CC -> single value*, and wrong or silent about *state, modes and timing*.

| Device | The reference says | Actually |
|---|---|---|
| TP-7 | nothing about MIDI clock | **sends it** continuously in `sync` mode |
| TP-7 | nothing about the four midi modes | they gate everything; `ctrl` blocks all input |
| TP-7 | `CC 18` = "fast forward/rewind, -64..+63" | persistent bipolar speed state that must engage first |
| TP-7 | nothing about real-time transport | 0xFA/0xFB/0xFC drive the tape |
| TP-7 | `CC 9` = "input gain, channels 1-3" | the three **input jacks**, upstream of the mix channels |
| TP-7 | button table omits one | there is a `mode` button on **CC 28** |
| TX-6 | nothing about needing setup | ignores everything until `midi control = in` |
| TX-6 | one CC table | transmit and receive are **different maps that collide** |

Four bugs in this app came from trusting the references; all are fixed and covered by tests.

**Second opinion:** [TP7_VS_TP7MIDI.md](TP7_VS_TP7MIDI.md) cross-references every TP-7 finding
here against [lucidyan/tp7-midi](https://github.com/lucidyan/tp7-midi), an independently measured
third-party spec. Most of it agrees. Where it does not, two of the disagreements are ones our own
numbers lose — see the ⚠️ notes on the CC 18 dead zone and the `+708` stop point below, and the
hardware test plan in that file. Treat those two as open until they have been re-run.


Sources: OP-1 tables in `README.md`; [tp-7](https://teenage.engineering/guides/tp-7#midi-reference)
and [tx-6](https://teenage.engineering/guides/tx-6#midi-reference) MIDI references.

These tables are the spec that `ios/Sources/Engine/DeviceProfiles.swift` encodes, and they are
independently re-asserted in `ios/Tests/` (`OP1ProfileMatchesSpecTests`, `TX6ProfileTests`,
`TP7ProfileTests`) so a typo in the profile can't hide behind a test that reads the same table.

## Display scale is app-wide, not per device

Every device shows **0-99** in the UI while MIDI carries **0-127**. This is the OP-1's on-screen
scale and it is deliberately applied to all devices for consistency:

```
midiToUI(v) = floor(v * 99 / 127)
uiToMidi(u) = (u * 127 + 98) / 99      // ceiling inverse — every UI value round-trips exactly
```

`DeviceProfile` intentionally has **no** per-device scale field, so the two can never diverge.

## Channel model

| Device | tracks | track channels (0-based) | master | other |
|---|---|---|---|---|
| op-1 field | 4 | 0-3 | ch 0 (separate CC bank) | — |
| tx-6 | 6 | 0-5 | ch 6 | fx I = ch 7, fx II = ch 8 |
| tp-7 | 6 | 0-5 | ch 0 | — |

The TX-6's FX buses have no track of their own, so they are exposed as **master-only**
parameters under the (m) target — hence `ParamSpec` carrying separate `track` and `master`
bindings, and `ChannelRule.pinned` for an absolute channel.

## op-1 field

Per track (ch = track − 1): volume `7`, mute `9` (127/0), pan `10`, par 1-4 `46-49`,
env A/D/S/R `50-53`, fx 1-4 `54-57`, lfo 1-4 `58-61`.
Master (always ch 0): master fx 1-4 `70-73`, master compressor 1-4 `74-77`
(the master "lfo" parameter is intentionally overloaded onto the compressor).
Transport: `0xFA`/`0xFB` start/continue, `0xFC` stop, tape prev/next `82`/`83` + SPP `0xF2`.

## tx-6

Per channel (ch 0-5): volume `7`, pan `8`, gain `9`, seq pattern `14`, filter `74`,
eq high `85`, eq mid `86`, eq low `87`, comp `93`, syn wave `3`, syn freq `89`, syn len `90`,
syn detune `95`, fx1 send `91`, aux send `92`, aux2 send `94`, mute/solo `120`.
Master (ch 6): main vol `7`, aux vol `14`, cue vol `15`, local control `122`,
start/stop toggle `46`, tempo relative `47`.
FX I (ch 7) / FX II (ch 8): enable `82`, engine `15`, param 1-3 `12`/`13`/`14`,
fx I return `7` (ch 7), fx II track select `9` (ch 8).
On/off encoding: 0-63 = off, 64-127 = on.

**CC 47 is deliberately not an automatable parameter.** It is a relative encoder, so an LFO on
it would drift the tempo in one direction forever instead of oscillating. It is reachable only
from the −/+ transport buttons.

**Relative encoders are two's complement, not centred on 64.** `1...63` count up, `127...65`
count down (`127` = -1). The app originally sent `64 + delta`, so `+` transmitted 65 (read as
**-63**) and `-` transmitted 63 (read as **+63**): each press moved the tempo hugely in the wrong
direction, reported from hardware as "+ halves the bpm and - doubles it". Confirmed independently
by the TP-7's wheel, which sends `1,2,3` clockwise and `125,126,127` counter-clockwise.

Note this is the opposite convention to `CC 18` on the TP-7, which *is* centred on 64. Both
appear on the same manufacturer's devices, so neither can be assumed.

**CC 120 is standard MIDI "all sound off".** TE reuses it per channel for mute. Sending it will
also silence unrelated gear sharing a hub.

## tp-7

**Firmware: 1.1.11** — every TP-7 measurement in this file was taken on this version, including
the [tp7-midi cross-reference](TP7_VS_TP7MIDI.md), whose author independently documents the same
1.1.11. No disagreement between the two projects is a firmware artifact.

Per channel (ch 0-5): mix volume `7`, mix mute `120`, input gain `9` (**channels 1-3 only** —
4-6 are playback, not inputs).
Global (ch 0): record `14`, cue rec `16`, loop `17` (0=off, 1=in, 2=out), ff/rewind `18` (relative).
Notes = cue markers; pitch bend = playback speed (not yet used by the app).
Outgoing in controller mode (ch 0): up `20`, down `21`, rec `22`, play `23`, stop `24`,
left `25`, right `26`, memo `27`, wheel `30` (relative), rocker = pitch bend.

## Device detection

CoreMIDI endpoint names, read off a Mac's MIDI database with all three devices paired:

| Device | `kMIDIPropertyName` / model | manufacturer |
|---|---|---|
| OP-1 Field | `OP-1` | `teenage engineering` |
| TP-7 | `TP-7` | `teenage engineering` |
| TX-6 | `TX-6` | `teenage engineering` |

Matching is a lowercase substring test against the endpoint display name
(`op-1`/`op1`, `tx-6`/`tx6`, `tp-7`/`tp7`). Manufacturer and model are also exposed by CoreMIDI
and would be a sturdier signal for hubs that rename ports — not used yet.

Each device appears **twice** in the device list (one USB entry, one BLE entry).

## Hardware findings — TX-6 over USB MIDI

Measured by passively monitoring a real TX-6's CoreMIDI source (~12 minutes total across three
sessions, including one 10-minute session of heavy hands-on use). Nothing was transmitted to
the device.

### The transmit map and the receive map are different namespaces that collide

This is the important one. In controller mode the TX-6 sends its **own** map, all on MIDI
channel 1, which is *not* the map it listens on. Five CCs mean different things in each
direction:

| CC | transmitted (controller mode) | received (mixer control) |
|---|---|---|
| 3 | fader 3 | syn wave |
| **7** | **upper knob 1** | **volume** |
| **8** | **upper knob 2** | **pan** |
| **9** | **upper knob 3** | **gain** |
| 14 | middle knob 2 | seq pattern |

So feeding the TX-6's output back through the receive table makes turning upper knob 1 look
like "track 1 volume changed". Confirmed: upper knob 1 was observed transmitting CC 7 on ch 1.
Meanwhile the faders transmit CC 1-6, which the receive table does not use at all — so the one
thing you would actually want to mirror is invisible, and the things you would not want to
mirror are misread.

Handled by `DeviceCapabilities.mirrorsIncomingCC` (false for the TX-6): incoming CC is ignored
for UI mirroring rather than misinterpreted. The OP-1 was once assumed to echo its
mixer on the CCs it accepts; that was wrong — see "Hardware findings — OP-1 Field transmit
behavior" below.

### Confirmed transmitting

`cc1` fader 1 (range 0-127) · `cc18` middle knob 6 · `cc24` lower knob 6 ·
`cc25-30` all six track buttons · `cc31` encoder turn · `cc32` encoder button ·
`cc33` fx I · `cc34` fx II · `cc35` shift — every one matching the documented outgoing table.
Faders **do** transmit; an earlier session that saw none simply had no fader movement.

### The TX-6's play button does not tell the app anything (2026-10-17)

Passive probe from a Mac (`tools/midi/anymidi` and a timestamped dump), the TX-6's **encoder button**
used as its play/pause toggle, three attempts at each `midi control` setting:

- **`midi control = in`** (the setting the app needs to control the TX-6): **silent.** No message of any
  kind for the presses, in two separate 12 s windows.
- **`midi control = out`:** each press sends **`B0 20 7F` then `B0 20 00`** (CC 32, channel 1, value 127
  then 0, about 0.2 s apart). **The same two messages for play and for pause**: a press, with no
  state. No Start (`0xFA`), Continue (`0xFB`) or Stop (`0xFC`) at all.

The TX-6's `midi control` has exactly **three settings: `x` (off), `in` and `out`**, so no setting lets
it take control from the app and report its own controls back at the same time.

So a play press on the TX-6 itself cannot restart the LFOs the way the OP-1's does:
`ClockEngine` listens for Start and Continue, which the TX-6 never sends; in `out` the only trace is a
stateless CC 32 that cannot tell play from pause; and `out` makes the TX-6 ignore everything the
app sends, so it cannot be used together with the app controlling the TX-6. A play press **in the
app** restarts the LFOs as designed (verified on an iPad with a TX-6 on USB-C). Not tested: the
TX-6's **sequencer** play, which may send something different; no good way to exercise it was
available. This also answers the open question below about starting the transport from the panel:
the app cannot know it happened.

### MIDI clock

**It does send clock — but only when configured to.** With `clock SRC` set to internal and clock
`out` enabled, the TX-6 streams 24 PPQN steadily: **32.00 ticks/s measured over 20 s against a
device display reading 80 BPM**, which is exact (32 / 24 x 60 = 80.0).

An earlier capture here recorded **zero `0xF8` in ~12 minutes**, including 10 minutes of hands-on
use, and concluded the TX-6 does not send clock — which set `canBeClockMaster: false` and
disabled the app's metronome toggle for this device. That capture was in the **default**
configuration, with clock out off. The caveat noted at the time (that the test conditions might
not have been right) turned out to be the whole story.

Worth generalising: *"it sent nothing while I watched"* is not the same as *"it cannot send"*.
The same mistake was made on the TP-7, also marked `canBeClockMaster: false` before it was found
to stream clock in `sync` mode. Both are now `true`, and both are off by default — so the app
remains the tempo source unless the user switches deliberately.

Consequence for the app: with the TX-6 as clock source, its −/+ tempo nudges move both displays
together. While the app is master the two tempos are independent and drift apart, which is what
the nudge buttons appear to do from the app's side.

### Two device settings are required before any of this works

A TX-6 straight out of its default state ignores the app completely. Both of these are on the
device, not in the app, and a user who does not know about them will conclude the app is broken:

| TX-6 setting | Set to | Without it |
|---|---|---|
| `midi control` | **in** | the device ignores every CC the app sends |
| `clock SRC` | **usb** | the device will not follow the app's tempo |

#### `midi control` modes — full behaviour, tested on hardware

The setting is a three-way switch and only one of its positions works with this app. Each was
tested with the same 21-second volume sweep on `CC 7` ch 1:

| Mode | Receives CC from the app? | Transmits its own controls? |
|---|---|---|
| **in** | **yes** — channel 1 swept audibly | no — silent across 95 s of capture |
| **out** | no — no change at all | yes (documented; its control-surface map) |
| **X** | no — no change at all | no |

So the modes are mutually exclusive, not additive: the TX-6 is either a controller *or* a
controlled device, never both. This is why the transmit/receive CC collision documented above
cannot occur while the app is actually driving the device — in `in` mode there is nothing
coming back to misread.

#### Moving a physical fader while the app is sending

Tested in `in` mode: moving fader 1 during an incoming `CC 7` sweep made the channel audibly
**fight** — the fader's own value and the app's values alternated. Both write the same target
and the last writer wins, so there is no handover or takeover behaviour to rely on.

Practical consequence: an LFO on a channel's volume sends a value roughly 40 times a second, so
grabbing that fader mid-performance produces stuttering rather than control. Pause the chip for
that channel first. Worth surfacing in help.

It also means **the app can never mirror the TX-6's physical fader positions**. Doing so would
require `out` mode, which simultaneously stops the device accepting anything the app sends.
Worth stating plainly rather than leaving as a "why doesn't the UI follow my hardware?" mystery.

### Verified by sending to the device

- **`midi control` must be set to `in` on the TX-6.** Until that is set the device ignores
  everything — a full volume sweep produced no response at all. This is a setup step a user
  will otherwise experience as "the app is broken"; it belongs in the help text.
- **It acts on incoming CC.** With `in` set, `CC 7` on ch 1 swept channel 1's volume audibly.
  Channel mapping (ch 1 = track 1) and CC number both confirmed correct.
- **`CC 120` is absolute, not a toggle, and 127 = muted.** Sending 127 muted channel 1 and 0
  unmuted it. The profile's `SwitchEncoding` default (on 127 / off 0 / threshold 64) is right,
  and `inverted` is correctly left false. This mattered: had it been a toggle, an LFO on mute
  would flip state on every clock tick (~40 Hz) and stutter the channel rather than gate it.
- **It follows incoming MIDI clock** (requires `clock SRC = USB` on the device). Sending `0xFA`
  plus 24 PPQN measured at 101.7 BPM moved the TX-6 from 68 BPM to a settled **101 BPM** — a
  match within 1%. It slewed rather than jumping, and the 100-106 wobble during the run was the
  test script's sleep-based timing, not the device.
  So `followsClock: true` is verified, and the pairing is: the app is always clock master
  (the TX-6 never sends clock) and the TX-6 locks to it.
- **The pinned FX-bus channels work.** `CC 82 = 127` on ch 8 switched FX I on, and 0 switched it
  off. Channel 8 is outside the 1-6 track range and is reachable only via `ChannelRule.pinned`,
  so this validates that mechanism end to end.
- **FX I enable is global, not per channel.** Confirmed on hardware: enabling the bus affects the
  whole FX unit, while how much each channel feeds it is the separate per-channel send (`CC 91`,
  ch 1-6). This is exactly the split the profile encodes — `tx6.fx1.en` is master-only and
  `tx6.fx1Send` is per-track — so folding the FX buses into the master (m) slot is correct.
- **Transmit and receive are mutually exclusive modes.** In `in` mode the TX-6 sent nothing at
  all across two captures totalling 95 s, despite flooding earlier captures with control-surface
  CCs in its default mode. So the transmit/receive collision documented above cannot occur while
  the app is actually driving the device — `mirrorsIncomingCC: false` remains correct as a guard
  for the case where a user leaves it in controller mode.

## Hardware findings — TP-7 over USB MIDI

Endpoint name `TP-7`, manufacturer `teenage engineering`; exposes both a source and a destination.

### The four `midi` modes

Unlike the TX-6, the TP-7 accepts CC in most modes — there is no "you must enable input" step.
Measured with the same 21-second `CC 7` ch 1 volume sweep:

All four modes tested with the same 21-second `CC 7` ch 1 volume sweep, monitoring
simultaneously:

| Mode | Receives CC from the app? | Transmits | Tape playback |
|---|---|---|---|
| `off` | **yes** | nothing | plays |
| `sync` | **yes** | **MIDI clock**, continuously (~110 BPM measured) | plays |
| `ctrl` | **no** | its own button map (CC 20-27, wheel 30) | **stops** |
| `cue` | **yes** | nothing observed | plays |

Three of the four modes accept CC. Only `ctrl` — controller mode — does not. So unlike the
TX-6, the TP-7 needs **no setup at all** for the app to control it; the only thing a user must
avoid is `ctrl`.

The modes gate what the TP-7 *does*, not a blanket MIDI enable:
`sync` adds clock output, `ctrl` swaps it into being a controller for other gear, `cue` relates
to cue markers, `off` is plain. CC reception rides along in everything except `ctrl`.

`ctrl` is *controller mode*: the TP-7 becomes a MIDI controller for other gear. It stops tape
playback, shows only "CTRL" on the display, and stops accepting incoming MIDI. TE's docs
confirm the exclusivity: *"TP-7 only sends button events (CC 20-27) in Controller Mode, which is
mutually exclusive with receiving MIDI commands."*

So the app should be used in `off` or `sync`, never `ctrl`.

### It sends MIDI clock — contradicting the published reference

**1769 clock ticks in 40 s (~110 BPM), streaming continuously**, while in `sync` mode. The
published TP-7 MIDI reference documents no clock output at all; this was found only by
listening. `canBeClockMaster` is therefore **true** for the TP-7 — the app can slave to it, the
same "beat match" relationship the OP-1 has. (Contrast the TX-6, which genuinely never sends
clock across ~12 minutes of monitoring.)

### MAJOR CORRECTION (2026-09-07): the outgoing clock rate is a TEMPO readout, not a TAPE-SPEED
### readout. "44 ticks/s = 1x" was never a device constant — it was one memo's tempo setting.

Every measurement on this page that expresses CC 18 / bend behaviour as an "x" multiplier
(the whole affine model, the `deadZone` finding, the bend curve, all of it) was calibrated
against **44 ticks/s** as if it were a fixed, universal property of the device — "1x playback
speed." **That was wrong.** MIDI clock counts *beats* (24 pulses per quarter note), not tape
motor revolutions, and the tick rate the TP-7 transmits during ordinary unmodified playback
tracks **the current tempo setting**, which is a property of what's loaded, not a hardware
constant. Normal playback of any recording advances real-world time 1:1 regardless of its
tempo — a 120 BPM memo and a 60 BPM memo both play at ordinary speed, they just tick at
different rates, because MIDI clock is measuring music, not motor RPM.

**Confirmed with three separate memos, blind, on 2026-09-07:**

| memo | clock measured | tempo/setting | match |
|---|---|---|---|
| memo A (106 BPM tag, per its own metadata, checked *after* measuring) | 42.41 ticks/s → **106.0 BPM** | 106 BPM | exact |
| memo B (metronome set to 120 BPM while recording) | 48.01 ticks/s → **120.0 BPM** | 120 BPM | exact |
| memo C (metronome turned **off** while recording) | 48.01 ticks/s → **120.0 BPM** | (see below) | matches memo B |

Memos A and B were genuinely blind predictions — the tick rate was computed and stated *before*
the actual tempo was revealed, twice, and matched to within 0.03 BPM both times. That is not
plausibly a coincidence at that precision.

**Memo C, resolved.** Turning the metronome off during recording did **not** silence the clock or
reset it to some default — it kept transmitting at exactly memo B's rate (120 BPM). Two
explanations fit that result equally well on their own:

1. **Per-file, sticky at record time** — memo C silently inherited the device's tempo setting at
   the moment it was recorded (metronome *audibility* and tempo *assignment* being separate
   switches), so it now has that value baked in permanently, same as any other memo.
2. **A single global "current tempo"** — not tied to any file at all. The device has one current
   tempo value (adjustable, drives the metronome and tempo-based navigation), and outgoing clock
   always reflects *whatever that dial currently reads* regardless of which file is loaded.

**Distinguishing test, run 2026-09-07: changed the device's current tempo setting to 90 BPM (via
the recording menu's tempo setting), recorded nothing new, and re-measured memo C.** Result:
**47.985 ticks/s — still exactly 120 BPM, unchanged.** Setting the device to 90 BPM had zero
effect on this already-recorded memo. **Explanation 1 confirmed: tempo is genuine per-file
metadata**, fixed at (or shortly after) record time, independent of whatever the device's
current tempo dial shows afterward. The device's "current tempo" setting and a given recording's
own stored tempo are separate, non-interacting values.

**Suspected — not yet confirmed — this applies uniformly across memo, recordings, and library
modes.** The original "library plays back faster than recordings" finding from earlier in this
session (~51.2 ticks/s / ~128 BPM in library vs ~42.4 ticks/s / ~106 BPM in recordings/memo) is
now suspected to have been **the same tempo-readout mechanism, not a mode difference at all** —
the library file and the memo simply happened to carry different tempo values. If that holds,
"library vs. recordings" was a red herring riding on top of the real variable (whatever tempo is
associated with the current file), and the mode itself has no independent effect on clock rate.
Not yet directly tested — would need the same tempo measured on the same piece of content in two
different modes to confirm the mode genuinely has no effect.

**Impact on prior findings, assessed per-test:**
- **Test 9 (CC 18 extremes, x99-x278.9) — unaffected.** Those numbers came from the physical
  position counter (real minutes:seconds elapsed), not clock ticks, precisely because the clock
  is blind during CC-18-driven motion from a parked tape. A tempo-independent, genuine physical
  playback-speed measurement.
- **Tests 1, 2, 3 (deadZone, the +708 null, the engage/additive question) — unaffected or
  effectively so.** Test 1's verdict came from the position counter, not ticks. Tests 2 and 3's
  verdicts are qualitative within-run comparisons (near-zero vs. not; returns-to-baseline vs.
  not) that don't hinge on knowing the exact reference value.
- **Test 4 (bend curve) — exact reported numbers carry a small systematic bias.** They were
  computed against the hardcoded 44.0 rather than that session's actual memo tempo (~42.4,
  about 3.6% off). The conclusions (velocity model over multiplier model; ours closer than
  theirs on the negative branch) almost certainly still hold, but the specific x-values quoted
  (x0.48, x1.93, etc.) should be read as approximate, not precise.
- **Test 10 (`followsClock`) — gets a better explanation, not a retraction.** It now makes much
  more sense *why* streaming external clock at the device never changed its outgoing rate: that
  rate is a static readout of the loaded content's tempo setting, not a live motor-speed
  parameter driven by incoming pulses. There was never a mechanism by which external clock
  could have changed it.
- **`tools/midi/cc18map.swift`'s hardcoded `44.0` reference** throughout (`measure()`'s x-value,
  the `stopped` mode's absolute verdict thresholds) should ideally become a freshly-measured
  per-session baseline rather than a historical constant, for any future test that reports an
  absolute multiplier. Not yet changed — noted here so it isn't forgotten.

Neither `lucidyan/tp7-midi` nor the TE manual say anything about tempo/BPM in connection with the
outgoing clock at all (checked `MIDI_SPEC.md`, `app.js`, the manual, the changelog — zero hits).
This entire mechanism is new to both projects.

### SPD varispeed × pitch bend: multiplicative, and the bend curve is a portable device constant

**CONFIRMED 2026-09-07.** With the tempo-readout mechanism established above, one prediction
follows immediately: any genuine physical speed change (bend, CC 18, or the physical `SPD`
varispeed control) should scale the tick rate multiplicatively relative to *whatever the current
baseline already is* — because `ticks/s = (native tempo) × (physical speed multiplier)`
regardless of what's driving that multiplier. This was tested directly.

Fresh baseline on the loaded memo, no SPD, no bend: **R0 = 48.022 ticks/s** (≈120.06 BPM, matches
this memo's own tempo). Engaged `SPD` to a non-1x position on the physical gauge ("a little right
of centre" — the gauge has no numeric readout, just a dial either side of a centre mark) — no
bend yet: **R_spd = 57.891 ticks/s**, i.e. **x1.2055** relative to R0.

With SPD still engaged at that same position, ran the same five-point bend sweep as the earlier
bend curve test, and normalized against R_spd (not the historical 44.0):

| bend | raw ticks/s | normalized to R_spd | earlier bend curve (different memo, tempo, no SPD) |
|---|---|---|---|
| full negative | 28.98 | **x0.501** | x0.48 |
| -4096 | 39.74 | **x0.687** | x0.66 |
| centre | 57.85 | **x0.999** | x0.96 |
| +4096 | 83.20 | **x1.437** | x1.39 |
| full positive | 115.68 | **x1.998** | x1.93 |

**These match almost exactly** — a different memo, a different native tempo, and a physical SPD
control actively engaged, and the normalized bend curve still lands within a few percent of the
original measurement taken under none of those conditions. That is not plausible as coincidence.

**Conclusion: SPD and bend compose multiplicatively** — `total speed = SPD × bend_curve(value)`
— and **the bend curve itself, expressed in x-units relative to whatever the current baseline is,
is a portable, fixed property of the device.** It is not tied to a specific file's tempo, and not
tied to whatever the SPD control happens to be doing. It is still clearly *our* curve shape, not
`lucidyan/tp7-midi`'s — full negative sits at x0.50, nowhere near their formula's x0.25.

**The `SPD` display was confirmed to never move**, even while bend swept the actual audible
speed from roughly half to double normal and into reverse (via `CC 18 = 56` engaged alongside
it) — the gauge stayed exactly where it was set, the entire time. This extends the earlier
"bend leaves `SPD` unchanged" finding (measured with SPD at rest) to also hold with SPD actively
engaged and under simultaneous CC 18 / direction changes.

**This resolves the `cc18map.swift` hardcoded-`44.0` concern properly, not just as a workaround.**
The fix was never "measure a fresh baseline every session and use that instead" — it's that **the
bend curve in x-units is a device constant**, so normalizing against *any* correctly-measured
local baseline (whatever tempo, whatever SPD setting) reproduces the same portable curve. The
44.0 constant was simply the wrong denominator for absolute ticks/s claims; the underlying x-unit
relationship it was trying to express was right all along.

### It never reports its state

Per TE's docs: *"TP-7 never reports its state via MIDI. You cannot query transport, loop, or
cue states."* So `mirrorsIncomingCC` is false — there is nothing to mirror, and in `ctrl` mode
what it does send is a different map entirely.

### TP-7 playback direction and speed — CC 18, verified on hardware

`CC 18` is not "fast forward/rewind" as the official reference calls it, and not a relative
nudge. It is a **persistent bipolar speed control that must first take over the transport**.
The following was established by probing a real TP-7 in `sync` mode with a file playing.

**RETIRED (2026-09-06, confirmed on hardware): there is no engage/release state machine.** The
four points below were the original framing and are kept for the method notes, but `cc18map TP-7
engage` settled it directly: with the tape playing forward (baseline ~44 ticks/s), sending
`CC 18 = 64` three times, then `70`, then `64` again produced 42.5 → 42.3 → 102.1 → 42.4 — a clean
return to baseline both times `64` was sent, with no stop and no re-engage transition in between.
`64` simply **adds zero velocity**; it never was a special "disengage" state. The simpler additive
model (below) explains every observation on this page without needing "engage" at all.

**The original engage/release framing, superseded above but kept for context:**

1. While the tape is rolling under its own transport, `CC 18 = 64` does **nothing** — CC 18 has
   not taken control yet. (Verified: sent three times, no effect.)
2. Sending any value **other than 64** takes control of the transport.
3. Once engaged, `64` **removes the CC 18 offset**, leaving whatever the transport itself is
   doing. (This was originally recorded as "zero speed, the tape stops" — true only when the
   transport is parked. With the transport rolling, `64` hands motion back to it rather than
   stopping it. See *CC 18 is additive* below.)
4. `0xFC` (MIDI stop) does **not** release that control — a tape seeking under CC 18 keeps
   going. (Verified.)

So stopping a CC 18-driven tape needs **`CC 18 = 64` *and* `0xFC`**: the CC zeroes the speed,
the real-time message stops the transport.

**Stopping holds position — it does not rewind.** Verified: after `CC 18 = 64` the tape stayed
where it was. That is the desired behaviour for a first stop press, and it means returning to
zero has to be an explicit separate action (the double-stop gesture), not a side effect of stop.

**First-pass speed scale, by ear**, all while engaged:

| value | observed |
|---|---|
| 56 | reverse, fast |
| 60 | reverse, ≈normal speed |
| 61 | reverse, slower than normal |
| 62 | reverse, crawling |
| **64** | **stopped** (once engaged) |
| 72 | forward, clearly faster than normal ("chipmunks") |

Distance from 64 is speed; side of 64 is direction. Reverse playback is reachable only this way.

⚠️ **The "60 ≈ normal speed" row is wrong** — later measurement puts 60 at **x0.33**. Judging a
reverse rate by ear without a simultaneous forward reference is unreliable, and this row sent the
implementation down a wrong path for several iterations. See *TP-7 speed measured numerically*
below, which supersedes this table.

**RETRACTED (2026-09-06, confirmed on hardware) — this was our error, not theirs.**
[lucidyan/tp7-midi](https://github.com/lucidyan/tp7-midi) states the stop point "shifts between
60-61" during playback, with a workaround of `CC 18 = 60` plus pitch bend `+708`. An earlier round
of this document called that wrong, on the theory that 60 and 61 are simply slow *reverse* speeds
and the stop point stays at 64. **That correction was itself wrong.** Once CC 18 was measured to
be *additive* (below), their claim falls out of our own model — and hardware confirms it directly:

- `CC 18 = 61`, playing forward: measured **8.6 ticks/s (x0.20), forward** — matches the additive
  prediction of ~8.9
- `CC 18 = 60`: measured **2.6 ticks/s (x0.06)**, and the direction **flipped to reverse** — heard
  and watched directly on the device, not inferred from magnitude alone
- `CC 18 = 60` + bend `8900`: measured **0.00 ticks/s** — the reel visibly stopped

So the true null sits **between 60 and 61 while playing**, exactly as they found, and `CC 18 = 60`
plus a bend compensation (`+708` in their formula, `8900` unsigned in ours — the same value in
different encodings) lands on it. Our own additive model derives their workaround independently
rather than needing to borrow it. What survives from the original paragraph is only that the stop
point is 64 **when the tape is stopped**, which is a different regime (see the `deadZone` finding
above) and where their own "normal mode" table agrees with us.


**Pitch bend is a separate, persistent speed control** — later measured to be a *signed velocity
offset* rather than the magnitude multiplier described here, with a range of about x0.5-x2.1
rather than x0.25-x2.0. See *TP-7 speed measured numerically* below. Verified: a stray `+708`
(x1.09) left over from an earlier test kept every
subsequent playback slightly fast, surviving stop, rewind and play, until it was explicitly
returned to centre (8192). It is invisible on the device's display — the guide's own note that
pitch bend and the on-screen `SPD` are separate controls means the user gets no feedback that
it is off-centre.

**Anything in the app that drives pitch bend must return it to 8192 when it stops**, or the
user is left with a silently pitch-shifted machine and no obvious cause.

**Transport play resets the CC 18 speed.** After a stop, `0xFB` plays at normal speed rather
than resuming the previous shuttle speed — so the app does *not* need to remember and restore
CC 18. (The apparent counter-example was the stray pitch bend above.)

**Still unknown:** how to jump the TP-7 to position zero on demand. `0xFA` (Start) does restart
playback from the beginning — verified — but that also *starts* the tape, so it cannot serve as
a "rewind while stopped". Untested candidates: Song Position Pointer `0xF2 00 00`, or driving
`CC 18` to a fast-rewind value until the head reaches zero.

**Consequence for this app:** `.directionalTransport` models this correctly — magnitude from
the variable `ClockEngine.transportSpeed`, direction from the op — and `stop` must send
`CC 18 = 64` followed by `0xFC`. Both are implemented.

### TP-7 speed measured numerically — the sync clock as an instrument (title kept for history;
### see the correction above — it's a tempo readout, not literally "tape speed")

⚠️ **The title and the "44.0 ticks/s = 1x" framing below are the thing the correction above
fixes.** Everything in this section still works as a measurement *technique* — clock ticks
genuinely do move proportionally with CC 18 / bend within one session, which is what makes it a
usable instrument at all — but "44 ticks/s" was that session's memo's tempo setting, not a
device constant. Read every "x" value below as relative to *that session's own baseline*, not a
portable absolute.

Judging playback rate by ear failed repeatedly: offset 4 was called "≈normal speed" early on and
is actually **x0.06**, and several rounds of guess-deploy-listen converged on nothing. The fix
was to find an instrument.

**In `sync` mode the TP-7 both accepts incoming CC and transmits MIDI clock, and that clock
tracks the loaded content's tempo setting, moving proportionally with CC 18 within one session.**
So counting `0xF8` ticks per second measures *relative* playback rate change. `44.0 ticks/s =
110 BPM = 1x` was this session's own baseline, established from three independent forward
baselines — not, as originally written here, a universal 1x reference.

This is self-diagnosing: if the clock were a fixed project tempo, the rate would not move when
CC 18 changed. It moves proportionally, so it is tape-derived.

**CC 18 is affine, not proportional.** Driving each offset and counting ticks:

| offset (below 64) | ticks/s | multiplier |
|---|---|---|
| 4 | 2.80 | x0.06 |
| 5 | 14.39 | x0.33 |
| 6 | 26.17 | x0.59 |
| 7 | 37.97 | x0.86 |
| 8 | 49.55 | x1.13 |

Successive differences are 11.59, 11.78, 11.80, 11.58 — a straight line:

```
rate = 11.69 * offset - 44 ticks/s        offset = 3.76 * (multiplier + 1)
```

**There is a dead zone**: the tape does not move until offset ~3.76, and speed rises linearly
only beyond it. Consequences: `offset 4 = 1x` (both the third-party spec and the earlier by-ear
note here) is wrong — offset 4 is the *stall point*. **1x is offset 7.5**, so it is not reachable
at integer resolution: 7 is 14% slow and 8 is 13% fast, both audible and both independently
reported by ear before being measured.

The app therefore models this as `offset = deadZone + unitSpeed * multiplier`, with
`deadZone = 4, unitSpeed = 4` on the TP-7.

**CONFIRMED ON HARDWARE (2026-09-06, firmware 1.1.11): the dead zone belongs to the playing case
only. There is no dead zone with the tape stopped.** Every row in the table above was measured
with the tape *playing forward*, so the +44 ticks/s internal transport was inside every number —
the "dead zone at offset 3.76" is that transport cancelling out, not a motor threshold.

With the tape genuinely parked, `lucidyan/tp7-midi`'s formula is right: `speed = (value - 64) / 4`,
no dead zone. Measured directly, since the sync clock is **blind to CC-18-driven motion from a
parked tape** (0.00 ticks/s throughout, even with the reel visibly and audibly turning — a new
instrument limitation beyond "no clock while stopped," see *Method notes* below) — so this had to
be read off the position counter instead of the clock:

- `CC 18 = 68` (their predicted 1x, our predicted stall/offset-4 point) held for exactly 10.0s:
  position counter went from **11:36 to ~11:46.4-46.5** — **x1.04-1.05, i.e. 1x**. Our model
  predicted ~0.06x (a few tenths of a second of travel); theirs predicted 1x. Unambiguous.
- Separately, the app's own current constants were replayed from a parked tape (`cc18map TP-7
  control`) and judged by ear: `CC 18 = 72` (app believes 1x) sounded "faster than normal,"
  `76` (app believes 2x) "pretty fast," `124` (app believes 14x) "super fast" — all three
  consistent with their formula (2x, 3x, 15x) and each one whole multiple past what the app
  currently claims.

**Consequence: `deadZone: 4` is a device constant only while the internal transport is already
rolling forward. Applied unconditionally, as `ClockEngine.swift:503-515` does today, every
prev/next/scrub sent from a parked tape runs one whole 1x too fast.** `deadZone` needs to become
0 when the tape is parked and ~4 while it plays forward, rather than a fixed profile literal. See
[TP7_VS_TP7MIDI.md](TP7_VS_TP7MIDI.md) for the full writeup and remaining tests.


**Pitch bend is a signed velocity offset, not a magnitude multiplier.** Sweeping bend while
playing forward and again while reversing:

| bend | forward | reverse (cc18=56) |
|---|---|---|
| 0 (-8192) | x0.54 | x1.38 |
| 8192 (centre) | x1.00 | x1.00 |
| 16383 (+8192) | x2.14 | x0.22 |

The sense **flips** in reverse — bend up *slows* a reversing tape. A magnitude multiplier could
not do that. Expressed as a velocity contribution it is consistent across both runs: about
**-20 ticks/s at full negative, +40 at full positive**, added to whatever the transport and CC 18
are already doing.

**RE-MEASURED on hardware, 2026-09-06 (firmware 1.1.11), five-point sweep both directions
(`cc18map TP-7 bend`):**

| bend | signed | forward, measured | forward, ours (orig. 3pt) | forward, theirs |
|---|---|---|---|---|
| 0 | -8192 | **x0.48** | x0.54 | x0.25 |
| 4096 | -4096 | x0.66 | — | x0.63 |
| 8192 | 0 | x0.96 | x1.00 | x1.00 |
| 12288 | +4096 | x1.39 | — | x1.50 |
| 16383 | +8191 | **x1.93** | x2.14 | x2.00 |

| bend | reverse (cc18=56), measured |
|---|---|
| 0 | x1.51 |
| 8192 | x1.08 |
| 16383 | x0.24 |

This resolves two things at once. First, **the internal inconsistency between this table's x2.14
and the "+40 ticks/s at full positive" claim two paragraphs up is settled in favour of the
latter** — measured x1.93 corresponds to +42.4 ticks/s over baseline, matching "+40" almost
exactly. x2.14 was noise from the original single-run measurement; the table above is corrected.
Second, **the negative branch numeric disagreement with `lucidyan/tp7-midi` is resolved in our
favour** — measured x0.48 sits far closer to our x0.54 than to their formula's predicted x0.25.
This is the one place in the whole cross-reference where our own number, not theirs, held up.

The reverse sweep reproduces the original three-point table closely (x1.51/x1.08/x0.24 vs the
original x1.38/x1.00/x0.22) and the sense-flip was independently confirmed by the operator without
looking at any numbers: watching and listening through the full sequence — forward at half speed,
back to normal, fast forward, faster still, then (after CC 18 = 56 engaged) fast reverse, normal
reverse, slow reverse, stop — the direction and relative speed at every step matched the table
above, including the flip itself (reverse got *slower*, not faster, as bend increased toward
maximum positive).

**Follow-up: the two extremes re-verified independently against the position counter** (not just
the clock), using `cc18map TP-7 bendhold <value> 10`, which holds one bend value for an exact
measured elapsed time (not a nominal one) and leaves everything else — CC 18, the transport —
untouched:

| bend | signed | clock (exact elapsed 10.005s) | counter, operator-read | theirs |
|---|---|---|---|---|
| 0 | -8192 | x0.484 | **~x0.50** (5s of travel) | x0.25 |
| 16383 | +8191 | x1.924 | **~x2.00** (~20s of travel) | x2.00 |

Two independent measurement methods — electronic tick-counting and a human reading the physical
counter — now agree closely at both extremes. The negative branch remains decisive: **x0.50 by
direct counter reading is roughly double their predicted x0.25**, confirmed by a completely
different method than the clock sweep above, closing this off as measurement error on either
side. The positive branch sits close to both models (x1.92-2.00), not decisive either way, but
consistent with everything already measured — no reversal or other anomaly at the literal maximum
bend value (16383, all bits set), which was worth checking given how close that value sits to a
14-bit wraparound.

**Bend does nothing on its own.** With the transport stopped, holding bend at -8192 for 10s left
the position completely unchanged (verified on the display: 2:16 before and after, no transport
message sent at any point). Bend only scales an already-rolling transport.

⚠️ **Correction to a widely-repeated claim** (an LLM answer citing TE, and the same idea in the
third-party spec): that pitch bend maps directly to tape motor speed *and direction*, with
`-8192` = "normal 1x playback in reverse" and `E0 00 00` as a one-message reverse command.
Measured, `-8192` gives **x0.5**, not x1 — and with the transport stopped it does not move the
tape at all. The claim's other two rows are correct (centre = 1x forward, +8192 = x2.14 forward),
which is what makes it plausible. Direction cannot come from bend.

**Reverse at exactly 1x = `CC 18 = 56` plus pitch bend `9700`.** Offset 8 alone is 49.7 ticks/s;
the bend trim pulls it to 43.95 against a 44.0 target (0.1% error). Bend is the fine control
because CC 18 has no resolution between offsets.

**Confirmed against ground truth.** The device's own reverse (its play button, nothing sent from
the Mac) measured **44.06 ticks/s over 30 s = x1.000** — so the TP-7's native reverse is the same
rate as forward, and the calibrated app reverse sits **0.25% away** from it. Also confirmed by
ear in a direct forward/reverse A/B.

### CC 18 is additive — it stacks on the device's own direction

Found by driving the app's reverse while the tape was already reversing under its **own**
transport (play pressed twice on the device): it went to roughly **3x backwards** instead of 1x.

`CC 18` does not set an absolute speed. Like pitch bend, it is a **signed velocity added to
whatever the transport is already doing**:

```
net = transport (±44) + CC 18 contribution + bend contribution
CC 18 contribution = -11.69 * offset ticks/s
```

| internal transport | CC 18 = 56 | net | |
|---|---|---|---|
| forward +44 | -93.5 | **-49.5** | matches the measured 49.55 |
| reverse -44 | -93.5 | **-137.5** | ~3x backwards — the bug |

This also reframes the "dead zone" recorded above. Offset 3.76 is not a motor threshold, it is
where -44 exactly **cancels** forward playback. That is why offset 4 looked like a stall: it is a
null point, not a limit. The affine formula the app uses is therefore correct *only while the
device is internally playing forward*.

**Confirmed by a prediction it was not fitted to.** With reverse engaged, sending `CC 18 = 64`
alone (no `0xFC`) gave *forward, faster than normal* rather than a stop:

```
with CC 18:     +44 - 93.5 + 5.6 (bend trim)  = -43.9   1x reverse
CC 18 removed:  +44        + 5.6              = +49.6   1.13x forward
```

The leftover 13% is the bend trim still applied — which is exactly why the app releases the trim
before returning to forward.

**The fix: force a known direction.** The device never reports its state, so the app cannot read
the direction — but it can *impose* one. Sending `CC 18 = centre`, `0xFC`, `0xFB` resets the
internal transport to forward, after which CC 18 lands predictably. Verified on hardware sent
back to back, with **no settling delay needed and no audible gap**, so it costs nothing.

Without this, driving transport from both the app and the hardware buttons desyncs and reverse
runs at 3x.

**Method notes for anyone repeating this:**
- The clock rate is **unsigned** — it measures speed, never direction. Direction always needs ears.
- The device emits **no clock while stopped**, so this instrument goes blind exactly when the
  transport is parked. A "0 ticks/s" reading there means "stopped", not "the motor is not turning".
- **This blindness extends to CC-18-driven motion from a parked tape.** Confirmed directly:
  holding `CC 18 = 68` from a stop moved the reel and counter at a clear, audible 1x (see the
  `deadZone` finding above), while the clock read a flat 0.00 ticks/s the entire time. So "no
  clock" cannot be read as "no motion" even when CC 18 itself is doing the driving — only the
  position counter or the reel can confirm movement in this state.
- Never send `0xFC` twice. A stop while already stopped rewinds to zero; an early version of the
  test tool did this and produced a spurious "31s -> 0s" jump that looked like a scrub.
- Sample for at least ~10 s. One-second windows alternate between ~43.8 and ~44.8 as ticks land
  on window boundaries; only the average is meaningful.

### TP-7 CC 18 extremes — a distinct high-speed seek regime, not the affine model extrapolated

**Both this project's affine model and `lucidyan/tp7-midi`'s linear formula agree, at the extreme
ends of CC 18 (0 and 127), on a prediction of roughly x16.** Measured directly on hardware
(2026-09-06, firmware 1.1.11, `cc18map TP-7 extremes` and `cc18map TP-7 hold`), the real numbers
are **an order of magnitude higher**:

| test | value | held for | tape moved | measured multiplier |
|---|---|---|---|---|
| short burst | 127 | ~4s | +7m25s | ~x99 |
| short burst | 0 | ~4s | −11m38s | ~x155 |
| full 10s hold | 127 | 10.0s | +41m25s | **x248.5** |
| full 10s hold | 0 | 10.0s | −46m29s | **x278.9** |

(The `extremes` mode's clock reads 0.00 throughout both bursts — the same clock-blindness as the
`deadZone` finding above, confirmed to extend across the whole CC 18 range. Direction and
magnitude here come entirely from the operator reading the position counter directly, off video,
before and after each burst — not from the clock.)

**The longer hold moved roughly 2-2.5x faster on average than the short burst**, which means the
motor is still visibly ramping up well past 4 seconds, and even the 10-second figures above may
understate the true ceiling. Reverse is consistently a bit faster than forward at every duration
tested, though the gap narrows as the hold gets longer (x155/x99 ≈ 1.57x at the short burst,
x278.9/x248.5 ≈ 1.12x at 10s) — consistent with both directions converging toward their own
ceiling as the ramp completes, rather than one direction being fundamentally faster forever.

**The operator watched the ramp directly and reported it takes about 2 seconds to reach full
speed.** Approximating the ramp as linear (so it contributes about one second's worth of
terminal-speed distance over that 2s, not two), the remaining ~9s of each 10s hold is close to
terminal speed, giving a cleaner steady-state estimate than the raw 10s average:

| direction | raw 10s average | ramp-corrected (÷9s) |
|---|---|---|
| forward | x248.5 | **~x276** |
| reverse | x278.9 | **~x310** |

Same order of magnitude either way — the correction narrows the gap to either model's ~x16
prediction from "15x higher" to "17-19x higher," it doesn't change the conclusion.

**This is very likely a distinct high-speed seek/scan behavior, not a continuation of the affine
ffwd/rewind curve** established elsewhere on this page. That curve was calibrated entirely from
offsets in the 3-12 range (near the centre); nobody — either project — had previously pushed CC 18
all the way to 0 or 127 and actually measured what happens. A physical reel mechanism plausibly
has two different modes: a play-head-engaged variable-speed mode (the affine model, moderate
offsets) and a fast-wind mode much like pressing physical FF/REW on a cassette deck (no play-head
engagement, so no speed ceiling tied to audio fidelity) — x250-280 is a plausible fast-wind speed
for a physical reel, in a way x16 barely is.

**Consequence for the app:** `ClockEngine.swift`'s `maxScrubSpeed = 14.0` ceiling is a deliberate
product choice about how fast momentary scrub should *feel*, not a claim about what the device can
physically do — this finding doesn't invalidate it. But it does mean the device has a much larger,
currently completely unmapped speed range above where our affine model applies, should a "seek"
style feature ever be wanted. The transition point between the two regimes (where does the affine
model stop applying and the fast-wind behavior take over?) is unknown and would need its own
sweep — this was only tested at the two absolute extremes.

**Neither the ramp nor the fast-wind regime itself appears anywhere in `lucidyan/tp7-midi`.** A
search of their `MIDI_SPEC.md`, `README.md`, `docs/MANUAL.md`, `docs/FIRMWARE_CHANGELOG.md`, and
`app.js` for "ramp," "accelerat," "spin up," or "gradual" returns nothing — their model treats
every CC 18 value as an instantaneous fixed speed with no time dimension at all
(`speed = (value-64)/4`, applied the same way whether held for 10ms or 10s). This entire finding
is new, not a rediscovery of something either project already knew.

**Caveats:** these are order-of-magnitude figures. The short-burst numbers came from a phone video
sampled at 2fps with a hard-to-read counter under motion blur; the 10-second-hold numbers are far
more solid (a stopwatch-precise 10.0s elapsed, exact H:MM:SS counter reads before and after,
confirmed against a video correction mid-conversation), but still may not represent true steady
state given the visible ramp between 4s and 10s. Neither test ran the tape past a physical
boundary — both were set up with several hours of margin. If this needs settling further, it
should be with a hold long enough to see the multiplier stop increasing between two durations.

### TP-7 does NOT follow incoming MIDI clock — `followsClock: true` is wrong

**CONFIRMED WRONG on hardware, 2026-09-06.** `DeviceProfiles.swift:278` has carried
`followsClock: true // UNVERIFIED` since the field-device refactor, and `tp7.tempo`
(`.virtualTempo`) — the parameter that lets an LFO modulate the TP-7's tempo — is built entirely
on that assumption being true.

Tested with `tools/midi/clocksuppress`, tape playing normally in `sync` mode, at three separate
target tempos:

| sent | target rate (24 PPQN) | measured, before | measured, while sending | moved? |
|---|---|---|---|---|
| 90 BPM | 36 ticks/s | ~51.3 ticks/s | ~51.5 ticks/s | **no** |
| 130 BPM | 52 ticks/s | ~51.5 ticks/s | ~51.5 ticks/s | inconclusive — coincidentally close to natural rate |
| 60 BPM | 24 ticks/s | ~51.5 ticks/s | ~51.5 ticks/s | **no** |

The device's own outgoing clock — already established elsewhere on this page to be a direct
tape-speed readout — never moved from its natural rate (~51-52 ticks/s for this particular
recording; confirmed by the operator to be normal playback speed, not a stray leftover pitch bend
or SPD offset from earlier tests) at any of the three tempos, including two (90, 60) that are
unambiguously different from that natural rate. The 130 BPM pass happened to land close to the
natural rate by coincidence and is not informative on its own, but the other two are decisive: **a
device genuinely slaving playback speed to incoming clock would show its own transmitted rate
moving toward the imposed tempo, and it never did.**

**What is confirmed working:** the device keeps transmitting its own clock at its natural rate the
entire time it is receiving ours — not suppressed. So `ClockEngine.deviceIsRolling`, which listens
for exactly this, is safe regardless of whether the app is also sending clock.

**Consequence:** `followsClock` should be `false`, and `tp7.tempo` — currently shipped and
`lfoTargetable` — likely does nothing audible on real hardware. This wasn't tested with the device
literally in the middle of receiving an LFO-modulated tempo sweep (only fixed 90/130/60 BPM
streams), so a final check with `tp7.tempo` actually running before making a code change would be
worth doing, but the evidence here points the same direction three times.

### TP-7 `ctrl` mode — verified transmit behaviour

`ctrl` is a true controller mode, confirmed on hardware in both directions:

- **Full incoming lockout.** CC is ignored (volume sweep did nothing) *and* real-time transport
  is ignored (0xFA/0xFC did nothing). It is not merely "CC off" — nothing gets in.
- **Transmits its whole control surface** on channel 1, buttons as value 127.
- Entering `ctrl` stops tape playback and the display shows only "CTRL".

Ten distinct controls were observed transmitting: `CC 20, 21, 22, 23, 24, 25, 26, 27, 28, 30`
and pitch bend. Of these, `CC 28` (mode) is absent from the published reference.

**`memo` is CC 27, as documented** — verified in isolation (a capture with only that button
pressed produced exactly one message, `ch1 cc27 = 127`).

**`CC 28` is the `mode` button** (bottom left, next to record) — **undocumented**. It does not
appear anywhere in the published TP-7 MIDI reference, but it transmits `127` like the others.
Isolated and confirmed separately from memo.

(An earlier note here claimed memo was CC 28. That was wrong — it came from a capture where the
bottom-left button was pressed by mistake. Corrected after re-testing each button in isolation.)

**The wheel (CC 30) is a signed relative encoder: magnitude is speed, sign is direction.**
Measured by spinning the reel one way and then the other, 875 messages with no overlap between
the ranges:

| direction | values |
|---|---|
| clockwise | `1, 2, 3` |
| counter-clockwise | `125, 126, 127` |

Standard two's complement: `127 = -1`, `126 = -2`. The motorised reel turning on its own during
forward playback produced a steady 1-2 at roughly 57 messages/second, so a playing TP-7 in
`ctrl` mode is a constant ~57 msg/s source of traffic.

(An earlier note here called this "a relative encoder whose value is rotation speed", concluding
that the value was magnitude only. That came from watching forward playback exclusively, where
the negative range never appears.)

**The wheel is transmit-only — the TP-7 does not receive CC 30.** Tested with the tape stopped
mid-file in `sync` mode: ~250 messages of `CC 30 = 30` over 4 s, then the same at `= 98` (-30),
with nothing else sent. Neither the reel nor the position moved at all. So there is no "wheel"
parameter to expose: sending CC 30 to the device does nothing, and shuttling is already covered
by `speed` (pitch bend), `direction` and CC 18 — all of which are absolute, and therefore usable
as LFO targets in a way a relative encoder would not be.

**Nor can it give the app playback direction.** CC 30 is transmitted only in `ctrl` mode,
which refuses all incoming MIDI and stops the tape — so direction is readable only when the app
cannot control the device, and controllable only when direction is unreadable. Confirmed both
ways: every sync-mode measurement run counted `wheel 0 msgs`, and the ctrl-mode capture got 179
in 15 s. To detect direction while driving the device, see the additive probe below.

**At rest the TP-7 is completely silent** — 20 s of idle with the tape stopped produced nothing,
no active sensing, no chatter.

**Caution on the other button labels.** The published table's names (up/down/left/right) do not
map cleanly onto the physical controls (a rocker, `-`/`+` buttons, separate user buttons), so
only `memo`, `rec`, `play`, `stop`, the wheel and the rocker are confidently identified here.
The remaining CC numbers are confirmed to exist but their button labels are not.

### TP-7 input gain (CC 9) — measured curve

Stepped through nine values, holding each so the on-screen dB could be read:

| midi | 0 | 16 | 32 | 48 | 64 | 80 | 96 | 112 | 127 |
|---|---|---|---|---|---|---|---|---|---|
| dB | 0 | +5 | +10 | +15 | +21 | +26 | +31 | +37 | +42 |

**Linear in dB**: `dB = midi x 42/127`, about 0.33 dB per MIDI step, range 0 to +42 dB. Every
measured point is within 1 dB of that line.

Worth knowing for automation: because the scale is linear in dB — which is already logarithmic
in amplitude, and roughly matches how loudness is perceived — a sine LFO on gain rises and
falls evenly. A control that was linear in amplitude would make the same LFO sound lopsided.

**Gain is inaudible on tape playback.** It is an input-stage control, so sweeping it while
playing a recorded file changes the on-screen dB but not the sound. Anyone testing this
feature against a recording will think it is broken.

**`CC 9` addresses the three physical input jacks, which feed the six mix channels.** It is a
preamp at the *input stage*, so it sits upstream in the signal chain:

```
input jack 1-3  ->  [ CC 9 gain applied here ]  ->  mix channels 1-6
```

Gain therefore does affect what you hear — but only for audio actually arriving through that
jack. If nothing is coming in on jack N, changing gain N does nothing audible, even though the
setting itself moves. That is what made this confusing to pin down:

| test | result |
|---|---|
| `CC 9` ch 5 | nothing at all — no display change, no audio. Gain really is 1-3 only. |
| `CC 9` ch 3, audio on track 5 | display moved, **audio did not** |
| `CC 9` ch 1, audio on track 1 | display moved, **audio did not** |
| `CC 9` ch 1, audio patched into **input jack 1** | display moved **and the audio changed** |

Every "no audio change" above is explained by there being no live signal on that jack at the
time — not by the gain being disconnected from the mix. Once a source was patched into jack 1,
gain 1 changed it immediately.

The display always moves regardless, because the setting is real whether or not anything is
plugged in. Watching the display alone would have given the wrong answer three times over; only
listening distinguished them.

**Consequence for this app:** gain is addressed per *input jack*, not per track, so modelling it
as a track parameter on tracks 1-3 implies gain 1 belongs to track 1. It does not — it belongs
to jack 1, whose signal reaches whichever mix channels it is routed to. Modelled as three
master-level controls instead.

### TP-7 loop (CC 17) is a state machine — verified

Setting `in` (1) then `out` (2) three seconds apart created a working 3-second loop: markers
appeared, the audio repeated, and `off` (0) released it cleanly with playback continuing.

**But `out` sent with no prior `in` is silently discarded** — tested twice, no display change, no
audio change. So the values are not independent; the order is mandatory, exactly as
[lucidyan/tp7-midi](https://github.com/lucidyan/tp7-midi) reports.

**Consequence:** loop is marked `lfoTargetable: false`. An LFO sweeping 0-127 maps cyclically
onto 0/1/2, so most of the sweep would be discarded and the rest would drop loop points at
arbitrary moments — noise rather than modulation. This is the same class of modelling error as
CC 18: a state machine dressed as a plain value.

**Precondition discovered 2026-09-06: CC 17 only has any effect while the device's LOOP screen is
actively showing.** The first attempt at this test (`tools/midi/looptest.swift`, `sync` mode,
tape playing normally, main playback screen showing) sent the identical `1`/`2`/`0` sequence and
produced **zero observable change** — no display change, no audio change, nothing. Entering the
LOOP screen on the device (hold record, per `docs/MANUAL.md` page 47 in the
[tp7-midi](https://github.com/lucidyan/tp7-midi) transcription) and rerunning the exact same
sequence worked immediately: a ~4-second loop formed and cycled repeatedly. Same shape of gap as
the cue-marker finding below — a MIDI CC that only does anything once the device's own UI has
navigated to the matching screen, undocumented anywhere. The original loop finding earlier in this
document didn't record which screen was showing at the time, so it was very likely already on the
LOOP screen without that being written down.

**Loop is immutable once active — confirmed on hardware.** With the loop already cycling
(`in`=1 then `out`=2 sent, LOOP screen active), sending `1` again and then `2` again — each several
seconds into the already-repeating loop — produced **no change whatsoever**: same length, same
position, looping continuously through both resends. Only `0` (off) had any effect, releasing the
loop and letting playback continue past the old out point. This confirms
[lucidyan/tp7-midi](https://github.com/lucidyan/tp7-midi)'s claim exactly ("once loop is active
... you can ONLY exit with Off (0)") — the loop is locked, not re-triggerable, once both points
are set.

### TP-7 cue rec mode (CC 16) — no observable effect

Sent `127` four times and `0` twice in midi mode `off`, with the tape playing, then `127` again
in midi mode **`cue`** — on the theory that a mode of that name might be what makes a
"cue rec mode" CC meaningful. **No change was visible on the display or audible at any point,
in either mode.**

This is recorded as *unverified*, not as *working* — and not as *broken* either. On a device
that never reports its state, there is no way to distinguish "silently succeeding" from "doing
nothing". Possibilities not ruled out:

- it needs a precondition we did not set up (armed, recording, or a particular menu state)
- it has no front-panel indicator at all
- it is inert on this firmware, like `CC 18 = 64` turned out to be

### The whole cue subsystem appears inert over MIDI

`CC 16` was tested in **all three receiving modes** (`off`, `cue`, `sync`) — no observable effect
in any of them.

Incoming **notes** were then tested as well, since the reference says notes create cue markers.
Three notes (C, E, G) were sent in `sync` mode and again in `cue` mode with the cue submenu
selected. **No cue markers appeared.**

This negative is trustworthy because the tester first created a cue marker by hand and deleted
it, to confirm what one looks like on the display before judging the MIDI attempts. Without that
control the result would only mean "nothing recognisable happened".

So neither documented half of the cue subsystem — `CC 16` cue rec mode, nor note-triggered cue
markers — produces any effect on this firmware. Something else is required that is not
documented, or the feature is not implemented over MIDI.

**Consequence:** `tp7.cueRec` is marked `lfoTargetable: false`. Independent of whether it works,
modulating a mode-enable at LFO rates is not musically meaningful, and exposing a control whose
effect nobody can confirm — on hardware that cannot report back — is worse than not exposing it.
Notes are not exposed by the app at all, so no change was needed there.

### TP-7 mute (CC 120) — absolute, not a toggle, confirmed on hardware

**CONFIRMED 2026-09-06.** `DeviceProfile.swift` previously marked TP-7 mute polarity as
unverified, even though the CC number itself (120) was never in question — both this project and
[lucidyan/tp7-midi](https://github.com/lucidyan/tp7-midi) always agreed on it, and it was already
confirmed on the TX-6. This test closes that gap for the TP-7 specifically:

- `CC 120 = 127` → track 1 muted
- `CC 120 = 127` again → **still muted, no change** — absolute, not a toggle
- `CC 120 = 0` → unmuted
- Three rapid mute/unmute cycles, 2 seconds apart → tracked cleanly every time, no lag, no missed
  transitions

Matches the TX-6 behaviour and `lucidyan/tp7-midi`'s claim exactly. `SwitchEncoding.inverted`
stays `false`, now verified on both devices, not just the TX-6.

**Gotcha hit along the way: the device can enter an unresponsive state that only a reboot
clears, with no visible symptom.** Mid-session, CC 120 and CC 7 (volume) both stopped having any
effect at all — silence from a device that was, by every visible sign, correctly configured
(`sync` mode confirmed on its own settings screen, MIDI endpoint confirmed online and receiving
the bytes). Two brand-new ad-hoc test scripts were suspected and ruled out one at a time: first by
routing the exact same messages through the already-proven `cc18map` binary (a `raw <b0> <b1>
<b2>` mode was added for this — see `tools/midi/cc18map.swift`), which also produced no effect,
then by rebooting the TP-7 itself. The reboot fixed it immediately; the identical bytes through
the identical code path worked right after. **If a previously-working CC suddenly does nothing
and everything about the setup checks out, reboot the device before suspecting the tooling or the
MIDI mode setting** — this is a real, if rare, device-side hang, not a MIDI protocol fact.

### TP-7 record (CC 14) — arms, does not record

`CC 14 = 127` puts the TP-7 into **record-armed**: red light blinking, display showing 0
seconds, no audio. It does **not** start recording. The published reference calls this simply
"record", which implies it rolls.

| action | effect |
|---|---|
| `CC 14 = 127` | arms record |
| waiting | arm **persists** — still blinking after 30 s, no timeout |
| `CC 14 = 0` | disarms |
| **`0xFC` (stop)** | **also cancels the arm** |
| `CC 16` while armed | nothing — tested in isolation with nothing else sent |

Two differences from the physical button, both undocumented:

- The **hardware record button stops the reel** as part of arming. `CC 14` does not — arming
  while a tape is rolling leaves it rolling. So the button is a compound action the CC does not
  reproduce.
- Arming while transport is running and then sending `0xFC` cancels the arm rather than leaving
  it armed and stopped.

**`CC 14` alone cannot record — it only arms.** But arm followed by play *does* record, mirroring
the physical sequence exactly (press record once to arm, press play to start):

```
CC 14 = 127   ->  armed   (blinking, 0s)
0xFB          ->  RECORDING BEGINS
0xFC          ->  stops
```

Verified on hardware: this produced a 4-second recording from a live input.

**It created a NEW track rather than overwriting the one that was loaded** — non-destructive in
the configuration tested. Whether that is fixed behaviour or depends on a record-menu setting is
**unconfirmed**: the TP-7 guide has `#recording` and `#record_menu` sections, but that page
serves its content as images and the text could not be retrieved. Check the device's own record
menu before relying on this.

**Do not assume MIDI recording is safe.** One observation in one configuration is not a
guarantee, and a setting that made record overwrite the current take would turn this into a
destructive operation with no warning.

### End-to-end validation — the app driving a TP-7 (iPhone, USB-C via adapter)

First run of the actual app against real hardware. Everything below was verified on device:

- **Auto-detection works.** Status bar showed `TP-7 (usb)` with a green dot on launch, with no
  manual override — so endpoint-name matching, profile resolution and the status-bar wiring all
  work together.
- **6 track strips** with the tracks 5-6 colours.
- **No pan knobs** (`caps.hasPan: false`), faders taking the full height.
- **Transport shows the profile's symbols** (fast-forward / rewind rather than the OP-1 arrows).
- **Parameter picker shows the TP-7's own vocabulary** ("mix volume", not "volume").
- **Metronome dimmed**, since the app is forced clock master.
- **Faders drive the device**: dragging a volume fader changes the matching value in the TP-7's
  own mix submenu, exactly.
- **An LFO on volume runs and sweeps the device.**

**Control is one-way, app -> device.** The TP-7's mix values do not follow back into the app,
which matches `mirrorsIncomingCC: false` and is the same behaviour as the OP-1.

## Hardware findings — OP-1 Field global controls: sustain, pitch bend, EQ, record level (2026-10-23)

Question: which of the reference's remaining CCs fit the LFO parameter system, and how do they
actually behave? The reference is thin ("any channel", a range) and two of its claims turned out
to be incomplete.

Method: OP-1 Field over Bluetooth to a Mac. `tools/midi/sweep` sends a slow centre -> top ->
bottom -> centre sweep of one CC or pitch bend on chosen channels, announcing each, while the
operator plays notes or runs a tape loop and watches the OP-1's screen. Single values with
`tools/midi/cc18map OP-1 raw`. The OP-1 reports nothing back, so every result is read off the
device by eye and ear.

| control | result |
|---|---|
| **Sustain, CC 64** | 127 holds live notes; 0 and 63 release; behaves like a piano pedal. Exactly 64 was not sent (taken from the reference). Whether it holds notes on tape playback was not tested. |
| **Pitch bend** | **Global, channel 1 only.** It bends the selected instrument's live notes. Channels 2, 3 and 4 do nothing (three runs of each): not the instrument, not the tape loop, not another track. It never touches recorded or played-back tape. Presumably it drives the instrument's portamento / bend-range settings (T2, envelope screen); that link is a guess. Channels 5-16 were not swept. |
| **Bend is a held level** | One `E0 7F 7F` stayed in effect with nothing re-sent: 3 s in one test, then 30+ s in another through releasing keys and switching instrument. It cleared only when the patch was reset on the device. The no-bend value is **8192** (`E0 00 40`); 0-16383 has no integer midpoint. |
| **Master EQ, CC 90 / 91 / 92** | All three move the matching knob on the OP-1's EQ screen and audibly change the sound. **64 is dead centre on all three.** Answered on channel 1. |
| **Record level, CC 78** | One global level, moved by the same CC on channel 1 and channel 4 ("any channel"). It drives the red record-level line on the tape screen and the volume of whatever the synth or drum engine is playing live, so it sets the level recorded to tape. Tape playback is unaffected. TE's guide calls it both the recording level and "the main level for Synthesizer and Drum sounds". |

**Record level resets to CC 95 on power-up.** No default is published, so it was measured from
photos of the tape-screen dot, aligned on the dot's red line: the startup photo versus photos after
sending CC 78 = 95 and = 96 put the dot at 75.55%, 75.49% and 76.03% of the way up the line. That is
-0.1 of a step for 95 and +0.6 for 96, which fits 95 and not 96. 95 / 127 = 74.8% (74 on the 0-99
display scale). One step is about 1.5 px on the best photos; use a close-up with the whole line in
frame, because a wide shot (86 px line) could not separate 95 from 96.

**Consequences for the app.** The device holds every one of these, so a stopped LFO leaves them
wherever it last put them. Each carries a neutral `restValue` that the "previous" pause/finish
option returns to: bend 8192, EQ 64, record level 95, sustain 0. A force-quit, a crash or a
Bluetooth drop in the middle of a bend LFO leaves the bend on; sending 8192, or resetting the
patch, clears it. Bluetooth also dropped between probing sessions (the OP-1 goes to sleep and the
endpoint disappears): re-run `./mididiag` before trusting a silent result.

## Hardware findings — OP-1 Field transmit behavior (2026-10-16)

Question: does the OP-1 Field send CC when its own controls move, or echo CC it receives? The
app's mirroring code (`router.onCC`, `mirrorsIncomingCC`) and an earlier note here assumed yes.
That claim traces to the 2026-06-13 Swift rewrite (`bef84db`), with no measurement recorded.

Method: OP-1 Field attached to a Mac (not the iPad), listening with `tools/midi/anymidi` while
sending with `tools/midi/cc18map OP-1 raw`. Two 5 s windows per mode:
- **A, knob control:** turn the track 1 volume knob on the mixer page (the OP-1 screen showed the
  change); listen for any CC.
- **B, echo test:** send `B0 09 7F` (mute on), `B0 07 64` (volume 100), `B0 09 00` (mute off)
  about 1 s apart; listen for anything coming back. The OP-1 reacted to all three every time
  (track 1 muted, volume display went to 77 = `100 * 99 // 127`, then unmuted), so the silence is not
  a failure to deliver.

| Transport | Tempo mode | A: knob sends CC? | B: received CC echoed? |
|---|---|---|---|
| USB | beat match | no (clock only) | not tested |
| USB | free | no (nothing at all) | no |
| USB | midi sync | no (nothing at all) | no |
| BLE | beat match | no (clock only) | no |
| BLE | midi sync | no (nothing at all) | no |

Conclusion: in every combination tested, the OP-1 Field neither reports its own knob moves as CC
nor echoes received CC. Control is one-way, app -> device, as on the TX-6 and TP-7.
`mirrorsIncomingCC` is therefore `false` for all three devices.

Not tested: PO sync and 1/16 sync modes; USB echo in beat match; other controls (buttons, pan,
FX knobs); the original OP-1 (not the Field). A different firmware or an untested mode could
differ, so re-run this before relying on any mirroring.

Consequence for testing: nothing can observe the bytes the app sends to a physical device, because
a CoreMIDI client only sees what the device transmits. Delivery is confirmed only by watching the
device react (`notes/HARDWARE_CHECKLIST.md`). The old on-device listener test
(`MidiHardwareUITests`, which waited for an echo) could never pass and was removed.

## Hardware findings — OP-1 Field transport position in midi sync (2026-10-16)

Question: when the app presses play, where does the OP-1 tape start? In the app, play started at
0 the first time and then always resumed at the app's last stop position, even after the tape was
moved by hand on the OP-1. Isolated from a Mac (`sendbytes` / `sendclock` one-off probes, USB),
OP-1 in **midi sync** (app = master), tempo 110 BPM, clock sent at 120 BPM (OP-1 showed 109%).

- **A lone `0xFB` with no clock does nothing.** The slave waits for clock. (CC 83 / next bar did
  move the tape, so the link was fine.)
- **`0xFB` with clock already running** starts the tape from the OP-1's own current position
  (26s -> 31s, 35s -> 40s).
- **Hand moves are discarded.** Tape parked by hand at 10s, then clock + `0xFB`: it sat at 10s,
  then jumped to 40s (where the previous synced run had stopped) and played from there.
- **An SPP positions the tape.** `F2 64 00` (SPP 100 = 25 beats) then clock + `0xFB` started at
  13s. Sent *alone*, with no clock, Continue or Stop, the counter went 18s -> 13s 15 frames:
  25 beats * 60/110 = 13.636 s = 13 s + 15 frames at 24 fps. SPP maps to tape time at the OP-1's own
  tempo, exactly.
- **Speed follows the clock** (displayed 100% -> 109% as the clock arrived, before any movement).

So the OP-1 resumes from "the last synced position", not from the physical tape position.

**Tape prev/next: use the CC alone (2026-10-16).** CC 82/83 is a *relative* nudge from the tape's
real position. The app used to follow it with an SPP and, while playing, a Continue; the SPP is
absolute, so every press snapped the tape to the app's own position counter (the first press
from a tape parked at 30 s landed at 2 s). Dropping the SPP fixes that: three presses of next
move three bars from wherever the tape is, and a play afterwards starts at the *nudged* position,
so a CC nudge, unlike a hand move, is not discarded. The nudge does halt a rolling transport;
sending a Continue after it keeps the tape playing, as the device's own buttons do, and the
tape stays stopped if it was stopped. Verified over BLE in midi sync, including a tape started
from the OP-1 itself. `.tapeSeek` (CC + SPP) is kept as an op for devices that want an
absolute seek; no profile uses it now.
 The
OP-1 never reports its position back (see the transmit findings above), so the app cannot know
it. Only the app's own tape prev/next buttons, which send an SPP, move the tape reliably.

Same as `main`: it also sent `0xFB` after the first play, and `0xFA` only on the first play of a
session (equivalent at position 0). Not verified by running the 1.0 build.

## Clock over Bluetooth: time the ticks by the sender's stamps (2026-10-18)

Over BLE the 24-PPQN clock ticks reach the app in bursts and stalls, so timing them by **arrival** gives a
noisy tempo. Measured on a TX-6 over BLE (iPad Pro, `clock src = int`, `clock out = on`):

| tempo | tick spread by arrival | tick spread by the sender's stamp | per-second tempo by arrival (5th-95th pct) | by stamp |
|---|---|---|---|---|
| 60 BPM | sd 5.25 ms, intervals up to 60 ms | sd 0.47 ms (41-43 ms) | 59.61 to 60.55 | 59.981 to 60.038 |
| 80 BPM | sd 5.7 ms, intervals 7.6-68 ms (one 537 ms stall) | sd 0.43 ms (30-32 ms) | 79.73 to 80.17 | 80.000 to 80.000 |
| 400 BPM | sd 5.2 ms on a 6.25 ms tick, intervals 0.1-55 ms | sd 0.43 ms (5-7 ms) | 396.3 to 403.0 | 399.70 to 400.20 |

USB is already tight (sd 0.23 ms), so it keeps arrival timing.

**The spec** (BLE-MIDI 1.0, read from the PDF): every MIDI status byte, System Real-Time included, "must be
preceded by a timestamp byte"; timestamps are 13-bit milliseconds (wrap at 8192), "issued by the sender in a
monotonically increasing fashion", "in the sender's clock domain"; they exist because messages "must be
buffered and transmitted each BLE connection interval" and carry "the render time and event spacing". The
correlation with the receiver's clock "is not addressed in this document", but tempo only needs the
**differences** between stamps. Ableton's manual warns stamp accuracy "can vary widely" by hardware, so a tick
whose stamp cannot be a real tempo falls back to arrival time (`ClockEngine.senderInterval`: 2 ms to 2 s).
BlueZ ignores the stamps; Apple asks accessories to request a 15 ms connection interval or less.

Three bugs the 400 BPM run exposed: stamped intervals of exactly 5 ms (6.25 ms ticks on 1 ms stamps) were
thrown away as arrival bursts, biasing the tempo low; a 96-tick window is only 0.6 s at 400 BPM, where 1 ms
of stamp resolution is +/-0.17% of it (the window is now at least 1 s, or 3 s without stamps); and the app
ignored any tempo above 300, so 400 read 300.0 (one ceiling now, `AppState.maxBpm`, 440). The BPM box is
also told of a new tempo at most 4 times a second, because a tempo that is itself moving otherwise redrew it
on every tick.

**Then the smoothing came off.** With stamps accurate to 0.4 ms, every smoothing step (the window, the step
detection, the snap, the hysteresis) only added lag: raw per-tick timing from the stamps, with only the
4-a-second display limit, locked onto a new tempo at once, where the smoothed version arrived within 1-2 BPM
and took about a second to settle. `ClockEngine.antiJitter = false` for sender-stamped ticks; the logic is
kept (set it true to restore it) and still applies to ticks timed by arrival.

**Then it went back on.** Raw readings are only as good as the stamps: whole milliseconds, plus the source's own
tick timing. At 400 BPM (6.25 ms a tick) single intervals read 6 or 7 ms, 416.7 / 357.1, so raw mode now spans
~0.5 s of ticks (`rawSpanSeconds`). That left ~0.1% wobble (386.9 / 387.7 at 387 BPM), which looked less steady
than the smoothed readout, so `ClockEngine.antiJitter = true` again (2026-10-18). Raw mode is kept behind the flag.

## Open questions — answer on hardware

- [ ] Do the pinned FX-bus channels (ch 8/9) actually land?
- [ ] Does the TX-6 *follow* incoming MIDI clock, even though it does not send it?
- [x] How badly does TX-6 CC 46 desync when the transport is started from the device panel? (2026-10-18: CC 46 works from the app: play starts the sequencer, play again restarts it, stop pauses it. A press on the device followed by one in the app just restarts it; the one odd case is a start on the device then a stop in the app while the device is stopped, which can start it. Accepted; the device never reports its own transport.)
- [ ] Is TX-6 program change on ch 7 usable for scene slots?
- [ ] Exact BLE peripheral names for TX-6 and TP-7 — or whether they do BLE MIDI at all.
- [ ] A TP-7 CC 18 ff/rewind step size that feels right (currently ±8).
