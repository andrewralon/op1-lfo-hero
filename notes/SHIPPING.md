# Shipping a new version

The things to change or check every time a build goes to the App Store. Copy the list into a
scratch plan for the release, tick it off there, and fix this file when a step turns out to be
wrong or missing.

Related, not repeated here: `HARDWARE_CHECKLIST.md` (what to try on a real device),
`RELEASE_READINESS.md` (a snapshot of the 1.1.0 release: its blockers and the reasoning),
`../ios/fastlane/README.md` (the lanes), and `../CLAUDE.md` ("Screenshots and simulator testing"
for the capture commands and the App Store slot sizes).

## 1. Decide what is shipping
- [ ] Everything for this release is merged to `main` and the working tree is clean.
- [ ] Open PRs that this release makes redundant are closed and their branches deleted.
- [ ] Pick the version. Is the current `MARKETING_VERSION` already live? Check App Store Connect
      (and TestFlight), not the repo: tags only record releases that were tagged. A new feature is
      a minor bump, a fix-only release is a patch.

## 2. Version numbers
- [ ] `MARKETING_VERSION` in `ios/op1-lfo-hero.xcodeproj/project.pbxproj` — **two places** (Debug and
      Release). The help sheet's version label reads it.
- [ ] Do **not** bump `CURRENT_PROJECT_VERSION`. The `beta` and `release` lanes ask App Store Connect
      for the last build and pass the next number as an xcarg, so the local value cannot drift.

## 3. Verify
- [ ] Unit tests: `cd ios && xcodebuild test -project op1-lfo-hero.xcodeproj -scheme op1-lfo-hero
      -destination 'id=<simulator-udid>' -only-testing:op1-lfo-heroTests 2>&1 | grep -E "error:|Executed .* tests"`
- [ ] Full UI tests, `-only-testing:op1-lfo-heroUITests` (slow). A "Simulator device failed to
      launch … Busy" is the known intermittent failure, not a test failure: rerun.
- [ ] A hardware pass on the iPad with the devices that changed (`HARDWARE_CHECKLIST.md`). The
      unit tests only prove the app agrees with itself, and the simulator has no MIDI and no
      Bluetooth. Anything that touches MIDI, BLE, clock or transport needs a real device.
- [ ] Anything marked "not yet on a device" in `FEATURES.md`'s Done entries for this release is
      either confirmed (and the entry updated) or called out in the release notes.
- [ ] Install the build on the iPad and the iPhone and use it for a few minutes. Layout changes
      should also be looked at on the other device class and in landscape.

## 4. Things that go stale
Check each against the release, not against memory.
- [ ] `ios/fastlane/metadata/en-US/release_notes.txt` — rewrite for this version.
- [ ] `description.txt`, `promotional_text.txt`, `subtitle.txt`, `keywords.txt` — still true? New
      devices, new parameters or new behaviour that belongs in the listing. The description
      states the minimum iOS version; compare it with the deployment target in the project.
- [ ] `notes/APP_STORE.md` — the human-readable copy of the listing. Update its "What's New".
- [ ] The site (`docs/`): the "what's new" section of `docs/index.html`, the setup sections, and
      `docs/support.html` troubleshooting if a status string or a setting changed. GitHub Pages
      builds from `main`, so it goes live when the PR merges, which may be before the App Store
      version does.
- [ ] `NSBluetoothAlwaysUsageDescription` (in `project.pbxproj`, two places) and
      `ios/PrivacyInfo.xcprivacy` — still accurate for what the app now does.
- [ ] In-app help copy and the tutorial (`HelpCopy` in `ContentView.swift`), if controls changed.
- [ ] `CLAUDE.md` — the identifier list, device table and rules, if they changed.

## 5. Screenshots and previews
Only when the visible UI changed enough to matter. App Store Connect needs a set for each slot, and
filling one slot does not fill the others. See `CLAUDE.md` for the simulators, sizes and the
file-name rules.
- [ ] `ios/fastlane/capture_screenshots.sh`, then **look at every image** in `/tmp/claude-ss/`.
- [ ] `cd ios && fastlane upload_media overwrite:false`.
- [ ] Never pass `overwrite_preview_videos` unless every device set's preview is being replaced: it
      deletes them all and Apple reprocesses for up to 24 hours.
- [ ] After a preview upload, pick the poster frame in App Store Connect once it finishes processing.

## 6. Build, test, submit
1. `cd ios && fastlane whatif` previews the commit list the TestFlight notes will carry;
   `fastlane beta` builds, uploads to TestFlight and tags `beta/<build>`.
2. Install the TestFlight build on the iPad and iPhone and run the hardware checks on **that**
   build, not on a debug one.
3. `fastlane release build:<build>` — submits the build that was just tested, with the metadata
   in `fastlane/metadata`. It has `automatic_release: true`, so **it goes live the moment Apple
   approves it**. Turn that off in the lane (or in App Store Connect) if the release should wait.
   Plain `fastlane release` builds a new build number first.
- [ ] In App Store Connect, check the version page before and after: build selected, release notes,
      screenshots in every slot, and nothing left in "Prepare for Submission" or "Rejected".

## 7. After it is live
- [ ] Tag the release commit on `main`: `git tag v<marketing-version> && git push --tags`.
- [ ] Close the issues the release resolved, and move finished items under `## Done` in `FEATURES.md`.
- [ ] Update `RELEASE_READINESS.md`, or replace it with the next release's snapshot if one was written.
- [ ] Clean up what the release left around: local build folders, test simulators, merged branches.
