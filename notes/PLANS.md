# Plans

Planning documents, newest first. Each carries its status, because a plan written before hardware
testing records what was *assumed* — not what the code does.

| plan | status |
|---|---|
| TX-6 FX I / FX II transport buttons | 🟡 **deferred** — not built; open questions below |
| Volume digits clipped in landscape | ✅ **shipped** |
| Multi-device support (OP-1 / TX-6 / TP-7) | ⚠️ **superseded** — several assumptions proved wrong; see its banner |

For what the code actually does, read these instead:

1. `ios/Sources/Engine/DeviceProfiles.swift` — the device profiles as they are
2. `RESEARCH.md` — measured hardware behaviour, including corrections to TE's own references
3. `FIELD_DEVICE_SUPPORT.md` — what is done and what is untested
4. `../tools/midi/` — the probes that produced the measurements

---

# TX-6 FX I / FX II transport buttons

> 🟡 **Deferred — not built.** The two unresolved questions below need hardware or a decision.


## Context

With a TX-6 connected, the transport row's play/stop buttons appear to do nothing. The idea is to
replace them with **FX I / FX II toggles** mirroring the two buttons on the device itself (photo:
`I` on dark navy, `II` on orange), wired to the FX bus enables.

We are **not building it now** — it is being recorded as a planned feature. Two things are
unresolved and both need hardware or a decision, so writing them down is the point of this task.

### What is actually known

- **The FX enables are verified.** `CC 82 = 127` on channel 8 switched FX I on and `0` switched
  it off, on hardware. Both buses already exist as params: `tx6.fx1.en` / `tx6.fx2.en`
  (`DeviceProfiles.swift`), master-only, `teSwitch` encoding.
- **"Play/stop do nothing" is unverified.** `CC 46` is documented as the TX-6's start/stop toggle
  and appears in the transport map, but `notes/RESEARCH.md` lists its behaviour as an open
  question — it has never been sent to a real device.
- **Play/stop are not obviously pointless.** They also send `0xFB`/`0xFC`, and the TX-6 *is*
  verified to follow the app's clock (68 -> 101 BPM). Those are how a clock-slaved sequencer would
  start and stop in time, so removing them may remove the only way to do that.
- **The device never reports state** (`mirrorsIncomingCC: false`), so the app must track FX on/off
  itself and can desync — the same hazard already recorded for CC 46.

## Blocking question: are play/stop actually useless?

`CC 46` is documented as the TX-6's start/stop toggle, but it has **never been sent to a real
device** — `RESEARCH.md` lists its behaviour as an open question. Play/stop also send `0xFB`/
`0xFC`, and clock-following *is* verified (68 -> 101 BPM), so those are how a clock-slaved TX-6
sequencer would start and stop in time. Removing them may remove the only way to do that.

The 30-second test that settles it: send `CC 46 = 127` on channel 7 with a sequence loaded on the
device, and watch whether its transport moves. `tools/midi/` has everything needed.

## Open design question

In the reference photo the FX I button is dark navy and FX II is orange. Unknown whether those are
the buttons' **fixed identities** or their **on/off state** — it decides the styling, and only the
device answers it.

## Implementation constraints

- **Profile-driven, not an `if tx6` branch.** Adding a device is meant to be a profile literal
  (CLAUDE.md). This wants a capability or a declared transport-row variant.
- **The app must hold the on/off state.** `mirrorsIncomingCC: false` — the device never reports
  it, so the buttons can desync from the hardware exactly like CC 46 already can.
- **Write the same params an LFO writes** (`tx6.fx1.en` / `tx6.fx2.en`), so a chip and a button
  press do not fight over the bus.
- **New accessibility ids** for UITests, alongside the existing `track<n>Button` / `masterButton`.

## Where the code goes

`ios/Sources/UI/TransportView.swift` — row 1 of both `TransportColumnView` (landscape) and
`TransportBarView` (portrait), which today hold `play.fill` / `stop.fill`.

---

<!-- previous plan — completed and shipped -->

# Fix: volume digits clipped in landscape

## Context

In iPhone landscape the two volume digits either side of the fader are cut off on their right
edge — the "9" and "0" of 90 both lose part of the glyph. Reported from a TX-6 screenshot at
812x375. Portrait is fine.

**Cause:** `volValueFont` is derived from `trackColW`, but the digits do not live in a track
column — they live inside the *fader*, which in landscape is what remains after the pan knob and
four hardcoded paddings. `trackColW` also ignores the gaps `TracksView` and `TrackStripView` add,
so it overstates the real strip width by ~18%. The font ends up sized for roughly three times the
space the digits actually have.

Portrait escapes it because the pan knob sits *above* the fader there, so the fader gets the whole
strip and each digit has ~45pt for a ~17pt glyph.

### Measured — iPhone 11 Pro landscape (812x375), TX-6, 6 tracks

