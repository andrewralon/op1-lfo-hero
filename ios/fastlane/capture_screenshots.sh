#!/bin/bash
# Capture the App Store screenshots at each device's NATIVE resolution.
#
# Run from anywhere:  ios/fastlane/capture_screenshots.sh
# Then upload:        cd ios && fastlane upload_media overwrite:false
#
# Why three devices (App Store Connect screenshot spec, checked 2026-10-19):
#   iPhone 17                       1206x2622  -> APP_IPHONE_61  "Dynamic Island (medium)"  REQUIRED
#   iPhone 13 Pro Max Screenshots   1284x2778  -> APP_IPHONE_65  "Face ID (large)"          required unless a
#                                                                  Dynamic Island (large) set is given
#   iPad Pro 13-inch Screenshots    2064x2752  -> APP_IPAD_PRO_3GEN_129  "13-inch"            REQUIRED for iPad
# Uploading only the 6.5" set leaves the medium slot empty, and App Store Connect shows it greyed
# ("Using Existing Assets", 0 of 10) — that is what happened to 1.1.0 the first time.
#
# The tests pass --uitest-reset (no tutorial) and --uitest-spoof-connected (a green "<device> (ble)"
# status; the simulator has no Bluetooth). Output goes to /tmp/claude-ss first, is size-checked, and
# only then replaces fastlane/screenshots/en-US, so a failed run never leaves a half-updated set.
set -euo pipefail

cd "$(dirname "$0")/.."          # ios/
OUT=fastlane/screenshots/en-US
TMP=/tmp/claude-ss
mkdir -p "$TMP" "$OUT"

# name (exactly as the simulator is called) | expected pixel size
DEVICES=(
  "iPhone 17|1206x2622"
  "iPhone 13 Pro Max Screenshots|1284x2778"
  "iPad Pro 13-inch Screenshots|2064x2752"
)

# xcodebuild cannot match the custom-named simulators by name, so resolve the UDID ourselves. A name
# that exists under two runtimes (iPhone 17) resolves to the last listed, the newest runtime.
udid_for() {
  xcrun simctl list devices available | grep -F "    $1 (" | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | tail -1
}

rm -f "$TMP"/ss_*.png

for entry in "${DEVICES[@]}"; do
  IFS='|' read -r name size <<< "$entry"
  udid=$(udid_for "$name")
  [ -n "$udid" ] || { echo "no simulator named '$name' (see CLAUDE.md for how they were created)" >&2; exit 1; }
  echo "== $name ($size) $udid"
  xcodebuild test -project op1-lfo-hero.xcodeproj -scheme op1-lfo-hero -destination "id=$udid" \
    -only-testing:op1-lfo-heroUITests/ScreenshotTests 2>&1 \
    | grep -E "error:|Executed [0-9]+ tests, with|TEST (SUCCEEDED|FAILED)" | tail -2
  count=0
  for f in "$TMP/ss_${name}_"*.png; do
    [ -e "$f" ] || { echo "no screenshots written for $name" >&2; exit 1; }
    w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
    if [ "${w}x${h}" != "$size" ]; then
      echo "wrong size for $f: ${w}x${h}, expected $size" >&2; exit 1
    fi
    count=$((count + 1))
  done
  echo "   $count screenshots, all $size"
done

# Everything captured and checked: replace the upload folder.
rm -f "$OUT"/*.png
for f in "$TMP"/ss_*.png; do
  b=$(basename "$f"); b=${b#ss_}
  # ss_<device>_01_main.png -> <device>-01_main.png (the name fastlane/deliver expects)
  cp "$f" "$OUT/$(echo "$b" | sed -E 's/_([0-9][0-9]_)/-\1/')"
done
ls "$OUT"
echo "Look at every image in $TMP before uploading."
