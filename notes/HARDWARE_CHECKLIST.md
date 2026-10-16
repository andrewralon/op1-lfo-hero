# Hardware checklist

Delivery to a device can only be confirmed by watching the device react — see "Hardware findings
— OP-1 Field transmit behavior" in `RESEARCH.md` for why. Build and install the current commit
first (`xcodebuild build`, confirm `** BUILD SUCCEEDED **`, then `devicectl device install app`).
Needs `iPad Pro Dawg` with the device on USB-C. Record the commit, the date, and the tempo mode.

## OP-1 Field
- [x] track 1 mute from the app mutes track 1 on the OP-1; tapping again unmutes (2026-10-16, USB)
- [x] volume 100 (MIDI) shows 77 on the OP-1 (`v * 99 // 127`) (2026-10-16, Mac probe, USB and BLE)
- [x] volume, pan and mute on tracks 1-4 (2026-10-16, iPad USB, midi sync)
- [x] master FX and compressor (fx 1-4 and lfo 1-4 on master, via LFO; 2026-10-16, USB)
- [x] tape prev / next (absolute position from the app's counter, not relative to the parked tape; 2026-10-16, USB)
- [x] play sends Continue and the OP-1 resumes from the last *synced* position, not a hand-parked one (documented in RESEARCH.md; midi sync only, beat match ignores app transport)
- [x] stop stops it
- [ ] clock both ways: beat match (OP-1 master) and midi sync (app master)
- [x] an LFO running on a track parameter (2026-10-16, volume, master fx, compressor)
- [x] play restarts every active LFO from the start of its cycle: pressed on the OP-1 (beat match; Start after a double stop, Continue after a single stop) and in the app (midi sync) (2026-10-16, USB)
- [ ] upgrade install over an older build keeps settings (Keychain migration)
- [ ] same checks over BLE

## Probing from a Mac (`tools/midi/`)
Plug the device into the Mac, not the iPad. `./mididiag` first (stale endpoints look like a silent
device), then `./anymidi <name> 5` to listen and `./cc18map <name> raw <b0> <b1> <b2>` (decimal) to
send. 5 seconds is enough. Do a positive control before trusting any silence.