| quantity | pt | where from |
|---|---|---|
| `trackGapUnit` | 5.68 | `screen.width * 0.007` |
| `transportColW` | 110.32 | `(812 - 7 * 5.68) / 7` |
| strip content width | **98.95** | column 110.31 minus the strip's own 2x5.68 |
| `trackColW` (the metric) | 116.95 | **overstates the real width by 18%** |
| pan knob + `.padding(.leading, 6)` + `.padding(.trailing, 4)` | 54.44 | TrackStripView:42-44 |
| fader `.padding(.horizontal, 6)` | 12.00 | TrackStripView:53 |
| **fader width** | **32.51** | 98.95 - 54.44 - 12 |
| space per digit | **9.25** | `32.51 / 2 - volValueSpacing 7` |
| glyph width at 28pt | **16.8** | monospaced advance ~0.6em |

Short by 7.5pt — about half the glyph, which is what the screenshot shows.

**iPad landscape is worse and also broken** (untested by the user so far): ~19.5pt available
against ~34.8pt needed at the 58pt cap. That cap has never actually been rendered.

## Approach

Reclaim the padding first, as requested, then let the font size itself from the space that is
genuinely left. The four hardcoded paddings total only 22pt, so padding alone cannot fully close
a 7.5pt deficit while leaving any breathing room — trimming them to ~8pt yields 16.05pt per digit,
still 0.75pt under. A font of ~26pt closes it, a 7% reduction that is not perceptible.

Crucially the font stops being a guess: it is computed from the width that exists, so every device
and orientation is correct by construction rather than by a cap that happens to fit.

### 1. `ContentView.swift` — LayoutMetrics

- Add `var hasPan: Bool = true`, passed at construction from `app.profile.caps.hasPan` alongside
  the existing `trackCount` (ContentView.swift:186). The TP-7 has no knob, so its fader gets the
  whole strip and its digits can be larger.
- Add `stripContentW` — the *real* width one strip's content gets, subtracting the gaps
  `TracksView` and `TrackStripView` add. Verified against the measurement above (98.95).
  `trackColW` stays as-is for callers that want the nominal column.
- Add `stripInnerPad` and `panFaderGap`, both fractions of `trackGapUnit` (~0.5), replacing the
  hardcoded 6/4/6/6. Keeps the CLAUDE.md rule that leaf views hold no pt literals.
- Add `faderColW`: `stripContentW` minus the pan knob and those paddings in landscape when
  `hasPan`; the full `stripContentW` otherwise.
- Redefine `volValueSpacing` as `faderThumbW / 2` — the clearance that keeps a digit off the
  thumb, which is what it is actually for. Equals today's 7pt at the reference size, and removes
  the circular dependency on the font.
- Redefine `volValueFont` from the space per digit: `(faderColW / 2 - volValueSpacing) / 0.6`,
  still capped by the existing `isIpad ? 58 : 28` so nothing grows beyond today's sizes. 0.6 is
  the monospaced advance ratio and wants a named constant with a comment.

### 2. `TrackStripView.swift` — landscape branch (lines 36-55)

Replace `.padding(.leading, 6)` / `.padding(.trailing, 4)` on the knob and
`.padding(.horizontal, 6)` on the fader with the new metrics. Portrait is untouched.

### 3. `VolumeFaderView.swift` — safety net (lines 65-76)

Add `.lineLimit(1)` and `.minimumScaleFactor(0.8)` to both digit `Text`s. The 0.6 advance ratio is
an approximation; this guarantees a glyph shrinks rather than clips if a future size lands outside
the estimate. Cheap insurance against exactly this class of bug returning.

### Expected results

| device / orientation | digit space before | after | font |
|---|---|---|---|
| iPhone landscape, TX-6 | 9.25 (clipped) | ~16.1 | 28 -> ~26 |
| iPad landscape, TX-6 | ~19.5 (clipped) | ~23.4 | 58 -> ~39 |
| iPhone portrait | ~45 | unchanged | 28 (capped) |
| TP-7 landscape (no pan) | — | wider still | capped |

## Verification

1. `xcodebuild test ... -only-testing:op1-lfo-heroTests` — 156 tests must stay green (layout is
   untested there, but the profile/metric plumbing must not break).
2. Landscape screenshots via the existing UITest, which writes to `/tmp/claude-ss/`:
   `-only-testing:op1-lfo-heroUITests/HelpSettingsUITests/testLandscapeLayout`, run with
   `--uitest-profile tx6`, then `tp7` (no pan knob) and `op1` (4 tracks, widest strips).
3. Repeat on an iPad simulator — the case predicted to be broken today, so it is the one that
   proves the formula rather than the cap.
4. Read the digits in each PNG: both glyphs whole, clear of the thumb, still legible.
5. On device, drag a fader through 0-99 and check no digit clips at any value (11, 88 and 90 are
   the widest glyph combinations).

---

# Multi-device support: OP-1 Field + TX-6 + TP-7

