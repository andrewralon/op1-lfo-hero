# Hardware checklist

Delivery to a device can only be confirmed by watching the device react — see "Hardware findings
— OP-1 Field transmit behavior" in `RESEARCH.md` for why. Build and install the current commit
first (`xcodebuild build`, confirm `** BUILD SUCCEEDED **`, then `devicectl device install app`).
Needs `iPad Pro Dawg` with the device on USB-C. Record the commit, the date, and the tempo mode.

## OP-1 Field
- [ ] track 1 mute from the app mutes track 1 on the OP-1; tapping again unmutes
- [ ] volume 100 (MIDI) shows 77 on the OP-1 (`v * 99 // 127`)
- [ ] volume, pan and mute on tracks 1-4
- [ ] master FX and compressor
- [ ] tape prev / next
- [ ] play from a **parked** tape continues from there (play sends Continue `0xFB`, not Start)
- [ ] stop stops it
- [ ] clock both ways: beat match (OP-1 master) and midi sync (app master)
- [ ] an LFO running on a track parameter
- [ ] upgrade install over an older build keeps settings (Keychain migration)
- [ ] same checks over BLE

## Probing from a Mac (`tools/midi/`)
Plug the device into the Mac, not the iPad. `./mididiag` first (stale endpoints look like a silent
device), then `./anymidi <name> 5` to listen and `./cc18map <name> raw <b0> <b1> <b2>` (decimal) to
send. 5 seconds is enough. Do a positive control before trusting any silence.
