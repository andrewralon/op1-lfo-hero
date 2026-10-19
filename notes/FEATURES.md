# Features (iOS)

> Multi-device support (op-1 field / tx-6 / tp-7) has its own status file:
> [FIELD_DEVICE_SUPPORT.md](FIELD_DEVICE_SUPPORT.md) — what is done, what is untested, and what
> is still only assumed. Protocol detail is in [RESEARCH.md](RESEARCH.md), and planning documents
> (deferred, shipped and superseded) are in [PLANS.md](PLANS.md).

## To fix
- [ ] LOW - the tempo limit is one global, `AppState.maxBpm` (440, the highest of te's own: op-1 field 440, tx-6 400, tp-7 shows 200 but is assumed to cope with 400, not tested), with `AppState.minBpm` (20) as the floor, and nothing else in the app hard-codes a bpm limit. make it a per-device capability in `DeviceCapabilities` (data-driven, like the rest of the profile) if a device ever needs a tighter one. found 2026-10-18: a tx-6 at 400 bpm over ble showed 300.0 because readings above the old 300 ceiling were ignored
- [ ] MED - disconnecting a ble device in the picker removes it from the list, but it should stay listed if it is still available: disconnect should only clear the green box and change the status, and the device remains a row to tap again. cause: `BLEMidi.didDisconnectPeripheral` calls `forgetDiscovered(p)`, which drops the peripheral from `discovered` and `discoveredIds` straight away, and it only comes back when a fresh advertisement is seen (a device may take a while to advertise again after a disconnect). fix idea: keep it listed on disconnect and give it a fresh `lastSeen`, so the staleness check (5 s without an advertisement, picker open) decides whether it is really gone; consider a longer grace after a disconnect because a device can be slow to resume advertising. found 2026-10-18 on an ipad with a tx-6 over ble
- [ ] MED - tp-7: confirm whether recording creates a new take or can overwrite the current one. observed as non-destructive (new track) in one test, but the guide's record menu section is images-only and could not be read. if there is an overwrite setting, the app must warn before arming record
- [ ] LOW - tp-7: expose the scrub speed in the ui. holding ⏪/⏩ now ramps 1x → 14x over 1.5s (14x is where CC 18 saturates), but the ramp shape is only editable in code — see `scrubStartSpeed` / `maxScrubSpeed` / `scrubRampSeconds` in ClockEngine
- [ ] LOW - tp-7: `ClockEngine.deviceIsRolling` (detects a hand-started tape from incoming clock, so the first play press flips direction instead of being absorbed) has never fired — the tp-7 sends no clock over ble. may work over usb-c, untested
- [ ] LOW - tp-7: input gain only exists on channels 1-3 — grey it out on 4-6 rather than just hiding the binding
- [ ] LOW - tp-7: listen to its controller-mode outgoing CCs as app input (cc 20-26, memo cc 27, the mode button on cc 28 (undocumented), wheel cc 30, rocker pitch bend). NOTE: ctrl mode blocks ALL incoming midi, so the app could receive but not send while in it
- [ ] LOW - device auto-detect matches on endpoint name only; CoreMIDI also exposes manufacturer ("teenage engineering") and model — use as a fallback for hubs with generic port names
- [ ] MED - hit stop twice quickly to return to tape start CC 84, >= 64
  * NOTE: this must also reset `ClockEngine.hasStarted` to false, so the next play sends Start (0xFA, from the beginning) rather than Continue (0xFB, resume). the comment in ClockEngine near `rewindPending` already claims this happens — it does not, because the feature isn't built yet. rewinding without resetting the flag would rewind the tape but resume from the old position.
- [ ] MED - start and stop lfos automatically, with start/stop buttons, in time with the op1 tempo
- [ ] MED - show the scrub UI boxes differently so it's obvious they are scrubbable (vs dropdown, for example) - 2 thin vertical lines next to box? Different color border (white vs gray)? BEST: Single thin vertical white line just to the right of the box
  * fun idea - BPM box could use a way to show the user it can be scrubbed. maybe like it's a big rotating wheel or an old analog clock. maybe clip the top and bottom of the next entries so they're cut off at the edges of the box?
- [ ] MED - pan knob is weird (scrubs up and down, not turning or left-to-right). Not sure how to fix it cause there's no room to scrub horizontally on the screen.
  * tap pan -> open modal with horizontal slider and grip fader thingy? Hmmm.... TWO TAPS: 1 opens modal, 2 slides fader. let go makes it close automatically.
  * no other obvious solution
- [ ] MED - pause or stop LFO chaos - maybe stop button should stop lfo activity while setting up new LFOs cause it's distracting. Play should start it. Or a better way?
- [ ] MED - rate/speed needs all of the OP-1 options - 25 options (in order): 8 to 1 (relative tempo time) + 17 for clock symbols 0 to 30 minutes (absolute time)
- [ ] LOW - add parameter: SOUND SLOT SELECT - CC 102, channel 1-8, >=64 *****
- [ ] LOW - add parameter: SYNTH PITCH BEND - channel 1-16, 0-16383
- [ ] LOW - add parameter: OCTAVE - CC 79, < 64 = down, ≥ 64 = up
- [ ] LOW - add parameter: MASTER EQ low/mid/high - CC 90-92, 0-127
- [ ] LOW - add parameter: SUSTAIN - CC 64, >= 64 = down
- [ ] LOW - add parameter: LOOP IN/OUT/TOGGLE - CC 86-88, 0-127
- [ ] LOW - depth & center spinboxes have no visual feedback for what they do since the waveform doesn't change.... not clear without trying it.
- [ ] LOW - icons: center could use some clarity

## Later (or not possible)
- [ ] tx-6: auto-pause an lfo chip when its hardware fader is grabbed (was MED). not possible: detecting the movement needs the tx-6 to transmit, and in `midi control = in`, the only mode where it accepts the app, it sends nothing (measured 2026-10-17, two 12 s windows). in `out` it reports its controls but ignores the app. the fight between the fader and an lfo stays, and the tx-6 setup text already says to pause the chip first
- [ ] tx-6: mirror its faders/knobs/track buttons into the app's mixer ui (was MED, raised from LOW on 2026-10-18, retracted the same day). `in` and `out` are exclusive on the device, so a mirror only works in `out`, where the tx-6 ignores the app and the app cannot run lfos on it, which is the point of the app. faders cc1-6 would be safe to mirror, knobs collide with the receive map, and the track buttons are momentary and stateless. only worth building as a display-only mode; seen 2026-10-18 that in `out` the tx-6's fader and mute did not move the app, by design (`mirrorsIncomingCC` is false)
- [ ] tx-6: read incoming CC 47 so the device's tempo encoder moves the app's bpm (was LOW). not possible, for the same reason as above: in `in` the tx-6 transmits nothing, and the app-to-device direction (the −/+ buttons) works
- [ ] tx-6: the app cannot see a transport started or paused on the device itself (was MED). cc 46 is a stateless toggle and the device sends nothing in `in`; its encoder button sends the same cc 32 for play and pause in `out`, and no start/continue/stop in either. confirmed 2026-10-18 that the app's play/stop do drive the sequencer (play starts it, play again restarts it, stop pauses it); the known desync is a press on the device followed by one in the app. accepted, and the tx-6 setup text says lfos restart only on a play pressed in the app
- [ ] LOW - fix left/right scrub mode if possible, like pressing them on the op1! tried and reverted, see commit history.

## Done
- [x] MED - the app's bpm readout flickered when slaved to a device over ble (a tx-6 at 80 bpm read 79.9 / 80.0 / 80.1, and 300.0 solid at 400). fixed 2026-10-18 and verified on an ipad with a tx-6 over ble at 60, 80, 120, 200 and 400 bpm: the tempo is now timed by the sender's own timestamps (ble-midi stamps every message with a 13-bit millisecond timestamp, measured sd 0.4 ms against 5.7 ms for arrival times), with the arrival time as the fallback for a tick whose stamp cannot be a real tempo; the averaging window is 32 ticks and 1 s when stamped (96 ticks and 3 s otherwise); a change of 2% or more restarts the average so a real change shows at once; the display snaps to a whole bpm and ignores moves under 0.15% of the tempo; and the bpm box is told of a new tempo at most 4 times a second (a jump of 2% or more is shown at once). also fixed on the way: stamped intervals of exactly 5 ms were dropped as arrival bursts and biased fast tempos low, a reading above 300 was ignored so 400 showed 300.0, and the tempo ceiling is now the single `AppState.maxBpm`
- [x] tx-6: play/stop in the transport row are kept (the plan to replace them with fx i / fx ii toggles is dropped). the blocking question was answered on 2026-10-18 with a tx-6 over usb-c in `midi control = in`: the app's play (cc 46 plus start/continue) starts the sequencer, play again restarts it, and stop pauses it, so they were never "doing nothing". adding fx i / fx ii toggles alongside them stays possible (`tx6.fx1.en` / `tx6.fx2.en` already exist as lfo parameters) but is not planned
- [x] HIGH - with two devices connected (an op-1 on ble and a tx-6 on usb-c) the layout, the status text and the midi routing could disagree, and a later connection could take over an active one. fixed 2026-10-17 and verified on an ipad in both connection orders: the first transport to connect owns the routing and keeps it, claimed at connect time (an op-1 in midi sync sends nothing, so waiting for a message let a later connection win); a device found while another is active is listed in the picker but never auto-connected; an explicit pick in the picker survives the connecting phase; when the owner disconnects, the other connected transport takes over by itself; and the layout (`AppState.profileId`) and the status follow the same transport as `MidiRouter.send`. also fixed on the way: the picker never redrew when a device was discovered while nothing else on AppState changed (it kept saying "scanning…"), and it now drops a bluetooth device that stopped advertising within about 5 s.
- [x] MED - switching the clock source to a device that isn't sending clock no longer freezes every lfo silently. in slave mode the device's ticks drive every lfo (chips, preview, free-rate too), so with none arriving they all stopped, and the only clue was a small `no clk` in the bpm box that only appeared when the tempo was exactly zero (a fresh slave still read 100.0). the lfo panel now shows "lfos paused — no clock from <device>. tap to use the app clock" over the waveform after 1.5 s without a tick, and a tap switches to the app clock. a flag rather than an automatic fallback: a tp-7 only sends clock while its tape moves, so a stopped tp-7 has none legitimately, and falling back would change a mode the user chose and hide a wrong op-1 tempo mode.
- [x] HIGH - ble: outgoing packets stamped every message with timestamp zero, so a tx-6 read the app's 24 ppqn clock as **640000 bpm**. bpm = 60 / (24 * interval), and every tick claimed to arrive at the same instant
- [x] HIGH - ble: the receive parser read timestamp bytes as clock/start/stop. timestamps span 0x80-0xFF, which includes 0xF8/0xFA/0xFC, so a stream of knob movements injected phantom transport — the wrong tempo was cosmetic, phantom start/stop would have moved the user's tape
- [x] HIGH - ble tested end to end. every tp-7 and tx-6 test on iphone ran over bluetooth, and both auto-detect by peripheral name (the status bar reads `tx-6 (ble)`), which closes the "names are guesses" risk
- [x] HIGH - tp-7: reverse playback calibrated against measured hardware rather than by ear. CC 18 turned out to be *additive* — it stacks on the device's own direction, so the same value gives 1.13x or ~3x depending on state the app cannot read. reverse now forces a known direction first and trims with pitch bend to land on a true 1x
- [x] MED - tp-7: `pitch bend` and `direction` are both lfo targets now, plus a `play` parameter that presses the play button. pitch bend turned out to be a *signed velocity offset* (~-20..+40 ticks/s), not the x0.25-x2.0 multiplier assumed here
- [x] MED - tx-6/tp-7: verified they act on what the app sends — volume, mute, gain, fx enables, transport and clock all confirmed on hardware
- [x] MED - tx-6: CC 120 mute polarity settled — absolute, and 127 = muted (not a toggle, which would have made an lfo stutter the channel at ~40 Hz instead of gating it)
- [x] MED - tx-6: relative encoder nudges were inverted and 63 steps too large. TE uses two's complement (1..63 up, 127..65 down) and the app sent `64 + delta`, so + read as -63 — reported from hardware as "+ halves the bpm and - doubles it"
- [x] MED - tx-6 can be the tempo source after all (`clock SRC` internal + clock `out`): 32.00 ticks/s measured against a device reading 80 bpm. it was marked as never sending clock from a capture taken in the default configuration
- [x] LOW - volume digits were clipped in landscape on both iphone and ipad — the font was sized from the track column instead of the space the digits actually occupy inside the fader. also gives them clearance from the thumb, so the value is no longer hidden by it
- [x] HIGH - end-to-end: app auto-detects a tp-7 over usb and drives it, including a working volume lfo. verified on iphone
- [x] HIGH - tp-7: play sent CC 14 — which is RECORD on that device, so pressing play would arm recording over a take. now real-time transport only
- [x] HIGH - tp-7: prev/next modelled CC 18 as a momentary nudge when it is a persistent bipolar speed state, so they started the tape moving and never stopped it
- [x] HIGH - play always sends Continue (0xFB) so the tape resumes; only an explicit rewind sends Start (0xFA). previously the first play of a session silently rewound the tape
- [x] HIGH - multi-device support: DeviceProfile abstraction (op-1 field / tx-6 / tp-7), one device at a time
- [x] HIGH - dynamic track count 1..N (6 for tx-6/tp-7), incl. toggle-row wrap on iphone portrait
- [x] HIGH - settings schema v1 + non-destructive decode. previously ANY added field made the whole decode throw and silently wipe every saved chip, because Swift's synthesized Decodable ignores property defaults
- [x] MED - manual device override in settings (hubs / generically-named midi ports)
- [x] MED - per-device saved state (volumes/pans/mutes/trackOn/chips) keyed by profile id, so unplugging one device and plugging in another doesn't destroy your chips
- [x] MED - tx-6 fx bus params (ch 8/9) folded into the master slot
- [x] MED - Controller held its own mute state that could drift from AppState.mutes — collapsed to one source of truth
- [x] LOW - CompactPicker portrait popover couldn't scroll, so long parameter lists were unreachable
- [x] LOW - add parameter: ENVELOPE x4 - CC 50-53, 0-127 (already implemented; item was stale)
- [x] HIGH - reorder text for active lfo's to be same order as UI - `t1*volume*sine` (not `sine*volume*t1`)
- [x] HIGH - volume values don't match (app to op1) - off by 1 here and there
- [x] MED - disable all button animations / transition times. just flipping toggle the button fast! this doesn't seem to be working: ".animation(.none, value: state)"
- [x] MED - play button enabled in all modes — sends MIDI signal regardless of clock mode; does not reflect OP-1 transport state (previously disabled in OP-1 mode; later re-enabled because it does start OP-1 tape playback in MIDI sync mode)
- [x] MED - icons: metronome is too tall compared to row elements. remove text and center vertically?
- [x] MED - icons: parameter umbrella??? -> replace with thunderbolt / lightning
- [x] MED - volume fader grip shape (square at 45 degree angle) is weird and too tall. make it a flatter rhombus / baseball diamond, like what python had
- [x] HIGH - help page: minimal instructions and information
- [x] HIGH - settings page: in case i ever need one
- [x] HIGH - splash screen / startup screen