> ## ⚠️ SUPERSEDED — historical planning document, do not use as reference
>
> This plan was written **before any hardware testing** and several of its assumptions turned
> out to be wrong. It shipped, and the implementation has since moved well past it.
>
> **Authoritative sources, in order:**
> 1. `ios/Sources/Engine/DeviceProfiles.swift` — the profiles as they actually are
> 2. `notes/RESEARCH.md` — measured hardware behaviour, with corrections to TE's own references
> 3. `notes/FIELD_DEVICE_SUPPORT.md` — what is done and what is still untested
> 4. `tools/midi/` — the probes that produced the measurements
>
> ### What this document gets wrong
>
> | claim below | reality (measured) |
> |---|---|
> | TP-7 `canBeClockMaster: false` | **true** — it streams 24 PPQN in `sync` mode, undocumented by TE |
> | TP-7 `hasTempoParam: false` | **true** — tempo retunes the app clock, which the device follows |
> | TP-7 play = `CC 14` | `CC 14` is **record**. Play is `0xFB`. This would have armed recording on every play |
> | TP-7 prev/next = `ccRelative(cc: 18, ±8)` | CC 18 is a **persistent bipolar speed state**, not a nudge — it must be released or the tape runs away |
> | CC 18 offset 4 = 1x | **x0.06.** It is the stall point. 1x is offset ~7.5, so no integer hits it |
> | CC 18 sets absolute speed | **additive** — it stacks on the device's own direction, giving ~3x if the tape is already reversing |
> | Pitch bend = magnitude multiplier x0.25-x2.0 | **signed velocity offset**, ~-20..+40 ticks/s; the sense flips while reversing, and it does nothing with the transport stopped |
> | TP-7 gain is per track | per **input jack** (3 jacks feeding 6 mix channels) |
> | TX-6 mute `CC 120` polarity assumed | verified; but note CC 120 is standard "all sound off" and leaks to other gear on a hub |
> | "verify TX-6/TP-7 follow `0xF8`" listed as open | TP-7 follows; TX-6 needs `clock SRC = usb` set on the device first |
>
> Two bugs not anticipated here were found later in the **BLE transport**, which this plan barely
> touches: outgoing packets stamped every message as time zero (a TX-6 read our clock as 640000
> BPM), and the receive parser mistook timestamp bytes for clock/start/stop. See
> `ios/Tests/BleMidiParserTests.swift`.

## Context

The iOS app is single-device end to end — there is no device abstraction anywhere. OP-1 Field assumptions are hardcoded in four independent layers: CC constants in `Controller`, a 4-track/channel-N-1 convention across `AppState` and every UI file, a 0-99 display scale in global `midiToUI`/`uiToMidi`, and name-matching (`"op-1"`/`"op1"`) device detection in `USBMidi`/`BLEMidi`.

You own a TP-7 and a TX-6 and can test against real hardware. Both are 6-channel devices with entirely different CC maps, native 0-127 values, and no documented MIDI clock. The goal is a data-driven `DeviceProfile` so all three devices are table entries rather than code branches, with **OP-1 behavior byte-for-byte identical** throughout.

