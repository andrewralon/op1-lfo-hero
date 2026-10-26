# Changelog

High-level notes for each App Store version of the iOS app, newest first. The store copy is
shorter and lowercase (`ios/fastlane/metadata/en-US/release_notes.txt`); this is the fuller record. Add the entry when a release is being prepared
(`SHIPPING.md` section 4), and fill in the date when it goes live.

Detail lives in the git history (`git log v1.0.0..v1.1.0`) and in `FEATURES.md` under `## Done`.
Anything marked **not yet on a device** has unit or UI test coverage but has not been seen to work
on the hardware; `HARDWARE_CHECKLIST.md` says how to check.

## 1.1.1 — not yet released

PRs [#4](https://github.com/andrewralon/op1-lfo-hero/pull/4) (OP-1 controls) and
[#5](https://github.com/andrewralon/op1-lfo-hero/pull/5) (waves and pickers), shipped together.

**New**
- **Slope and hold waves**, meant for one-shot use. Slope is a single ramp (inverted, it ramps
  down); hold snaps to the centre value and stays.
- **OP-1 Field master controls:** record level, master EQ (low / mid / high), sustain and pitch bend,
  offered under the master (m) target. Pitch bend is 14-bit, so it sweeps smoothly and returns to
  the exact centre.
- **Picker rework:** tap the parameter, wave or speed box to pick from a list; drag across the five
  boxes to scrub them. Lists open beside their box and are sized to their labels.
- **Waveform view** shows the LFO you are touching or editing, otherwise every running LFO. LFOs
  with the same shape are drawn in alternating stripes.
- **Device setup steps** for the OP-1 Field, TX-6 and TP-7 come first in help, above the tutorial.

**Changed**
- Free rates **f1–f17 now run slowest to fastest** (f1 was the fastest). A saved chip keeps its
  speed; its label changes.
- Help and settings share one scaffold, with larger titles on iPhone and a tighter header.
- The tutorial has a close ✕ instead of "skip", "next" on its first step, an `n/total` counter, and
  "later" restarts it from step 1.
- Status line reads "tap to connect a device" when no device is found.
- "live bend" is now "pitch bend"; picker lists always show a scroll bar.

**Fixed**
- A loop chip and a 1x chip with the same settings can both exist.
- A cancelled pending Bluetooth reconnect no longer clears the connection that replaced it (the
  "phantom" OP-1 row in the device picker).
- Editing a chip no longer loses precision, and switching parameter recentres.

## 1.1.0 — 2026-10-19

TX-6 and TP-7 support alongside the OP-1 Field.

**New**
- **TX-6 and TP-7:** six-track layouts, a data-only device profile per device, auto-detection from
  the MIDI endpoint name, and a manual device picker in settings. The TP-7's tape transport
  (play, stop, scrub, prev/next) is supported; it has no pan, and its input gain sits on channels
  1–3 only.
- **First-run tutorial**, replayable from help.
- **LFOs pause with a banner** when the device sends no clock; tapping it switches to the app's
  clock.
- Every play press restarts the active LFOs; an LFO-driven press does not.
- The BPM box drives the clock continuously while you drag it; tempo maximum is 440 bpm.

**Changed**
- Steadier BPM readout over Bluetooth, timed by the sender's own timestamps.
- Bluetooth device picker and startup scan reworked; the connected device is highlighted.
- Transport routing is sticky rather than USB-priority; layout, status and routing follow one
  connection, and a new device never takes over an active one.
- Settings are stored in the keychain instead of `UserDefaults`; the 1.0 settings blob migrates.
- Default startup volume and LFO centre are 99 on every track.
- Parameters are restored when preview ends or an active chip is deleted.

**Fixed**
- TP-7 scrub was too fast from a parked tape and while rolling, forward and reverse.
- Tape prev/next nudge is relative to the real tape position.
- Status bar said "no device found" for a connected device that sends no MIDI.

## 1.0.0 — 2026-07-15

First App Store release, OP-1 Field only. A port of the original Python desktop app (the `v0.x`
tags), rebuilt as a SwiftUI app.

- Per-track (four) and master LFOs for volume, pan, mute, FX and synth/envelope parameters,
  generated as MIDI CC and beat-synced to a MIDI clock.
- Waveforms: sine, triangle, saw, square, log, exp, sweep up, sweep down and random. A tempo LFO
  is available as a target.
- Speeds: beat-synced rates with a multiplier, plus free rates f1–f17 (0.02 s to 15 s).
- Loop, one-shot and invert per chip; chip long-press to edit; preview mode.
- Clock master (the app sends clock) or slave (the OP-1 sends clock), with the OP-1's 0–99 value
  scale matched.
- MIDI over USB-C or Bluetooth, with device search, disconnect, reconnect and swap.
- Responsive layout for iPhone and iPad in both orientations; dark theme and per-track colours.
- Energy work: the clock timer and Bluetooth polling stop when nothing is connected.

## Before 1.0

`v0.0.0`–`v0.1.1` (June 2026) are the PyQt6 desktop app in `src/` and its web remote: colored
waveforms, multiple LFOs per track, Bluetooth MIDI, master FX parameters, the tempo LFO. It is the
reference implementation and is not actively extended.
