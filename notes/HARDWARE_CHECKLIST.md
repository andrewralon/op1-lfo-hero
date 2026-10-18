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
- [x] tape prev / next: CC-only relative nudges, like the OP-1's own buttons; keep playing while playing, stay stopped while stopped, and play afterwards resumes at the nudged position (2026-10-16, BLE; the old CC+SPP version snapped to the app's counter)
- [x] play sends Continue and the OP-1 resumes from the last *synced* position, not a hand-parked one (documented in RESEARCH.md; midi sync only, beat match ignores app transport)
- [x] stop stops it
- [x] clock both ways: beat match (OP-1 master) and midi sync (app master); the BPM box drives the OP-1 live while dragging (2026-10-16, USB)
- [x] an LFO running on a track parameter (2026-10-16, volume, master fx, compressor)
- [x] play restarts every active LFO from the start of its cycle: pressed on the OP-1 (beat match; Start after a double stop, Continue after a single stop) and in the app (midi sync) (2026-10-16, USB)
- [x] upgrade install over the App Store 1.0 keeps settings: parameter, wave, rate, depth/center, all chips (paused and inverted too) and track states (2026-10-16; volumes were never saved in 1.0, by design). See "Testing the settings migration" below.
- [x] same checks over BLE: run over BLE on 2026-10-16 were the connection (auto-connect, stays connected when the device picker opens and closes), tape prev/next, and Mac-probe mute/volume. Not run over BLE on the iPad: per-track volume/pan/mute, master FX and the LFO restart on play. Accepted as working without a run (owner's call: BLE is not a priority for the OP-1).

## Probing from a Mac (`tools/midi/`)
Plug the device into the Mac, not the iPad. `./mididiag` first (stale endpoints look like a silent
device), then `./anymidi <name> 5` to listen and `./cc18map <name> raw <b0> <b1> <b2>` (decimal) to
send. 5 seconds is enough. Do a positive control before trusting any silence.

## Testing the settings migration
The Keychain is read **first**, and it survives deleting the app, so the legacy UserDefaults copy
is only migrated when the Keychain item (`AppSettings`) is empty. Installing 1.0 over a device that
has ever run a Keychain-era build tests nothing: the new build reads the stale Keychain item and
ignores 1.0's save. And the app re-saves its settings ~0.5 s after every launch (every settings
publisher fires once on subscribe), so `--uitest-reset` clears the item and the app writes a default
one straight back.

What worked: (1) delete the `AppSettings` Keychain item from a throwaway on-device unit test that
waits ~2.5 s, deletes it, then `exit(0)`s the host so nothing re-saves; (2) with the real 1.0 save
still in UserDefaults, launch the new build. Check `Library/Preferences/<bundle id>.plist`
(`xcrun devicectl device copy from ... --domain-type appDataContainer`): the `AppSettings` key
disappears once it has been migrated. The throwaway test deletes real data on the device: do not
commit it.

## Two devices at once (layout, status and routing must agree)
- [x] (2026-10-17, iPad Pro, OP-1 on BLE + TX-6 on USB-C, both orders, plus picks and handover each way) OP-1 on BLE plus TX-6 on USB-C (and the other way round, and in each connection order): the
      layout (4 or 6 tracks and the parameter set), the status text and where a fader move
      actually goes must all change **at the same moment**, and all switch back together when one
      is unplugged. Was broken 2026-10-17 (status `op-1 (ble)` with the TX-6's 6-track layout);
      fixed and verified the same day. Not checked: a TP-7 in either role, and an iPhone.

## TX-6 (USB-C) — shared changes made on the OP-1
- [x] connects, 6 tracks, status `tx-6 (usb)` (2026-10-17, iPad Pro, `midi control = in`)
- [x] play pressed **in the app** restarts a running LFO from the start of its wave
- [x] play pressed on the TX-6 itself restarts nothing: **by design**, it sends no Start/Continue
      (`midi control = in` is silent; `out` sends a stateless CC 32); see RESEARCH.md
- [x] live BPM drag: the TX-6 follows the app's tempo while dragging (clock SRC = usb), smooth, settles on
      the app's value (2026-10-17, iPad Pro, USB-C)
- [x] preview off, a parameter switch during preview, and deleting a running chip put the TX-6
      parameter back (the app restores its own value, not the physical fader position) (2026-10-17)

## TP-7 (USB-C, `sync` mode) — shared changes made on the OP-1
- [x] connects, 6 tracks, `tp-7 (usb)`, no tempo parameter in the LFO picker (2026-10-18, iPad Pro)
- [x] **play pressed in the app restarts every running LFO on every press**, the ones that reverse the
      tape included. Before 2026-10-18 only the reversing presses did, by accident: the resync that
      precedes a reverse (`0xFC` then `0xFB`) makes the TP-7 answer with its own Start, and the press
      that goes forward again sends only `0xFB`, so it restarted nothing
- [x] an LFO driving the **`play` parameter** (`tp7.playPress`) presses play on each rising edge and
      does **not** restart the LFOs (it would restart itself); app presses still do
- [x] an LFO driving the **`direction` parameter** (`tp7.direction`) **does** restart the LFOs on every
      flip, from the same Start echo. Left as is: `play` reverses without a restart, `direction` with one
- [ ] scrub from a parked tape: hold ⏩ about 3 s, about +30 s on the counter, stops on release
- [ ] scrub backwards from a parked tape, about -30 s, stops on release
- [ ] scrub while the tape is rolling, forward and back; returns to normal speed on release
- [ ] stop after a scrub from parked does not rewind the tape to 0:00
- [ ] preview off / parameter switch / deleting a chip put a TP-7 parameter back (volume)
- [ ] OP-1 on BLE plus TP-7 on USB-C: first owns the routing, a later one never takes over, handover

