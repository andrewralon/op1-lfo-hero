# CLAUDE.md

Custom MIDI LFOs (low-frequency oscillators) for the Teenage Engineering OP-1 Field. Generates beat-synced automation curves for per-track volume/pan/mute/FX and master FX/compressor, plus MIDI clock master/slave sync with the OP-1.

## Three implementations in this repo

| Path | What it is | Status |
|---|---|---|
| `ios/` | SwiftUI iOS app | **Main deliverable** — active development |
| `src/` | PyQt6 desktop app (macOS/Windows/Linux) | Reference — original implementation, not actively extended |
| `src/web/` | Mobile remote-control web UI, served by `src/server.py` over local WiFi | Companion to the Python app, not standalone |

Build new features in `ios/` first. Treat `src/` as a reference for protocol/algorithm details (MIDI CC mapping, LFO curve math, clock smoothing) — only modify it if explicitly asked to.

## iOS app structure (`ios/Sources/`)

- `Engine/` — no UI dependencies; MIDI transport + automation logic
  - `AppState.swift` — `@MainActor` ObservableObject root; owns all engine objects, wires their callbacks into `@Published` UI state
  - `MidiRouter.swift` — routes to USB when connected, falls back to BLE; aggregates callbacks from both transports
  - `USBMidi.swift` / `BLEMidi.swift` — CoreMIDI / CoreBluetooth transports; each auto-detects and auto-connects to an OP-1
  - `ClockEngine.swift` — MIDI clock master (generates 24 PPQN via `DispatchSourceTimer`) or slave (smooths incoming clock ticks into a BPM reading)
  - `AutomationEngine.swift` — evaluates LFO waveforms per clock tick, dispatches CC messages via `Controller`
  - `Controller.swift` — turns UI actions into MIDI CC messages
  - `Models.swift` — `LfoWave`, `Parameter`, `LfoClip`, PPQN/rate constants, MIDI↔UI value conversion (see OP-1 MIDI scale note below)
- `UI/` — SwiftUI views, one file per major control: `TrackStripView`, `PanKnobView`, `VolumeFaderView`, `TransportView`, `LFOPanelView`, `WaveformView`, `SplashScreenView`, plus `Theme.swift` for shared colors/styles
- `ios/UITests/` — XCUITest target

Build/run: open `ios/op1-lfo-hero.xcodeproj` in Xcode, select a simulator or device, Cmd+R.

## Python desktop app (`src/`)

```bash
source venv/bin/activate
python -m src.app
```

- `ui.py` — PyQt6 dark-theme UI (single file)
- `automation.py`, `clock.py`, `controller.py` — same role as the iOS `Engine/` files
- `server.py` — FastAPI/uvicorn WebSocket server backing `src/web/index.html` (mobile remote control)
- `app.py` — entry point; port auto-detection; CLI flags (`--debug`, `--no-device`)

## Visual style (shared across iOS and Python apps)

- Track colors are fixed and identical in both apps:
  - Track 1 = `#4477bb` (steel blue)
  - Track 2 = `#bb9933` (ochre)
  - Track 3 = `#848c94` (blue-gray)
  - Track 4 = `#ff6a00` (orange)
- Dark theme throughout — near-black backgrounds (iOS `Theme.swift`: `#111111` / `#1a1a1a` / `#2a2a2a`, with `#454545` reserved for borders that need more contrast)
- **All UI text is lowercase** — labels, button text, status messages (e.g. "scanning…", "no device found", "tempo mode:", window title "op1 lfo hero"). Match this in any new strings.
- Green (`#4ec94e`-ish) marks active/centered/selected state (e.g. pan knob indicator is green at dead-center, white/text-colored off-center).

## iOS UI scaling (`LayoutMetrics`)

All iOS dimensions are derived from a single `LayoutMetrics` struct defined at the top of `ContentView.swift`. **Never hardcode a point value in a leaf view.** Always add a property to `LayoutMetrics` and read it via `@Environment(\.metrics)`.

### Two-tier model

**Tier 1 — structural:** how the screen is divided into zones. Derived directly from `geo.size`.
- `tracksH` — height of the mixer row
- `transportColW` — width of the transport column (landscape only)
- `trackColW` — width of one track strip (`mixerWidth / 4`)
- `lfoH` — height of the LFO panel (remainder after tracks + transport + status bar)

