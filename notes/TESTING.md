# Testing Notes

## Simulators

| Device | UDID | Screen | Notes |
|---|---|---|---|
| iPhone 17 | `99D2A4A5-05FA-4D4F-BD64-3C14AD970012` | 1206×2622 px | Primary iPhone test device |
| iPad Air 11-inch (M3) | `EF22EF75-09BC-4F8B-8B7F-8D446EBD57CE` | 820×1180 pt | iPad layout testing |
| iPhone 13 Pro Max | `CFD3002F-A1FA-4F88-A867-7E8083DB16F3` | 1284×2778 px | App Store screenshots (6.5" slot) |

## Rebuild + screenshot pipeline

```bash
# Build
xcodebuild build \
  -project ios/op1-lfo-hero.xcodeproj \
  -scheme op1-lfo-hero \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -configuration Debug

# Install + launch + screenshot
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "op1-lfo-hero.app" \
  -path "*/Debug-iphonesimulator/*" | head -1)
xcrun simctl install <UDID> "$APP"
xcrun simctl terminate <UDID> com.andrewralon.op1-lfo-hero
xcrun simctl launch <UDID> com.andrewralon.op1-lfo-hero
sleep 2.5   # wait past 2.0s splash + 0.4s fade
xcrun simctl io <UDID> screenshot /tmp/screenshot.png
```

## App Store screenshot sizes

| Slot | Accepted sizes | Which simulator |
|---|---|---|
| 6.9" (covers 6.5"/6.7"/6.9") | 1320×2868 | iPhone 17 Pro Max |
| 6.5" | 1284×2778 | iPhone 13 Pro Max |
| iPad 13" | 2064×2752 | iPad Pro 13-inch simulator |

**Note:** iPhone 17 base model produces 1206×2622 px — not accepted by any named App Store slot.

## Layout responsiveness (iOS)

`ContentView.swift` uses `GeometryReader` to match iPhone's proportional row positions:
- `tracksH    = min(max(280, geo.size.height * 0.37), 500)` — 37% of usable height
- `transportH = min(max(58,  geo.size.height * 0.076), 90)` — 7.6% of usable height
- iPhone (759 pt): tracksH=280, transportH=58 (unchanged)
- iPad 11" (1115 pt): tracksH≈412, transportH≈85
- iPad 13" (1302 pt): tracksH≈482, transportH≈90

`LFOPanelView.swift` uses `horizontalSizeClass` (`.regular` = iPad) to:
- scale waveform: 90 pt → 160 pt on iPad
- cap action section at 300 pt on iPad (with `Spacer` absorbing excess above it)
