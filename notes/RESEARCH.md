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

## Beat Match: Start/Stop are bar-position beacons, not transport state

In Beat Match mode, the OP-1 sends MIDI Start (0xFA) and Stop (0xFC) at bar boundaries as a clock-position signaling mechanism — even when the tape is completely stopped. These are byte-for-byte identical to actual play/stop button presses.

**Consequence:** It is impossible to track whether the OP-1 tape is actually playing by listening to Start/Stop in Beat Match mode. Any debounce or filtering approach fails because Stop arrives mid-bar and the gap between Stop and the next bar-boundary Start is several seconds (tempo-dependent) — no debounce window can span that gap without also swallowing real stop events.

**App behavior:** The play button sends a MIDI signal to the OP-1 but does not attempt to reflect OP-1 transport state. User checks the OP-1 directly to know if tape is playing.

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

**CC 120 is standard MIDI "all sound off".** TE reuses it per channel for mute. Sending it will
also silence unrelated gear sharing a hub.

## tp-7

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
for UI mirroring rather than misinterpreted. The OP-1 echoes its mixer on the CCs it accepts,
so it keeps mirroring enabled.

### Confirmed transmitting

`cc1` fader 1 (range 0-127) · `cc18` middle knob 6 · `cc24` lower knob 6 ·
`cc25-30` all six track buttons · `cc31` encoder turn · `cc32` encoder button ·
`cc33` fx I · `cc34` fx II · `cc35` shift — every one matching the documented outgoing table.
Faders **do** transmit; an earlier session that saw none simply had no fader movement.

### MIDI clock

**Zero `0xF8` ticks in ~12 minutes**, including 10 minutes of continuous hands-on use, and zero
active sensing. MIDI clock transmits continuously when enabled, independent of which control is
touched, so this is strong evidence the TX-6 does not send clock in its default configuration —
supporting `canBeClockMaster: false` (the app is always the tempo source).

Remaining caveat: some devices only emit clock while their sequencer runs, and it was not
confirmed that the TX-6's sequencer was started during these captures. The TX-6's outgoing
table lists no transport control at all, so pressing play may simply transmit nothing.

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

### It never reports its state

Per TE's docs: *"TP-7 never reports its state via MIDI. You cannot query transport, loop, or
cue states."* So `mirrorsIncomingCC` is false — there is nothing to mirror, and in `ctrl` mode
what it does send is a different map entirely.

### TP-7 playback direction and speed — CC 18, verified on hardware

`CC 18` is not "fast forward/rewind" as the official reference calls it, and not a relative
nudge. It is a **persistent bipolar speed control that must first take over the transport**.
The following was established by probing a real TP-7 in `sync` mode with a file playing.

**The engage/release behaviour is the key, and is undocumented anywhere:**

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

**Correction to [lucidyan/tp7-midi](https://github.com/lucidyan/tp7-midi):** that source states
the stop point "shifts between 60-61" during playback, with a workaround of `CC 18 = 60` plus
pitch bend `+708`. On this firmware that is wrong — 60 and 61 are simply slow *reverse* speeds,
and the "workaround" plays backwards at roughly 1x (the `+708` being a x1.09 multiplier). The
stop point stays at 64; the confusion is explained by CC 18 needing to engage first.

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

### TP-7 speed measured numerically — the sync clock is a tape-speed readout

Judging playback rate by ear failed repeatedly: offset 4 was called "≈normal speed" early on and
is actually **x0.06**, and several rounds of guess-deploy-listen converged on nothing. The fix
was to find an instrument.

**In `sync` mode the TP-7 both accepts incoming CC and transmits MIDI clock, and that clock is
derived from tape speed.** So counting `0xF8` ticks per second measures playback rate directly.
`44.0 ticks/s = 110 BPM = 1x`, established from three independent forward baselines.

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
- Never send `0xFC` twice. A stop while already stopped rewinds to zero; an early version of the
  test tool did this and produced a spurious "31s -> 0s" jump that looked like a scrub.
- Sample for at least ~10 s. One-second windows alternate between ~43.8 and ~44.8 as ticks land
  on window boundaries; only the average is meaningful.

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

## Open questions — answer on hardware

- [ ] Do the pinned FX-bus channels (ch 8/9) actually land?
- [ ] Does the TX-6 *follow* incoming MIDI clock, even though it does not send it?
- [ ] How badly does TX-6 CC 46 desync when the transport is started from the device panel?
- [ ] Is TX-6 program change on ch 7 usable for scene slots?
- [ ] Exact BLE peripheral names for TX-6 and TP-7 — or whether they do BLE MIDI at all.
- [ ] A TP-7 CC 18 ff/rewind step size that feels right (currently ±8).
