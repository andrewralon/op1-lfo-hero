# TP-7: our findings vs `lucidyan/tp7-midi`

Cross-reference between this repo's hardware measurements ([RESEARCH.md](RESEARCH.md)) and
[lucidyan/tp7-midi](https://github.com/lucidyan/tp7-midi), a browser-based TP-7 controller with a
detailed experimental spec.

| | |
|---|---|
| Their commit compared | `f3af600` (2026-01-26) |
| Their stated firmware | **1.1.11** (2026-01-24 doc date; 1.1.11 released 2025-12-23) |
| Our firmware | **1.1.11** — same version, confirmed. Every disagreement below is a real one, not a version skew |
| Their sources | `MIDI_SPEC.md`, `docs/MANUAL.md` (full TE manual transcription), `app.js` |

Their spec is good: independently derived, honest about what is a guess, and it transcribes the
official manual including two pages we had never read. It is **not** a superset of ours and we are
not a superset of theirs. **All three numeric disagreements are now resolved on hardware — D1 and
D2 in their favor (tests 1, 2), D4 in ours (test 4).** D5, a framing question rather than a
numeric disagreement, is also resolved (test 3: our own "engage" model was over-built).

---

## The headline

**✅ CONFIRMED ON HARDWARE (2026-09-06): our `deadZone: 4` is wrong when the tape is stopped, by
exactly 1x.** See test 1 below for the measurement — `CC 18 = 68` held for 10.0s from a parked
tape moved the position counter at x1.04-1.05 (their prediction: 1x; ours: ~0.06x, the stall
point). Not yet fixed in code — see [FIELD_DEVICE_SUPPORT.md](FIELD_DEVICE_SUPPORT.md).

Both projects measured the same slope for CC 18 — 4 MIDI units per 1x of playback speed. We
differ on the intercept:

| | 1x forward | 1x reverse | stop |
|---|---|---|---|
| them (`app.js:243`, `speed = (value - 64) / 4`) | 68 | 60 | 64 |
| us (`deadZone 4 + unitSpeed 4`) | 71.5 (unreachable; app uses 72) | 56.5 (app uses 56) | 64 |

The gap is 3.76 units — one whole 1x. And [RESEARCH.md:629-632](RESEARCH.md) already says why:

> Offset 3.76 is not a motor threshold, it is where -44 exactly **cancels** forward playback. That
> is why offset 4 looked like a stall: it is a null point, not a limit. The affine formula the app
> uses is therefore correct *only while the device is internally playing forward*.

Our offset table was measured **in `sync` mode with a file playing**
([RESEARCH.md:469](RESEARCH.md)), i.e. with the internal transport contributing +44 ticks/s. Their
table describes the tape **stopped**. Under our own additive model both are correct — and the
constant we baked into the profile belongs to the *playing* case only.

**Consequence in shipped code.** `ClockEngine.swift:503-515` applies `deadZone` unconditionally:

```swift
let offset = deadZone + Int((Double(unitSpeed) * transportSpeed).rounded())
sendCC(ch: ch, cc: cc, val: center + direction * max(1, offset))
```

So from a **stopped** tape, `transportSpeed = 2.0` sends CC 18 = 76, which their model reads as
**+3x, not 2x**. Momentary scrub starts at 72 = **+2x**, not the `scrubStartSpeed = 1.0` it
advertises. Every prev/next/scrub taken from a parked tape is one whole multiple fast. Test 1
settles it.

---

## Where we agree (no test needed)

Independently derived on both sides, same answer:

- CC map: `7` mix volume (ch 1-6), `9` input gain, `14` rec arm, `16` cue rec mode, `17` loop,
  `18` transport, `120` mix mute (ch 1-6); notes = cue markers; pitch bend = playback speed
- On/off encoding: 0-63 off, 64-127 on
- Controller-mode transmit map: CC 20-27 buttons, CC 30 wheel (relative two's complement),
  rocker = pitch bend, all on channel 1
- Input gain range **0 to +42 dB** (we additionally measured it linear — see below)
- CC 17 loop is a **state machine**: `in` (1) before `out` (2); `out` alone is silently discarded
- The device **never reports state** — no feedback, no query, host state is local-only
- Controller mode is **mutually exclusive** with receiving MIDI
- Pitch bend has **no effect with the transport stopped** (their "only applies during playback",
  our [RESEARCH.md:591-593](RESEARCH.md))
- Pitch bend is invisible on the device's `SPD` display and persists across stop/play
- CC 18 moves the tape **whether or not** the transport is playing
- Slope of CC 18: **4 MIDI units per 1x**
- 6 stereo tracks on MIDI channels 1-6

---

## What only we have (candidates to contribute upstream)

Their app contains **no real-time messages at all** — `grep` for `0xF8/0xFA/0xFB/0xFC` in
`app.js` returns nothing. Their entire transport is CC 18. That single gap explains most of this
list.

| # | Our finding | Where | Their spec says |
|---|---|---|---|
| 1 | **TP-7 transmits MIDI clock** in `sync` mode, derived from tape speed; 44.0 ticks/s = 110 BPM = 1x | [RESEARCH.md:539-550](RESEARCH.md) | nothing — no clock anywhere |
| 2 | **Real-time transport drives the tape**: `0xFB` plays/resumes, `0xFC` stops holding position, `0xFA` rewinds and plays | [RESEARCH.md:526-533](RESEARCH.md) | nothing |
| 3 | **A second `0xFC` rewinds to zero** — the device implements double-stop itself | [RESEARCH.md:657-658](RESEARCH.md) | nothing |
| 4 | **Recording over MIDI works**: `CC 14 = 127`, then `0xFB` → a real 4-second recording | [RESEARCH.md:848-854](RESEARCH.md) | gotcha #10: *"Recording via MIDI is useless"* — **refuted** |
| 5 | **Four `midi` modes** (`off`/`cue`/`sync`/`ctrl`) gate everything; `ctrl` blocks CC *and* real-time | [RESEARCH.md:421-449](RESEARCH.md) | knows only "Controller Mode vs not" |
| 6 | **CC 28 = the `mode` button** — undocumented, absent from TE's own table | [RESEARCH.md:677-679](RESEARCH.md) | omits it (copies TE's 8-button table) |
| 7 | **CC 9 addresses the three input jacks**, upstream of the mix — proven by patching audio into jack 1 | [RESEARCH.md:752-757](RESEARCH.md) | "input gain per channel" |
| 8 | **Gain is linear in dB**: `dB = midi × 42/127`, ~0.33 dB/step, 9 measured points | [RESEARCH.md:723-746](RESEARCH.md) | range only |
| 9 | **CC 18 is additive** on the device's own direction — reverse + CC 18 gives ~3x backwards | [RESEARCH.md:611-651](RESEARCH.md) | describes the symptom (two modes), not the mechanism |
| 10 | **Direction resync**: `CC 18 = 64`, `0xFC`, `0xFB` forces a known forward state, no settling delay | [RESEARCH.md:645-648](RESEARCH.md) | nothing |
| 11 | **Pitch bend is a signed velocity offset**, not a multiplier — its sense *flips* in reverse | [RESEARCH.md:577-589](RESEARCH.md) | asymmetric multiplier formula |
| 12 | **Numeric CC 18 calibration**: 11.69 ticks/s per unit, five measured points | [RESEARCH.md:552-566](RESEARCH.md) | integer table, no measurement |
| 13 | **Silent at rest**; in `ctrl` a playing reel emits CC 30 at ~57 msg/s | [RESEARCH.md:696-715](RESEARCH.md) | nothing |
| 14 | **Record arm differs from the button**: CC 14 does not stop the reel; `0xFC` cancels the arm | [RESEARCH.md:839-843](RESEARCH.md) | nothing |
| 15 | **The outgoing clock rate is a TEMPO readout, not a tape-speed readout, and that tempo is genuine per-file metadata.** MIDI clock counts beats; different memos tick at different rates purely because they carry different tempo settings, not because playback speed differs — confirmed blind on two memos (106 and 120 BPM, matched to 0.03 BPM). Also confirmed the tempo is fixed per-file, not a live global dial: changing the device's current tempo setting to 90 BPM had zero effect on an already-recorded memo's clock output | [RESEARCH.md](RESEARCH.md), added 2026-09-07 | nothing — neither their spec nor the manual mentions tempo/BPM in connection with outgoing clock at all |

---

## What only they have (we must test)

| # | Their claim | Source | Why it matters to us |
|---|---|---|---|
| A | **Mixer resets on track change.** A cue trigger or loop crossing to another track resets all volumes to 100% and clears all mutes | `MIDI_SPEC.md:251-259`, gotcha #11 | An LFO on `tp7.vol` would silently fight the device. We may need to re-send mixer state after any cue/loop event. **Never tested here.** |
| B | **MIDI-CUE must be enabled in settings**, and per TE's own manual: *"hold record and send MIDI notes to set cue points. Send same notes without record to trigger the cues"* | `docs/MANUAL.md:1369` | This very likely explains our "cue subsystem is inert" result — we sent CC 16 and notes but **never held the physical record button**, and may not have had the setting on |
| C | **Cue triggering puts CC 18 into "playback mode"** — same as pressing play | `MIDI_SPEC.md:89-96` | Consistent with our additive model (a cue starts the transport), but untested |
| D | ✅ CONFIRMED 2026-09-06 — **In/out points cannot be changed while a loop is active**; only `0` exits | `MIDI_SPEC.md:66-67` | Exactly right — see test 7. Bonus finding: CC 17 only works with the device's LOOP screen showing |
| E | **Only tracks 1-3 reach USB audio**; all 6 mix internally | `MIDI_SPEC.md:246-249` | Not a MIDI fact, but worth knowing before someone reports "tracks 4-6 do nothing" |
| F | ✅ TESTED 2026-09-06 — CC 18 extremes: `0` = -16x, `127` = +15.75x | `app.js:243` comment | **Both wrong, by the same ~order of magnitude.** Measured x248.5 (127, 10s hold) and x278.9 (0, 10s hold) — roughly 15x higher than either prediction. See test 9 below; likely a distinct fast-wind regime neither project had measured |
| G | Pitch bend negative branch: `1 + (p/8192) × 0.75` → **x0.25** at -8192 | `MIDI_SPEC.md:161-172` | We measured **x0.54**. Direct numeric disagreement — see D4 |
| H | No MIDI access to the on-screen `SPD` varispeed | `MIDI_SPEC.md:136-139` | Confirms bend and `SPD` are separate; we should check whether they multiply |
| I | Firmware pinned at **1.1.11**; 1.1.10 added *"enable reel, rocker and reverse playback in mixdown mode"* | `docs/FIRMWARE_CHANGELOG.md:22-27` | Rocker behaviour changed in a recent firmware. If our unit is older, some disagreements are firmware differences, not errors |

---

## Direct disagreements

### D1 — Where 1x lives on CC 18 *(most important; test 1)*

Covered in the headline above. Both models share a slope of 4 units/1x and differ by one 1x of
intercept. **Reconcilable:** ours is the playing case, theirs is the stopped case. If test 1
confirms it, `deadZone` stops being a device constant and becomes a function of transport state.

### D2 — ✅ RESOLVED 2026-09-06 — The `+708` stop workaround, our correction was wrong

[RESEARCH.md:508-512](RESEARCH.md) used to read (now retracted):

> **Correction to lucidyan/tp7-midi:** that source states the stop point "shifts between 60-61"
> during playback, with a workaround of `CC 18 = 60` plus pitch bend `+708`. On this firmware that
> is wrong — 60 and 61 are simply slow *reverse* speeds, and the "workaround" plays backwards at
> roughly 1x (the `+708` being a x1.09 multiplier). The stop point stays at 64.

**Confirmed on hardware, `cc18map TP-7 playing`, watching the reel directly (not inferring
direction from magnitude):**

| send | predicted (additive model) | measured | direction observed |
|---|---|---|---|
| baseline, playing forward | ~44 ticks/s | 42.3 (x0.96) | forward, normal |
| `CC 18 = 61` | ~8.9 ticks/s | 8.6 (x0.20) | **forward**, very slow |
| `CC 18 = 60` | ~2.8 ticks/s | 2.6 (x0.06) | **reverse**, very slow |
| `CC 18 = 60` + bend `8900` | ~0.7 ticks/s | **0.00** | stopped |
| released (64, bend centred) | ~44 | 42.5 | forward, normal |

The direction genuinely **flips** between 61 and 60 — the tape was watched doing it, not just
measured. That is decisive: the true null sits **between 60 and 61 while playing**, exactly as
`lucidyan/tp7-midi` found, and a bend compensation (`+708` in their signed encoding, `8900`
unsigned in ours — the same value) lands on it. Their number was never a magic constant, it falls
straight out of the additive model we derived independently.

Where we *are* right: "the stop point stays at 64" is true **when the tape is stopped** — a
different regime, resolved separately by test 1's `deadZone` finding above. Our published
correction conflated the two regimes and called their playing-mode finding wrong using
stopped-mode intuition. `RESEARCH.md` now carries the retraction in place of the original
correction.

### D3 — "Recording via MIDI is useless"

Their gotcha #10: *"CC14 arms recording BUT you can't control playback in record mode via MIDI
(only rocker emulation). Use physical controls for recording."*

**We are right and they are wrong**, for a reason they had no way to find: they never send
`0xFB`. Our sequence `CC 14 = 127` → `0xFB` → `0xFC` produced a verified 4-second recording from a
live input ([RESEARCH.md:848-854](RESEARCH.md)) and is shipped as `tp7.recSeq`. Worth reporting
upstream — it turns a documented dead end into a working feature.

### D4 — ✅ RESOLVED IN OUR FAVOR 2026-09-06 — Pitch bend negative branch

The one disagreement in this whole document where re-measurement sided with **us**, not them.
`./cc18map TP-7 bend`, five-point sweep both directions:

| bend | them | us (orig. 3pt) | measured 2026-09-06 |
|---|---|---|---|
| -8192 | x0.25 | x0.54 | **x0.48** |
| -4096 | x0.63 | — | x0.66 |
| 0 / centre | x1.00 | x1.00 | x0.96 |
| +4096 | x1.50 | — | x1.39 |
| +8191 | x2.00 | x2.14 | **x1.93** |

Measured x0.48 sits far closer to our x0.54 than to their formula's x0.25 — their `× 0.75`
coefficient looks like it was chosen to make the range end exactly at 0.25 rather than measured.
This re-measurement also fixed an **internal** inconsistency: RESEARCH.md's two conflicting
figures at full positive bend (a table saying x2.14, text saying "+40 ticks/s" which implies
x1.91) are now settled — measured x1.93 confirms the "+40" figure and the x2.14 table entry was
corrected.

The reverse sense-flip (bend up *slows* a reversing tape) was reproduced numerically
(x1.51/x1.08/x0.24 vs the original x1.38/x1.00/x0.22) and confirmed independently by the operator
watching and listening through the whole sequence with no numbers in front of them — forward
half-speed → normal → fast → faster, then fast reverse → normal reverse → slow reverse → stop,
matching the table exactly including the flip itself.

**Both extremes re-verified by position counter** (`cc18map TP-7 bendhold <v> 10`, exact elapsed
time reported, not nominal), a second measurement method independent of the clock:

| bend | clock (10.005s) | counter, operator-read | theirs |
|---|---|---|---|
| -8192 | x0.484 | **~x0.50** | x0.25 |
| +8191 | x1.924 | **~x2.00** | x2.00 |

Negative branch: two independent methods now agree closely (~x0.48-0.50), roughly double their
predicted x0.25 — as decisive as this gets. Positive branch: close to both models either way, and
confirmed clean (no reversal or other anomaly) at the literal maximum bend value, which was worth
checking given it sits at a 14-bit wraparound point.

### D5 — ✅ RESOLVED 2026-09-06 — "CC 18 must engage first" was our own over-modelling

[RESEARCH.md:471-484](RESEARCH.md) described an engage/release protocol: 64 does nothing until
some other value has "taken control". `cc18map TP-7 engage` confirmed the simpler additive
explanation instead: playing forward at baseline, `64` x3 → `70` → `64` again measured
**42.5 → 42.3 → 102.1 → 42.4 ticks/s** — a clean return to baseline both times, no stop, no
re-engage transition. **64 simply adds zero velocity.** A tape rolling at +44 with zero added
keeps rolling; that was never a device refusing to listen.

`RESEARCH.md` now marks the engage/release framing retired, keeping the original four points for
context only. The `stop` op still sends `CC 18 = 64` before `0xFC`, which stays correct for a
different reason: it removes any standing offset before the real-time stop.

### D6 — Cue markers: inert (us) vs working (them)

We tested CC 16 and note-on in `off`, `cue` and `sync` modes and saw nothing at all
([RESEARCH.md:786-812](RESEARCH.md)). They say cues work with MIDI-CUE enabled, and TE's manual
adds a step we never performed: **hold the physical record button while sending the notes**. Most
likely our negative result is a missing precondition, not a device limitation. Test 6.

### D7 — Mute polarity is asserted twice in this repo, verified once

**✅ RESOLVED 2026-09-06.** `DeviceProfile.swift:29-31` said TP-7 mute polarity was
**unverified**; `FIELD_DEVICE_SUPPORT.md:79` said "Mute `CC 120` absolute, 127 = muted" as if
confirmed. Test 8 closes the gap in favor of the latter — `127` mutes, repeated `127` stays muted
(not a toggle), `0` unmutes, and three rapid mute/unmute cycles 2s apart tracked cleanly. The
source comment is updated. See test 8 below for the mid-test detour into a device-hang gotcha.

---

## Hardware test plan

All tests need a TP-7 in **`sync` mode** (transmits clock, accepts CC) unless stated. Instruments
live in `tools/midi/` — build with `./build.sh`, and run `./mididiag` first (stale endpoints look
exactly like a silent device). `./clockrate` is the measuring stick: **44.0 ticks/s = 1x**, and
the clock is **unsigned**, so direction always needs ears or the display.

Sample ≥10 s per point; one-second windows alternate 43.8/44.8. Never send `0xFC` twice — it
rewinds. Return pitch bend to 8192 when finished or every later measurement is silently skewed.

### 1. ✅ CONFIRMED (2026-09-06, firmware 1.1.11) — CC 18 from a stopped tape, the `deadZone` question
Decided D1 and a live bug. **Theirs was right.**

The sync clock turned out to be blind to CC-18-driven motion from a parked tape (0.00 ticks/s
throughout, even with the reel visibly and audibly turning at speed) — a new instrument
limitation beyond the known "no clock while stopped," so `cc18map`'s clock-availability probe
correctly declined to guess and fell back to reading the position counter directly.

**Measured:** `CC 18 = 68` held for exactly 10.0s moved the counter from **11:36 to
~11:46.4-46.5 — x1.04-1.05, i.e. 1x**, matching their formula (`(68-64)/4 = 1x`) and the operator's
own real-time read ("played at what looked and sounded like normal speed"). Our model predicted
~0.06x (the offset-4 stall point) — a few tenths of a second of travel, not ten seconds' worth.

Separately, replaying the app's own current constants from a parked tape (`cc18map TP-7 control`)
and judging by ear: `CC 18 = 72` (app believes 1x) was "faster than normal," `76` (app believes
2x) "pretty fast," `124` (app believes 14x) "super fast" — consistent with their formula (2x, 3x,
15x), each one whole multiple past what the app currently claims.

**Consequence:** `deadZone` is not a device constant. It is 0 when the tape is parked and ~4 only
while the internal transport is already rolling forward (our earlier measurements, which were all
taken with a file playing). `.directionalTransport` in `ClockEngine.swift:503-515` applies
`deadZone` unconditionally, so **every prev/next/scrub sent from a parked tape runs one whole 1x
too fast today.** Fix touches `ClockEngine.swift:503-515`, the `deadZone: 4` literals at
`DeviceProfiles.swift:263-268`, and the golden byte tests in `NewDeviceProfileTests.swift:471-518`,
which currently assert the wrong (unconditional) values and must be re-derived, not patched to
match. Full writeup: [RESEARCH.md](RESEARCH.md).

### 2. ✅ CONFIRMED 2026-09-06 — The stop point during playback, our correction retracted
Decided D2. `./cc18map TP-7 playing`, direction confirmed by watching the reel:

| send | predicted | measured |
|---|---|---|
| CC 18 = 61 | ~8.9 ticks/s, forward | 8.6 (x0.20), **forward** |
| CC 18 = 60 | ~2.8 ticks/s, reverse | 2.6 (x0.06), **reverse** (direction flip observed directly) |
| CC 18 = 60 + bend 8900 (`E0 44 45`) | ~0.7 ticks/s, stopped | **0.00** |
| CC 18 = 64 | back to ~44 forward | 42.5 |

All four matched, including the direction flip watched live on the device. `RESEARCH.md:508-512`
is rewritten from a correction into a retraction — our published claim that
`lucidyan/tp7-midi`'s `+708` workaround was wrong turned out to be our own error.

### 3. ✅ CONFIRMED 2026-09-06 — Does CC 18 "engage", or does 64 just add zero?
Decided D5. **Additive.** `./cc18map TP-7 engage`: baseline 42.5, after `64` x3 → 42.3, after
`70` → 102.1 (~2.4x baseline — confirmed independently by the operator watching reel, audio, and
counter all agree at "roughly twice, not less than twice"), back to `64` → 42.4 — a clean return
to baseline forward speed both times, never a stop. Matches
[RESEARCH.md:634-639](RESEARCH.md)'s equivalent reverse-direction test. The engage/release
framing is retired in RESEARCH.md.

### 4. ✅ CONFIRMED 2026-09-06 — Pitch bend curve, re-measured. Resolved in OUR favor.
Decided D4. `./cc18map TP-7 bend`:

| bend (14-bit) | signed | measured | our orig. pred. | their pred. |
|---|---|---|---|---|
| 0 | -8192 | **x0.48** | x0.54 | x0.25 |
| 4096 | -4096 | x0.66 | — | x0.63 |
| 8192 | 0 | x0.96 | x1.00 | x1.00 |
| 12288 | +4096 | x1.39 | — | x1.50 |
| 16383 | +8191 | **x1.93** | x1.91-2.14 | x2.00 |

Measured negative branch (x0.48) sits close to ours (x0.54), far from theirs (x0.25) — the one
disagreement resolved in our favor rather than theirs. Full positive (x1.93) also resolves our
own internal inconsistency in favor of "+40 ticks/s," retiring the x2.14 figure.

Reverse sweep (`CC 18 = 56` engaged) reproduced the sense-flip both numerically
(x1.51/x1.08/x0.24, close to the original x1.38/x1.00/x0.22) and by direct observation — the
operator narrated the whole sequence blind to the numbers (half-speed forward → normal → fast →
faster, then fast reverse → normal reverse → slow reverse → stop) and it matched the table exactly,
including the flip.

### 5. 🔴 Mixer reset on cue/loop track change
Decides A — the only claim of theirs that could break a shipped feature.

Requires MIDI-CUE enabled (see test 6). Set distinctive mix state: `CC 7 = 30` on ch 1,
`CC 120 = 127` on ch 2, `CC 7 = 100` on ch 3. Confirm on the display. Then:

1. Trigger a cue that jumps to a **different track** (note-on, cue rec mode off)
2. Read the mix display for every channel

Repeat with a loop that cycles across a track boundary.

**If levels reset:** the app must re-send mixer state after any cue/loop event — and since the
TP-7 reports nothing, we cannot detect the event. Options: re-send on a slow heartbeat, or
document it and keep cue/loop out of the LFO picker (both are already `lfoTargetable: false`).
Note the scope: harmless with the app as the only controller, damaging the moment the user
touches the device.

### 6. 🟠 Cue markers with the missing precondition
Decides D6 / B.

Enable **MIDI-CUE** in the device's MIDI settings menu. Then:

1. **Hold the physical record button** and send note-on 60 → expect a cue marker at the current
   position
2. Release record, send note-on 60 again → expect a jump to that cue
3. Repeat with `CC 16 = 127` instead of holding record, to see whether CC 16 is the MIDI
   equivalent of holding record (their reading) or something else
4. Note whether the cue jump **starts the transport** (test C) and whether it **resets the mixer**
   (test 5)

**If cues work:** our "cue subsystem is inert" section is a false negative from a missing
precondition and must be rewritten — and `tp7.cueRec` becomes a real feature rather than a
placeholder.

### 7. ✅ CONFIRMED 2026-09-06 — Loop immutability while active. They were right.
Decided D. `tools/midi/looptest.swift`: `CC 17 = 1`, wait 4s, `CC 17 = 2` → loop active. Then
`CC 17 = 1` again, wait, `CC 17 = 2` again, wait, `CC 17 = 0`.

**First attempt produced nothing at all** — main playback screen, `sync` mode, tape playing.
Zero display or audio change through the whole sequence. Entering the device's **LOOP screen**
(hold record) and rerunning the identical bytes worked immediately: a ~4s loop formed and cycled.
New precondition, same shape as the cue-marker/record-hold finding (item B) — CC 17 requires the
matching UI screen to be showing, undocumented anywhere.

**With the loop already cycling, resending `1` then `2` did nothing** — same length, same
position, through both resends, still looping. Only `0` released it, and playback continued past
the old out point. Matches `lucidyan/tp7-midi`'s claim exactly. Full writeup:
[RESEARCH.md](RESEARCH.md).

### 8. ✅ CONFIRMED 2026-09-06 — Mute polarity, and a device-hang detour
Decided D7. `CC 120 = 127` on ch 1 → muted. `CC 120 = 127` again → confirmed **still muted**
(absolute, not a toggle). `CC 120 = 0` → confirmed unmuted. Three rapid mute/unmute cycles, 2s
apart → tracked cleanly, no lag. `DeviceProfile.swift:29-31` updated.

**Detour that ate most of this test:** the very first attempts (a quick ad-hoc `swift script.swift`
mute test, then a volume-sweep sanity check) produced **zero effect at all**, despite `sync` mode
confirmed on the device's own screen and the endpoint confirmed online. Ruled out one variable at
a time: routed the identical bytes through the already-proven `cc18map` binary instead of the
interpreted script (added a `raw <b0> <b1> <b2>` mode to it for exactly this) — still nothing.
Rebooted the TP-7 — fixed instantly, identical bytes, identical code path. **The device itself can
silently hang and stop responding to CC, with no visible symptom and no error anywhere** — worth
remembering before spending time distrusting tooling or mode settings. Written up in
`tools/midi/README.md`'s gotchas and `notes/RESEARCH.md`.

### 9. ✅ TESTED 2026-09-06 — CC 18 extremes vs our 16x clamp. Both models wrong by ~15-19x.
Decided F. `cc18map TP-7 extremes` (short burst) then `cc18map TP-7 hold 127/0 10` (full 10s
holds), reading the position counter directly since the clock is blind here exactly as in test 1:

| test | value | held | tape moved | multiplier |
|---|---|---|---|---|
| short burst | 127 | ~4s | +7m25s | ~x99 |
| short burst | 0 | ~4s | −11m38s | ~x155 |
| 10s hold | 127 | 10.0s | +41m25s | **x248.5** |
| 10s hold | 0 | 10.0s | −46m29s | **x278.9** |

Their prediction (±15.75x) and ours (extrapolated to the same ~16x) are **both wrong by roughly
the same order of magnitude** — the only test in this whole comparison where neither source came
close. The operator watched the burst directly and confirmed a visible ~2s ramp to full speed;
correcting for that (treating ~9 of the 10s as terminal speed) puts the steady-state estimate
closer to **~x276 forward / ~x310 reverse**.

**Read this as a distinct high-speed seek/scan regime, not a continuation of the affine ffwd/
rewind curve** — that curve was calibrated entirely from offsets 3-12 near centre; nobody had
previously pushed all the way to 0/127 and measured it. Doesn't invalidate the app's
`maxScrubSpeed = 14.0` (a deliberate feel choice, not a device-capability claim), but reveals a
large unmapped speed range above where the affine model applies. Full writeup, caveats on
precision, and the physical-mechanism hypothesis (a fast-wind mode distinct from play-head-engaged
variable speed) in [RESEARCH.md](RESEARCH.md).

### 10. ✅ CONFIRMED WRONG 2026-09-06 — the TP-7 does NOT follow incoming clock
Not from their spec — this was our own `followsClock: true // UNVERIFIED`
(`DeviceProfiles.swift:278`), and `tp7.tempo` (`.virtualTempo`) is built entirely on it.

`tools/midi/clocksuppress` at three tempos, tape playing normally in `sync` mode:

| sent | target (24 PPQN) | measured before | measured while sending | moved? |
|---|---|---|---|---|
| 90 BPM | 36 ticks/s | ~51.3 | ~51.5 | no |
| 130 BPM | 52 ticks/s | ~51.5 | ~51.5 | inconclusive (coincidentally close to natural rate) |
| 60 BPM | 24 ticks/s | ~51.5 | ~51.5 | no |

The device's own outgoing clock never moved from its natural rate at any tempo, including two
unambiguously different targets (90, 60). **`followsClock` should be `false`, and `tp7.tempo`
likely does nothing audible on real hardware.** What *is* confirmed: the device keeps
transmitting while receiving our clock — not suppressed, so `ClockEngine.deviceIsRolling` stays
safe.

**Update 2026-09-07 — this now has a mechanistic explanation, not just a negative result.**
Item 15 above establishes that the outgoing rate is a readout of the loaded content's *tempo
setting*, not a live motor-speed parameter — so there was never a channel by which incoming
clock pulses could have changed it. The "~51.3-51.5, never moving" baseline in the table above
was this test's own memo/mode's tempo setting, staying exactly where a static readout should
stay. See [RESEARCH.md](RESEARCH.md) for the full mechanism. Code change
(flip the flag, decide `tp7.tempo`'s fate) deliberately not made yet — flagged for a decision.

### 11. 🟡 SPD varispeed × pitch bend
Decides H. Set the on-screen `SPD` to a non-1x value with the reel, then sweep bend and count
ticks. Multiplicative (their model) or additive-in-velocity (ours)? Also confirms bend still
leaves `SPD` unchanged on the display.

---

## Follow-ups regardless of outcome

- **Report items 1-4 and 14 upstream.** MIDI clock, real-time transport, working MIDI recording,
  the double-stop rewind and CC 28 are all missing from their spec, and #4 turns a documented
  dead end into a feature. Their repo takes issues; `notes/OUTREACH.md` has the tone to reuse.
- **Record our firmware version in RESEARCH.md** and add it to the mapper's identity step —
  `docs/mapper/` currently captures port name/manufacturer/version but not the device's own
  firmware, which is the confounder that makes two honest reports disagree.
- **Their manual transcription is a resource.** `docs/MANUAL.md` is a full accessible transcription
  of TE's guide, and pages 55-56 are the official MIDI tables. It is where the MIDI-CUE
  record-hold gesture came from.
