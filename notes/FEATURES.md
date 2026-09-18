# Features (iOS)

> Multi-device support (op-1 field / tx-6 / tp-7) has its own status file:
> [FIELD_DEVICE_SUPPORT.md](FIELD_DEVICE_SUPPORT.md) — what is done, what is untested, and what
> is still only assumed. Protocol detail is in [RESEARCH.md](RESEARCH.md), and planning documents
> (deferred, shipped and superseded) are in [PLANS.md](PLANS.md).

## To fix
- [ ] MED - tp-7: confirm whether recording creates a new take or can overwrite the current one. observed as non-destructive (new track) in one test, but the guide's record menu section is images-only and could not be read. if there is an overwrite setting, the app must warn before arming record
- [ ] LOW - tp-7: expose the scrub speed in the ui. holding ⏪/⏩ now ramps 1x → 14x over 1.5s (14x is where CC 18 saturates), but the ramp shape is only editable in code — see `scrubStartSpeed` / `maxScrubSpeed` / `scrubRampSeconds` in ClockEngine
- [ ] MED - tx-6: grabbing a hardware fader while an lfo drives that channel makes the audio fight (last writer wins, ~40 values/sec from the lfo). consider auto-pausing the chip for a channel when incoming movement is detected on it — or at minimum say so in help
- [ ] LOW - tx-6: its faders/knobs/track buttons transmit a full control-surface map on ch 1 (faders cc1-6, knobs cc7-24, track buttons cc25-30). could drive the app's mixer UI from the hardware — needs a separate transmit table, since it collides with the receive map (see RESEARCH.md)
- [ ] MED - switching the clock source to the device silently freezes every lfo if that device is not transmitting clock. the only clue is a small `no clk` in the bpm box, nowhere near the lfo panel. cost a real debugging session — flag it where the lfos are, or fall back to the app clock and say so
- [ ] LOW - tp-7: `ClockEngine.deviceIsRolling` (detects a hand-started tape from incoming clock, so the first play press flips direction instead of being absorbed) has never fired — the tp-7 sends no clock over ble. may work over usb-c, untested
- [ ] MED - tx-6: CC 46 is a stateless start/stop toggle, so app and device transport can desync if play is pressed on the device
- [ ] MED - tx-6: replace the play/stop buttons with FX I / FX II toggles, matching the two buttons on the device. spec in [PLANS.md](PLANS.md) — blocked on confirming CC 46 does anything, since play/stop also send the start/stop a clock-slaved sequencer needs
- [ ] LOW - tp-7: input gain only exists on channels 1-3 — grey it out on 4-6 rather than just hiding the binding
- [ ] LOW - tp-7: listen to its controller-mode outgoing CCs as app input (cc 20-26, memo cc 27, the mode button on cc 28 (undocumented), wheel cc 30, rocker pitch bend). NOTE: ctrl mode blocks ALL incoming midi, so the app could receive but not send while in it
- [ ] LOW - tx-6: read *incoming* CC 47 so turning the device's tempo encoder moves the app's bpm. the reverse now works (the app's −/+ nudge the app's own bpm while it is clock master, and the device follows), but nothing listens — and the tx-6 transmits nothing while `midi control` is `in`
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
- [ ] LOW - fix left/right scrub mode if possible, like pressing them on the op1! tried and reverted, see commit history.

## Done
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
