# LFO Hero — iOS App

Native SwiftUI iOS app. Connects to the OP-1 Field via **USB-C** or **Bluetooth LE MIDI** — no paid Apple Developer account required.

## What it does

| Feature | Detail |
|---------|--------|
| USB MIDI | Wired USB-C connection; auto-detects OP-1 Field by name via CoreMIDI |
| BLE MIDI | Wireless Bluetooth LE MIDI via CoreBluetooth |
| Transport | Play / Stop / ← tape prev / → tape next |
| Clock master | Generates 24 PPQN MIDI clock; toggle between master / slave |
| BPM | Displayed, drag-to-scrub, double-tap for keyboard entry; auto-tracked when OP-1 is clock master |
| Track strips | Volume fader (red fill, 0-99), pan knob (L/R), mute button — all 4 tracks |
| LFO panel | All 9 wave shapes, all parameters (volume, pan, mute, tempo, FX 1-4, LFO 1-4), per-track + master targets, loop / one-shot, invert |
| Background | `UIBackgroundModes: audio` keeps MIDI running when screen is locked |

---

## Repo layout

```
ios/
  op1-lfo-hero.xcodeproj/   ← open this in Xcode
  Sources/                  ← all Swift source files (edit here)
    Engine/                 ← AppState, ClockEngine, BLEMidi, USBMidi, MidiRouter, …
    UI/                     ← SwiftUI views
    LFOHeroApp.swift
  Assets.xcassets/
  Info.plist                ← UIBackgroundModes: audio (merged with auto-generated plist)
```

All source files live in the repo — no separate Xcode directory, no rsync step. Edit Swift files directly in `ios/Sources/`, then build in Xcode.

---

## Setup (one time)

### 1 — Open the Xcode project

Open `ios/op1-lfo-hero.xcodeproj` in Xcode. Everything is already configured.

### 2 — Free provisioning (no paid account)

1. Plug your iPhone into the Mac via USB
2. In Xcode, select your iPhone as the run destination (top toolbar)
3. Open **LFOHero target → Signing & Capabilities**
4. Set **Team** to your Apple ID (add it via Xcode → Settings → Accounts if needed)
5. Set **Bundle Identifier** to something that has never been used (e.g. `com.yourfirstname.lfohero`)
6. Xcode will say "Provisioning profile created" — this is your free 7-day profile

Hit **▶ Run** (⌘R). Xcode builds and installs.

### 5 — Trust the app on your iPhone

The first time:
1. On iPhone: **Settings → General → VPN & Device Management**
2. Tap your Apple ID under "Developer App"
3. Tap **Trust "your@email.com"** → Trust

### 6 — Re-signing after 7 days

Free profiles expire after 7 days. When the app stops launching:

1. Plug in iPhone
2. Open Xcode → hit ▶ Run again

That's it — Xcode re-signs and re-installs automatically.

---

## Connecting to the OP-1

### USB (recommended)
1. Plug the OP-1 into the iPhone via USB-C
2. Open LFO Hero — it detects the OP-1 automatically
3. Status bar shows **OP-1 Field (usb)**

### Bluetooth
1. On the OP-1: **COM → MIDI → BLUETOOTH: ON**
2. Open LFO Hero — it scans automatically
3. Status bar shows **● OP-1 Field (bt)**
4. If it doesn't auto-connect, tap the status bar to open the device picker

### Clock modes

| Mode | Use when |
|------|----------|
| **mstr** (master) | App generates clock → OP-1 in MIDI Sync mode |
| **slv** (slave) | OP-1 generates clock → OP-1 in Beat Match mode |

Toggle with the metronome button in the transport column. The app starts in master mode so the transport buttons work immediately.

---

## MIDI reference (same as desktop app)

| CC | Function | Channel |
|----|----------|---------|
| 7 | Volume | 1-4 (tracks) |
| 9 | Mute | 1-4 |
| 10 | Pan | 1-4 |
| 54-57 | Patch FX 1-4 | 1-4 |
| 58-61 | Patch LFO 1-4 | 1-4 |
| 70-73 | Master FX 1-4 | 1 |
| 74-77 | Master comp 1-4 | 1 |
| 79 | Octave shift | 1 |
| 82 | Tape prev bar | 1 |
| 83 | Tape next bar | 1 |

Transport: 0xF8 clock, 0xFA start, 0xFB continue, 0xFC stop, 0xF2 song position