Sources: [TP-7 MIDI reference](https://teenage.engineering/guides/tp-7#midi-reference), [TX-6 MIDI reference](https://teenage.engineering/guides/tx-6#midi-reference).

**Decisions made:** fully dynamic 1…N track strips; full TX-6 param coverage; FX buses (ch 8/9) folded into the master slot as master-only params; LFOs always run off the app's internal 24 PPQN clock, transport is profile-defined, clock-following on TX-6/TP-7 is an empirical unknown to verify on hardware.

**Out of scope:** the Python app in `src/`; simultaneous multi-device connection (one device at a time).

---

## Pre-existing bugs this work must fix first

Verified in the code — these block the refactor:

1. **Saved settings are silently wiped by any schema change.** [AppState.swift:95-101](ios/Sources/Engine/AppState.swift#L95-L101) uses `try? decode(...)` falling back to `Settings()`. Swift's synthesized `Decodable` does **not** apply property defaults for missing keys, so adding one field throws → every saved chip, track state and BPM is lost silently. Must be fixed before any schema change ships.
2. **`Controller.muteState`** ([Controller.swift:17](ios/Sources/Engine/Controller.swift#L17)) is a second source of truth for mute, never synced with `AppState.mutes`. Delete it; make `AppState.mutes` authoritative.
3. **`CompactPicker`'s portrait branch cannot scroll** — [LFOPanelView.swift:500-505](ios/Sources/UI/LFOPanelView.swift#L500-L505) is a bare `itemList.frame(width: w)`. TX-6's flat list is ~33 items; on iPhone portrait the tail is unreachable. The landscape branch already has the `ScrollViewReader` fix — reuse it.
4. ~~`VolumeFaderView` renders exactly two digits~~ — **not a bug.** The 0-99 display scale is an app-wide convention that applies to *every* device, not just the OP-1: the UI always shows 0-99 while MIDI carries 0-127, via `midiToUI`/`uiToMidi`. `DeviceProfile` deliberately has **no** per-device scale knob, so the two can't diverge. This removes most of Phase 4 and leaves every literal-`99` site untouched.
5. **Hardcoded pt values that break at 6 columns:** `panKnobPortrait`'s `trackColW - 24` and `volValueFont`'s `isIpad ? 58 : 28` in [ContentView.swift](ios/Sources/UI/ContentView.swift). Both violate the CLAUDE.md rule and must become fractions.
6. **`toggleBtnSize`'s 44pt floor overflows** at 6 tracks: 8 buttons × 44 + 7 × 6 gaps = 394pt > 390pt iPhone portrait. The row must wrap.

---

## New types — `Engine/DeviceProfile.swift`

```swift
enum ChannelRule: Hashable {
    case trackRelative(offset: Int)   // ch = (track - 1) + offset; track 0 → profile.masterChannel
    case pinned(Int)                  // absolute 0-based MIDI channel
}

struct SwitchEncoding: Hashable {
    var onValue = 127, offValue = 0, threshold = 64, inverted = false
}

enum ValueEncoding: Hashable {
    case continuous
    case switching(SwitchEncoding)
    case relative(center: Int)
    case enumerated(count: Int)       // TP-7 loop 0-2
}

enum ParamBinding: Hashable {
    case cc(cc: Int, channel: ChannelRule, encoding: ValueEncoding)
    case pitchBend(channel: ChannelRule)   // reserved: TP-7 playback speed, unused in v1
    case virtualTempo                       // app-internal BPM, no CC (OP-1 "tempo")
}

enum ParamRole: String, Hashable { case generic, volume, pan, mute, tempo }

struct ParamSpec: Identifiable, Hashable {
    let id: String                 // STABLE persistence id — never rename
    let name: String               // picker label, lowercase
    let short: String              // chip label
    let track:  ParamBinding?      // nil → master-only
    let master: ParamBinding?      // nil → not master-capable
    var role: ParamRole = .generic
    var availableTracks: ClosedRange<Int>? = nil   // TP-7 input gain = 1...3
    var defaultCenter: Double = 90
    var lfoTargetable = true

    var isMasterOnly: Bool    { track  == nil }
    var isMasterCapable: Bool { master != nil }
}
```

Separate `track`/`master` bindings are the load-bearing decision. They reproduce OP-1 exactly (fx 1 = CC 54 track-relative, CC 70 pinned ch 0 on master) **and** deliver "FX buses folded into the master slot" with zero new UI machinery — a TX-6 FX param is simply `track: nil`, so the existing `lfoParam.didSet` / `cycleMaster` / `cycleTrack` logic at [AppState.swift:43-56](ios/Sources/Engine/AppState.swift#L43-L56) works unchanged.

```swift
struct DisplayScale: Hashable {
    let max: Int
    func toUI(_ v: Double) -> Double { (v * Double(max) / 127).rounded(.down) }
    func toMidi(_ v: Double) -> Int  { (Int(v) * 127 + (max - 1)) / max }
    static let op1    = DisplayScale(max: 99)
    static let raw127 = DisplayScale(max: 127)
}
```
At `max = 99` these are character-identical to the current [Models.swift:186-192](ios/Sources/Engine/Models.swift#L186-L192). At `max = 127` both collapse to the identity. Golden-tested.

```swift
enum TransportOp: Hashable {
    case midiStartOrContinue                        // 0xFA / 0xFB
    case midiStop                                   // 0xFC
    case tapeSeek(cc: Int, steps: Int)              // OP-1: CC + SPP 0xF2 + resume
    case cc(ch: Int, cc: Int, value: Int)
    case ccRelative(ch: Int, cc: Int, delta: Int)   // sends 64 + delta
    case toggleCC(ch: Int, cc: Int, value: Int, whenPlaying: Bool)
}

struct TransportMap: Hashable {
    var play, stop, prev, next: [TransportOp]
    var prevSymbol = "arrow.left", nextSymbol = "arrow.right"
}

struct DeviceCapabilities: Hashable {
    var hasPan = true
    var canBeClockMaster = true   // hardware sends 0xF8 → app may slave
    var followsClock = true       // UNVERIFIED for tx6/tp7
    var hasTempoParam = true
    var clockLabel = "op1"
}

struct DeviceProfile: Identifiable, Hashable {
    let id: String                 // "op1" | "tx6" | "tp7"
    let displayName: String
    let nameTokens: [String]       // lowercase substrings matched against endpoint names
    let trackCount: Int
    let masterChannel: Int
    let scale: DisplayScale
    let params: [ParamSpec]        // flat, ordered — drives picker AND the cycle button
    let defaultParamId: String
    let defaultVolume: Double
    let transport: TransportMap
    let caps: DeviceCapabilities

    private let byId: [String: ParamSpec]
    private let inbound: [Int: (spec: ParamSpec, track: Int)]   // key = ch << 8 | cc

    var trackIndices: [Int] { Array(1...trackCount) }
    func param(_ id: String) -> ParamSpec?
    func binding(_ s: ParamSpec, track: Int) -> ParamBinding? { track == 0 ? s.master : s.track }
    func channel(_ rule: ChannelRule, track: Int) -> Int
    func inboundTarget(channel: Int, cc: Int) -> (spec: ParamSpec, track: Int)?
    func clamp(_ s: ParamSpec, track: Int, raw: Double) -> Double
    func matches(endpointName: String) -> Bool
}

enum DeviceRegistry {
    static let all: [DeviceProfile] = [.op1Field, .tx6, .tp7]   // order = tie-break
    static func profile(forEndpointName: String) -> DeviceProfile?
    static func profile(id: String) -> DeviceProfile            // defaults to .op1Field
}
```

`inbound` is built once in `init` by iterating `params × (0...trackCount)` and resolving concrete channels — one table serving both directions. Add a `#if DEBUG` assertion that fails on duplicate ids or key collisions. (Verified collision-free: OP-1 master 70-77 vs track 46-61 on ch 0; TX-6 ch 7/8 reuse CC 12/13/14/15/82 on distinct pinned channels.)

---

## Profile data — `Engine/DeviceProfiles.swift`

### OP-1 Field
`id "op1"` · tokens `["op-1","op1"]` · 4 tracks · masterChannel 0 · `.op1` scale · defaultVolume 90 · caps all default.
Transport: play `[.midiStartOrContinue]` · stop `[.midiStop]` · prev `[.tapeSeek(cc: 82, steps: -1)]` · next `[.tapeSeek(cc: 83, steps: +1)]`.

**Param ids are the legacy `Parameter` raw values** so old saved clips decode with an empty mapping table:

| id | short | track | master | role |
|---|---|---|---|---|
| `volume` | vol | cc 7 rel(0) | — | .volume |
| `pan` | pan | cc 10 rel(0) | — | .pan |
| `mute` | mut | cc 9 rel(0) switch(127/0/64) | — | .mute |
| `tempo` | tmp | — | `.virtualTempo` | .tempo |
| `par 1`…`par 4` | p1…p4 | cc 46-49 rel(0) | — | |
| `env A/D/S/R` | eA…eR | cc 50-53 rel(0) | — | |
| `fx 1`…`fx 4` | fx1…fx4 | cc 54-57 rel(0) | cc 70-73 pinned(0) | |
| `lfo 1`…`lfo 4` | l1…l4 | cc 58-61 rel(0) | cc 74-77 pinned(0) | |

`par`/`env` keep `master: nil` — exact parity with today's `isMasterCapable`.

### TX-6
`id "tx6"` · tokens `["tx-6","tx6"]` · 6 tracks · masterChannel 6 · `.raw127` · defaultVolume 115 · caps `canBeClockMaster false`, `hasTempoParam false`, `clockLabel "tx6"`.
Transport: play `[.toggleCC(ch:6, cc:46, value:127, whenPlaying:false), .midiStartOrContinue]` · stop `[.toggleCC(ch:6, cc:46, value:127, whenPlaying:true), .midiStop]` · prev/next `[.ccRelative(ch:6, cc:47, delta:∓1)]` with `minus`/`plus` symbols.

Per-track, `.trackRelative(offset: 0)` → ch 0-5: vol `7`(.volume), pan `8`(.pan), gain `9`, mute `120` switch(.mute), filter `74`, eq high `85`, eq mid `86`, eq low `87`, comp `93`, syn wave `3`, syn freq `89`, syn len `90`, syn detune `95`, fx1 send `91`, aux send `92`, aux2 send `94`, seq pattern `14`.

Master-only, pinned: main vol `7`/ch6, aux vol `14`/ch6, cue vol `15`/ch6, local ctl `122`/ch6 switch; fx1 en `82`/ch7 switch, fx1 eng `15`/ch7, fx1 p1 `12`/ch7, fx1 p2 `13`/ch7, fx1 p3 `14`/ch7, fx1 return `7`/ch7; fx2 en `82`/ch8 switch, fx2 eng `15`/ch8, fx2 p1 `12`/ch8, fx2 p2 `13`/ch8, fx2 p3 `14`/ch8, fx2 track `9`/ch8.

**CC 47 (tempo relative) is deliberately not a param** — a relative encoder would drift monotonically under an LFO, never oscillate. Reachable only via the ←/→ transport buttons.

### TP-7
> ⚠️ **Everything in this TP-7 section is wrong except `hasPan: false`.** See the banner at the
> top and `DeviceProfiles.swift` for what shipped. Left here only to show what was assumed.

`id "tp7"` · tokens `["tp-7","tp7"]` · 6 tracks · masterChannel 0 · `.raw127` · defaultVolume 115 · caps **`hasPan false`**, ~~`canBeClockMaster false`~~ (**true** — it streams clock), ~~`hasTempoParam false`~~ (**true**), `clockLabel "tp7"`.
Transport: ~~play `[.cc(ch:0, cc:14, value:127), .midiStartOrContinue]`~~ — **`CC 14` is RECORD**; this would have armed a take on every play. Play is `[.midiStartOrContinue]` alone.
~~prev/next `[.ccRelative(ch:0, cc:18, delta:∓8)]`~~ — CC 18 is a **persistent bipolar speed state**, not a nudge: it engages the transport and the tape keeps moving until released, so it needs `.directionalTransport` with a dead zone (offset = 4 + 4 × speed), plus a pitch-bend trim to reach 1x reverse.

| id | short | track | master |
|---|---|---|---|
| `tp7.vol` (mix volume) | vol | cc 7 rel(0) · .volume | — |
| `tp7.mute` (mix mute) | mut | cc 120 rel(0) switch · .mute | — |
| ~~`tp7.gain`~~ | gn | ~~cc 9 rel(0), `availableTracks: 1...3`~~ — gain belongs to the **3 input jacks**, not tracks. Shipped as three master-only params on pinned channels 0/1/2 | — |
| `tp7.rec` (record) | rec | — | cc 14 pinned(0) switch |
| `tp7.cueRec` (cue rec) | cue | — | cc 16 pinned(0) switch |
| `tp7.loop` (loop) | lp | — | cc 17 pinned(0) enumerated(3) |

---

## Engine changes

**`Controller.swift`** — delete `muteState` and all seven named setters; one generic entry point:
```swift
func send(spec: ParamSpec, track: Int, value: Double, profile: DeviceProfile? = nil)
func send(role: ParamRole, track: Int, value: Double)      // used by the mixer strip
func transport(_ ops: [TransportOp], isPlaying: Bool, spp: inout Int, step: Int)
private func sendCC(ch: Int, cc: Int, val: Int)            // body unchanged
```

**`AutomationEngine.swift`** — the 20-arm switch at `dispatch` (L241-267) collapses to a profile lookup + `controller.send(spec:track:value:)`; `updateCallback` becomes `((Int, ParamSpec, Double) -> Void)`; `lfo.parameter == .tempo` checks become `spec.role == .tempo`; clamping delegates to `profile.clamp`. Waveform/phase math, free rates, the random PRNG, preview and `onTick` are untouched — already device-agnostic. A `deviceId` guard drops any stale clip so a switch race can't send a TX-6 CC to an OP-1.

**`Models.swift`** — `Parameter` is deleted. `LfoClip` gains `var deviceId: String = "op1"` and swaps `parameter: Parameter` for `paramId: String`. `midiToUI`/`uiToMidi` become a thin `@MainActor` shim over `UIScale.current` (set only from `AppState.applyProfile`) so ~20 call sites don't churn — every existing caller is already main-actor, and `AutomationEngine` never calls them.

**`AppState.swift`** — the duplicated inbound CC map (L254-272, bare literals `7`/`9`/`10` and the `(1...4)` guard) is replaced by `profile.inboundTarget(channel:cc:)` + a `spec.role` switch, so OP-1 CC 9 and TX-6 CC 120 differ in *data*, not code. Add `@Published var profile`, `@Published var profileOverrideId`, `var uiMax: Double`, and `applyProfile(_:)`.

**`USBMidi.swift` / `BLEMidi.swift`** — `isOP1(_:)` → `isKnownDevice(_:)` backed by `DeviceRegistry.profile(forEndpointName:) != nil`; `scanForOP1` → `scanForDevices`; add `@Published var matchedProfileId: String?`. `connectSource()`'s entity-based discovery (L229-244) is model-independent and stays as-is.

Profile resolution precedence: manual override → auto name match (USB first, then BLE) → **keep the last used profile** (never reset). `StatusBarView` gets a tappable profile badge, dim when auto-detected and `C.yellow` when assumed; tapping opens Settings.

---

## Persistence and per-device state

`Settings` becomes versioned with **hand-written `init(from:)` using `decodeIfPresent(…) ?? default` for every field** on `Settings`, `DeviceState` and `LfoClip` — this alone makes all future schema changes non-destructive and fixes bug #1.

```swift
private struct Settings: Codable {
    var version = 1
    var deviceId = "op1"
    var profileOverrideId = "auto"
    var perDevice: [String: DeviceState] = [:]
}
private struct DeviceState: Codable {   // lfoWave, lfoParamId, lfoRate/Depth/Center,
    ...                                 // trackOn, masterOn, isClockMaster, bpm,
}                                       // volumes, pans, mutes, activeLfos
```

Migration: try v1 → else decode a `SettingsV0` mirror of today's struct (with `parameter` as a raw `String` so an unknown value can't throw) into `perDevice["op1"]`. **The old→new param id map is empty** because OP-1's ids are the legacy raw values; keep `legacyParamIdMap: [String: String] = [:]` as the documented hook. Clips with an unresolvable `paramId` or `track > trackCount` are dropped with a debug log, not a crash. Sanitize `trackOn` to the profile's range (falling back to track 1 on) so `lfoStart`'s "lowest non-zero track" can't target a nonexistent track. Preserve the existing ordering constraint: assign `lfoParam` **last** ([AppState.swift:109](ios/Sources/Engine/AppState.swift#L109)) because its `didSet` adjusts `masterOn`.

**State is stored per profile, not reset on switch.** A chip is `(track, paramId, depth, center)` in that device's MIDI units and param namespace — `"fx 1"` and `"tx6.eqHi"` aren't translatable, nor are 0-99 vs 0-127 centers. Resetting would destroy a session's work every time you unplug the OP-1 for the TX-6 and back. Global (not per-device): `chipPauseAction`, `oneShotFinishAction`, `cleanupOneShots`, `profileOverrideId`.

`applyProfile` sequence: clear automation + preview → flush current state to `perDevice[oldId]` and save → swap profile into `UIScale`/`Controller`/`AutomationEngine` → rebuild published state from `perDevice[newId]` (filling gaps with `defaultVolume`) → re-add `loop` chips → force app-master clock if `!caps.canBeClockMaster`.

---

## UI changes

All per the CLAUDE.md `LayoutMetrics` rules — no pt literals in leaf views, only `isLandscape`/`isIpad` branches, 1pt strokes stay hardcoded.

**`ContentView.swift`** — `LayoutMetrics` gains `let trackCount: Int` (default 4 in `LayoutMetricsKey`):
- `transportColW`: `let cols = CGFloat(trackCount + 1); (screen.width - cols * trackGapUnit) / cols` — identical at 4.
- `trackColW`: `mixerW / CGFloat(trackCount)`.
- `toggleBtnCount: Int { trackCount + 2 }`; `toggleBtnRows: Int { !isLandscape && !isIpad && toggleBtnCount > 6 ? 2 : 1 }`.
- `toggleBtnSize` iPhone-portrait formula divides by `ceil(toggleBtnCount / toggleBtnRows)` instead of the hardcoded 6 — byte-identical at 4 tracks, wraps to 2 rows of 4 at 6.
- `panKnobPortrait` → `min(trackColW * 0.76, tracksH * 0.30)` (0.76 reproduces the current −24pt at iPhone-portrait `trackColW ≈ 97.5`).
- `volValueFont(digits:)` becomes a function; 58/28 survives only as a cap.
- `StatusBarView`/`SettingsView`/`DevicePickerView`/`HelpView`: profile-driven `clockLabel` and `displayName` instead of hardcoded "op1"; new device-override picker row (a11y id `deviceOverridePicker`) backed by `app.profileOverrideId`; discovered endpoints annotated with their matched profile.

**`TrackStripView.swift`** — `ForEach(1...4)` → `ForEach(app.profile.trackIndices, id: \.self)`; pan knob wrapped in `if app.profile.caps.hasPan` (fader takes the space on TP-7); direct `uiToMidi` calls become role-based controller calls.

**`LFOPanelView.swift`** — `snapCenter` and `waveTracks` iterate `app.profile.trackIndices`; the toggle row chunks into `m.toggleBtnRows` with master + preview trailing the last row; the param picker takes `app.profile.params`; center/depth ranges use `app.uiMax`; chip labels resolve `profile.param(lfo.paramId)?.short`. `CompactPicker` drops its `RawRepresentable` constraint for a `label: (T) -> String` closure (`ParamSpec` is already `Identifiable & Hashable`, so `.id`, `scrollTo` and `==` all still work) **and the portrait branch gets the landscape `ScrollViewReader` treatment**, capped at `min(count * 44 + 40, screen.height * 0.6)`.

**`VolumeFaderView.swift`** — new `maxValue: Double` param replacing the hardcoded 99 at L30/31/90/92/95; digit count derived from `String(Int(maxValue)).count`.

**`TransportView.swift`** — prev/next SF Symbols and metronome label from the profile; metronome disabled + dimmed when `!caps.canBeClockMaster`.

**`Theme.swift`** — extend `C.track` to 6, clear of green (#4ec94e active), purple (#aa66cc preview) and red (#c04040 fader): `5: #c25fa0` magenta, `6: #3fb0a8` teal.

---

## Implementation phases

Each phase compiles and ships; OP-1 stays identical throughout.

0. **Safety net.** Add an `op1-lfo-heroTests` unit-test target. Capture a **golden byte table**: every current `Parameter` × track 0-4 × value {0,1,63,64,126,127} → exact `[UInt8]`, plus `midiToUI`/`uiToMidi` for all 0-127. Add a `--midi-log` launch arg printing every outgoing triple so UITest runs can be diffed.
1. **Types only.** `DeviceProfile.swift` + `DeviceProfiles.swift` with only `.op1Field` populated. Nothing consumes it. Test: the OP-1 profile reproduces the golden table.
2. **Route OP-1 through the profile** (highest regression risk). Rewrite `Controller`, collapse `dispatch`, `Parameter` → `ParamSpec` everywhere, unify the inbound map, hand-written decoders + v0→v1 migration, delete `muteState` and `Parameter`. Still 4 tracks, one profile.
3. **Dynamic track count**, still 4 for OP-1. `LayoutMetrics.trackCount` and all generalized formulas, de-hardcode `panKnobPortrait`/`volValueFont`, `ForEach` over profile tracks, 6 track colors, `CompactPicker` portrait scroll fix.
4. **Capabilities.** `caps.hasPan` in `TrackStripView`, `caps.canBeClockMaster` in the transport/status bar, profile-driven `TransportOp` execution (OP-1's map must reproduce `ClockEngine.play/stop/tapePrev/tapeNext` byte-for-byte). No display-scale work — see the note above; 0-99 stays app-wide and untouched.
5. **Add the devices.** TX-6 + TP-7 profiles, `nameTokens` matching in both transports, Settings override + `--uitest-profile <id>` launch arg, per-device state buckets, status-bar badge, unknown-device fallback.
6. **Hardware validation + docs.**

New `.swift` files need `PBXFileReference` + `PBXBuildFile` + group + Sources-phase entries (`project.pbxproj` uses classic groups, `objectVersion = 77`) — add them through Xcode, not by dropping files on disk.

---

## Verification

**Unit tests** (`op1-lfo-heroTests`) — `ControllerGoldenTests` (the phase-0 byte table; highest-value guard), `DisplayScaleTests` (`.op1` matches the golden table for all 0-127; `.raw127` is the identity), `DeviceProfileTests` (no duplicate ids, no inbound key collisions, outbound→inbound round-trip for every param × track), `SettingsMigrationTests` (a captured real v0 blob keeps its chips/params/tracks/`isEnabled`/`loop`; an unknown `paramId` drops one clip without throwing; garbage yields defaults without crashing).

**Existing UITests** — `HelpSettingsUITests` needs no change (OP-1 param labels are preserved exactly). `ScreenshotTests` and `AppPreviewUITests` should add `--uitest-profile op1` next to `--uitest-reset` so a leftover override can't perturb them; `track5Button`/`track6Button` come free from the existing `"track\(track)Button"` interpolation.

**New UITests** — `testDeviceOverrideSwitchesTrackCount`; `testTx6ParamPickerReachesLastItem` (asserts `"fx2 track"` is hittable in **portrait** — the regression test for the popover-scroll bug); `testTp7HidesPanKnob` (needs new `panKnob\(n)` a11y ids); `testTx6PortraitLayout` / `testTx6LandscapeLayout` / `testTp7PortraitLayout` screenshots to `/tmp/claude-ss/` (landscape via `Snapshot.fixLandscapeOrientation`, `@MainActor`); `testChipsSurviveDeviceRoundTrip`.

**Hardware.** OP-1 first and exhaustively — every param on every track and master, both clock modes, tape seek with SPP, incoming CC 7/9/10 UI sync, USB and BLE. Then **TX-6**: does it act on 0xF8 at all; CC 120 polarity (does 127 mute or unmute); does CC 46 desync when the transport is started from the panel; do the ch 7/8/9 pinned params land; does it echo CC back for UI sync; what is the BLE peripheral name (it may not do BLE MIDI at all). Then **TP-7**: CC 14 record semantics, CC 17 absolute 0-2 loop, a CC 18 step size that feels right, clock following, BLE name.

---

## Notes to update

**`notes/FEATURES.md`** — add under `## To fix`: `HIGH` multi-device `DeviceProfile` abstraction; `HIGH` dynamic 1..N track count incl. toggle-row wrap; `HIGH` settings schema v1 + non-destructive decode; `MED` manual device override; `MED` per-device saved state; `MED` TX-6 fx bus params in the master slot; `MED` collapse `Controller.muteState` into `AppState.mutes`; `LOW` CompactPicker portrait scroll; `LOW` TP-7 pitch-bend playback speed as an LFO target; `LOW` TP-7 input gain only on channels 1-3; `LOW` listen to TP-7 controller-mode CCs as app input. Also: `add parameter: ENVELOPE x4` is already implemented and should move to `## Done`; `MASTER EQ low/mid/high - CC 90-92` becomes three table rows once `ParamSpec` lands.

**`notes/RESEARCH.md`** — a `## Multi-device MIDI mapping` section with all three CC tables as implemented, plus the OP-1 0-99 scale note (why the `max`-parameterized form is identical at 99 and the identity at 127), and an `## Open questions (answer on hardware)` list matching the hardware checklist above.

**`CLAUDE.md`** — extend the track palette to 6 (noting 5-6 apply only to TX-6/TP-7), add the device list, and add the new accessibility ids (`deviceOverridePicker`, `track5Button`, `track6Button`, `panKnob<n>`).

---

## Risks

- **CC 120 is standard MIDI "All Sound Off"** — sending it on ch 1-6 will silence unrelated gear behind a hub. Inbound is already scoped to the active profile's table; the outbound hazard needs documenting.
- **TX-6 CC 46 is a stateless toggle** — the app can't read the hardware transport state, so `.toggleCC(whenPlaying:)` gates on the app's own `isPlaying` and can desync if you press play on the device. Accept and document.
- **TX-6/TP-7 BLE peripheral names are unverified**, and the TX-6 may not expose BLE MIDI at all. The manual override is the escape hatch.
- **Track gap accumulation** — `TracksView`'s `HStack(spacing:)` plus each strip's `.padding(.horizontal, trackGapUnit)` costs 3 gap units per boundary, and `trackColW` doesn't subtract it. At 6 tracks on iPhone portrait that's ~35pt of 390. Acceptable, but revisit if the strips feel cramped.
- **Phase 2 is the regression risk** — it rewrites the entire outbound path at once. The golden byte table and `--midi-log` diff exist specifically to catch it.
