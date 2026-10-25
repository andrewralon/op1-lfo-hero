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
- [x] sustain (CC 64), pitch bend (channel 1), master EQ (CC 90-92) and record level (CC 78) measured from a Mac over BLE with `tools/midi/sweep` (2026-10-23). See "Hardware findings — OP-1 Field global controls" in RESEARCH.md.
- [ ] rec level, eq low/mid/high, sustain and pitch bend from the app on the iPad: each is offered under the master (m) target only; a slow LFO on each is audible and the OP-1 screen follows (EQ knobs, the red record-level line)
- [ ] stopping or pausing each of those chips on `previous` returns it to neutral: EQ flat, sustain released, record level back to 95, no bend left. `hold` leaves it where the LFO was, by design
- [ ] a pitch bend LFO is smooth (no 128-step staircase) and ends on exactly 8192; a one-shot finishes on 8192 too
- [x] sustain does nothing to tape playback; it only holds live notes on the selected instrument (2026-10-25)
- [ ] **TP-7:** speed bend returns to exactly x1.0 when its LFO stops, and a saved TP-7 bend chip from an older build still sweeps the same range after the 14-bit migration (settings v2 -> v3)

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
- [x] the app's play and stop drive the TX-6 sequencer (CC 46 plus Start/Continue): play starts it, play again restarts it, stop pauses it (2026-10-18)
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
- [x] scrub from a parked tape: hold ⏩ about 3 s, about +26 s on the counter, stops on release (2026-10-18)
- [x] scrub backwards from a parked tape, about -26 s, stops on release (2026-10-18)
- [x] scrub while the tape is rolling, forward and back; ramps from normal, returns to 1x and keeps playing on release (2026-10-18)
- [x] stop after a scrub from a parked tape **rewinds to 0:00**: by design, a Stop on a stopped TP-7 does that, and the TP-7's own stop button does the same (2026-10-18); documented in the TP-7 setup text
- [x] preview off / parameter switch / deleting a chip put a TP-7 parameter back (volume) (2026-10-18)
- [x] TP-7 on USB-C plus a **TX-6 on BLE** (2026-10-18, iPad Pro; an OP-1 was not used): the TX-6 listed in the picker unconnected, an explicit pick switched the layout and routing together and held, app fader and mute moved the TX-6, and unplugging the TP-7 handed over to the TX-6 by itself. Not done: the TX-6's own fader and mute moving the app in `out` mode (not supported, see FEATURES.md)
- [x] **parameter pass** (2026-10-18, iPad Pro, USB-C, `midi control = in`, `app (midi sync)`): faders, pan,
      mute and gain on tracks 1-6; filter, eq high/mid/low, comp; fx1/aux/aux2 send; syn wave/freq/len/
      detune and seq pattern; main/aux/cue vol; fx1 and fx2 enable, engine, p1-p3, fx1 return, fx2 track;
      and local control (off: the physical faders stop affecting the sound; on: they work again; a preview
      with the center above 64 always leaves it on). Every one moves the right control
- [x] TX-6 over BLE (2026-10-18): the mixer CCs worked from the start, but play/stop and tempo did nothing
      with `clock SRC = usb`: the TX-6 only accepts clock and Start/Stop from the source it is set to, and
      its `clock src` menu offers `int`, `usb`, `ble` and `tr1`-`tr6`. With **`clock src = ble`** the app's
      play starts, restarts and stops the sequencer and the TX-6's tempo follows a live BPM drag. The
      TX-6 setup text now says `usb` over USB-C and `ble` over Bluetooth

