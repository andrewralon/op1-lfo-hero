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

## Building & testing from the command line

No need to open Xcode for a quick build or test run — useful for CI or a sanity check after editing source files.

```
# Build for the simulator
xcodebuild -project op1-lfo-hero.xcodeproj -scheme op1-lfo-hero \
  -destination 'generic/platform=iOS Simulator' build

# List available simulators (grab a UDID for the commands below)
xcrun simctl list devices available

# Boot a simulator, install, and launch
xcrun simctl boot <UDID>
xcrun simctl install <UDID> <path-to-built-.app>
xcrun simctl launch <UDID> com.andrewralon.op1-lfo-hero

# Run the UI tests against a booted simulator
xcodebuild test -project op1-lfo-hero.xcodeproj -scheme op1-lfo-hero \
  -destination 'id=<UDID>'
```

The built `.app` (for `simctl install`) lands under `DerivedData`, e.g.:
`~/Library/Developer/Xcode/DerivedData/op1-lfo-hero-*/Build/Products/Debug-iphonesimulator/op1-lfo-hero.app`

### UI tests

`ios/UITests/HelpSettingsUITests.swift` covers the help/settings modals via XCUITest — it launches the app and taps real UI elements by accessibility identifier (`helpButton`, `settingsButton`, the `done` button, etc.), not screen coordinates, so the tests keep working across layout changes. Run a single test with `-only-testing`:

```
xcodebuild test -project op1-lfo-hero.xcodeproj -scheme op1-lfo-hero \
  -destination 'id=<UDID>' \
  -only-testing:op1-lfo-heroUITests/HelpSettingsUITests/testHelpModalOpensAndDismisses
```

New UI buttons/screens should get an `.accessibilityIdentifier(...)` so they can be tested the same way.

---

## Release workflow (Fastlane)

All lanes run from `ios/` with `bundle exec fastlane <lane>`. Credentials live in `ios/fastlane/.env` (gitignored).

| Lane | What it does |
|------|--------------|
| `certs` | Syncs distribution cert + provisioning profile via `match` |
| `screenshots` | Captures App Store screenshots on a 6.7" simulator, frames them |
| `beta` | Increments build number, builds, uploads to TestFlight |
| `release` | Increments build number, builds, uploads metadata + screenshots + binary, submits for review |

### TestFlight changelog

The `beta` lane sends a tester checklist followed by the git commits since the last tag:

```
o hai beta tester!
-unless you have an op1, there's no audio
-test all UI components - do they do what you expect? slide, change, ...
-does it look good visually? is anything skewed or morphed? a non-round circle, etc
-how fast does it open? should be ~3 seconds after clicking to respond like normal. try 2-3 times pls.
-are the UI elements big enough?
-is anything weird? does anything *not* do what you expect?

- <commit subject>
- <commit subject>
...
```

Edit the checklist text in `fastlane/Fastfile` → `lane :beta`. Merge commits are excluded automatically.

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
| **app** | `app` sends clock → op1 in `midi sync` mode |
| **op1** | `op1` sends clock → op1 in `beat match` mode |

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