**Tier 2 — content:** how elements fill their zone. Derived from Tier 1, never from `geo.size`.
- Track strip: `muteLabelFont`, `panKnobPortrait`, `panKnobLandscape`, `panHPad`, …
- LFO panel: `toggleBtnSize`, `scrubH`, `iconSize`, `pickerFont`, `waveformH`, …

### How to tune a value

Change one fraction in `LayoutMetrics` — it updates every device size at once. Common adjustments:

| Feels wrong | Property to change | Direction |
|---|---|---|
| Mute button text too small/big | `muteLabelFont` | adjust `0.09` multiplier |
| Pan knob too small in portrait | `panKnobPortrait` | adjust `0.30` (tracksH fraction) |
| Track/master toggle buttons too small | `toggleBtnSize` | adjust `0.11` (lfoH fraction) |
| Icons in control row too small | `iconSize` | adjust `0.06` |
| ScrubValue / picker boxes too short | `scrubH` | adjust `0.08` |
| Waveform too short in portrait | `waveformH` | adjust `0.18` |
| Action column (repeat/1x/trash) too narrow | `actionColW` | adjust `1.4` (toggleBtnSize multiplier) |

### Rules

- The only allowed hardcoded point value is `max(..., 44)` to enforce Apple's minimum touch target. Everything else is a fraction.
- `isLandscape` and `isIpad` are the only boolean branches permitted — use them to choose which Tier 1 formula applies, not to pick between two pixel values.
- New views: add needed Tier 2 properties to `LayoutMetrics`, then read `@Environment(\.metrics) private var m` in the view. Do not reach for `@Environment(\.horizontalSizeClass)` or `isPad ? x : y`.

## Notes workflow (`notes/`)

- `FEATURES.md` — iOS backlog: `## To fix` / `## Later (or not possible)` / `## Done`, each item prefixed with a severity (`HIGH`/`MED`/`LOW`)
- `FEATURES_PYTHON.md` — same structure, for the Python app
- `RESEARCH.md` — empirical MIDI protocol findings (e.g. why certain OP-1 tempo modes are indistinguishable over MIDI)

When a task originates from one of these files, check the box (`- [ ]` → `- [x]`) and move the item under `## Done` as part of the same change — don't leave completed items unchecked.

## Known iOS crash: List inside sheet on iPad

Never use `List` inside a `NavigationStack` inside a `.sheet` (or `.fullScreenCover`). On iPad, the UIKit focus system recursively traverses `UITableView` focus containers and hits an assertion, crashing the app (and sometimes Springboard). This has bitten us twice.

**Fix:** replace `List { ... }` with `ScrollView { VStack { ... } }`. Style section headers manually with `Text(...).font(.subheadline)` and `Divider()`. See `HelpView`, `DevicePickerView`, and `SettingsView` in `ContentView.swift` for examples.

## Screenshots and simulator testing

All testing/Xcode/simulator screenshots go in `/tmp/claude-ss/`. Create the directory if it doesn't exist (`mkdir -p /tmp/claude-ss`) before writing. Use this path in `xcrun simctl io` commands, UITest screenshot saves, and any other screenshot output.

### UITest patterns

Use XCUITest (not `cliclick` coordinate math) to drive the simulator — accessibility identifiers make taps reliable across device sizes.

**Known accessibility identifiers:**
- `helpButton` — opens HelpView sheet
- `settingsButton` — opens SettingsView sheet

**Run specific tests from the command line:**
```bash
cd ios
xcodebuild test \
  -project op1-lfo-hero.xcodeproj \
  -scheme op1-lfo-hero \
  -destination 'id=<simulator-udid>' \
  -only-testing:op1-lfo-heroUITests/HelpSettingsUITests/testHelpModalOpensAndDismisses
```

**Taking screenshots inside a UITest:**
```swift
let screenshot = XCUIScreen.main.screenshot()
try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-ss/my_screen.png"))
```

**Find the booted simulator UDID:**
```bash
xcrun simctl list devices available | grep Booted
# or pick any available iPhone:
xcrun simctl list devices available | grep iPhone
```

## MIDI reference

CC mapping, transport messages, and the OP-1 MIDI spec link are documented in `README.md` — refer there rather than duplicating the tables here.
