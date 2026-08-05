# Field device support — status and remaining work

Tracks the multi-device feature (OP-1 Field / TX-6 / TP-7) on `feature/support-field-devices`.

Protocol details and hardware measurements live in [RESEARCH.md](RESEARCH.md). This file is
just what is done, what is not, and what is still only assumed.

**Current state:** 104 unit tests, 20 UI tests. TP-7 validated end to end through the app.
OP-1 and TX-6 not yet run through the app on hardware.

---

## Done

### Architecture
- [x] `DeviceProfile` abstraction — devices are data, not branches. Every CC number in the app
      lives in `DeviceProfiles.swift` and nowhere else
- [x] `ParamSpec` with separate track/master bindings, so a parameter can exist in both places
      on different CCs, or only one
- [x] `ChannelRule.pinned` for channels outside the track range (TX-6 master + FX buses)
- [x] `ValueEncoding` — continuous / switching / relative / enumerated, so device quirks are
      data rather than code paths
- [x] `TransportMap` + `TransportOp` — per-device transport, including the TP-7's persistent
      bipolar seek and the TX-6's stateless start/stop toggle
- [x] `DeviceCapabilities` — hasPan, canBeClockMaster, followsClock, mirrorsIncomingCC
- [x] Dynamic track count (4 or 6) throughout `LayoutMetrics` and the UI
- [x] LFO target row wraps to two rows rather than overflowing the 44pt touch target
- [x] Per-device saved state, keyed by profile id — switching devices banks state instead of
      destroying it
- [x] Settings schema v1 with hand-written non-destructive decoders
- [x] Device auto-detection by endpoint name, with a manual override in settings
- [x] `--uitest-profile <id>` launch argument so 6-track layouts can be tested without hardware

### Profiles
- [x] **OP-1 Field** — 4 tracks, 20 parameters, proven byte-identical to the pre-refactor app
      by a golden byte table
- [x] **TX-6** — 6 tracks, 33 parameters, master bus on ch 7, FX I/II on ch 8/9 folded into
      the master (m) target
- [x] **TP-7** — 6 tracks, mix volume/mute, three input-jack gains, record/cue/loop

### Bugs fixed
Found by refactoring:
- [x] Any settings schema change silently wiped every saved chip — Swift's synthesized
      `Decodable` ignores property defaults, so one added field made the whole decode throw
- [x] `Controller` held its own mute state that could drift from `AppState.mutes`
- [x] The parameter popover could not scroll in portrait, so long lists were unreachable

Found by hardware testing — **all five would have shipped**:
- [x] TP-7 play sent `CC 14`, which is **record** — pressing play would arm recording over a take
- [x] TP-7 prev/next modelled `CC 18` as a nudge when it is a persistent state, so they started
      the tape and never stopped it
- [x] First play of a session sent Start (`0xFA`) instead of Continue, silently rewinding the tape
- [x] Stop sent a redundant CC that the TP-7 reads as a double-stop, throwing away the position
- [x] TP-7 input gain modelled as a track parameter when it addresses the three input jacks

### Hardware validation — TX-6 (by script, over USB)
- [x] Acts on incoming CC; channel mapping and CC numbers confirmed
- [x] `midi control` modes are mutually exclusive: `in` receives, `out` transmits, `X` neither
- [x] Requires `midi control = in` and `clock SRC = usb` — surfaced in the app's help
- [x] Mute `CC 120` is absolute, 127 = muted
- [x] FX bus on pinned channel 8 works; FX enable is global, per-channel send is separate
- [x] Sends no MIDI clock (~12 minutes of monitoring, zero ticks)
- [x] Transmit and receive maps collide (knobs 1-3 transmit CC 7/8/9 = volume/pan/gain inbound)
- [x] Physical faders fight an LFO rather than taking over — last writer wins

### Hardware validation — TP-7 (by script, over USB)
- [x] All four `midi` modes mapped; only `ctrl` blocks input, and it blocks *everything*
- [x] **Sends MIDI clock** in `sync` mode — undocumented; `canBeClockMaster` is true
- [x] `CC 18` is a persistent bipolar speed state that must engage before `64` means stop
- [x] Offset 4 from centre = 1x playback; speed modelled as a multiplier
- [x] Play resumes (`0xFB`); a second stop rewinds — the device implements double-stop itself
- [x] Mute `CC 120` absolute, 127 = muted
- [x] Input gain linear in dB, 0 to +42 dB, addressing the three input jacks
- [x] Loop is a state machine — `out` without `in` is discarded
- [x] Record arms rather than records; arm + play does record; arm is absolute, not a toggle
- [x] `ctrl` mode transmits the full control surface; found an undocumented `mode` button on CC 28
- [x] Cue subsystem (CC 16 and note-triggered markers) has no observable effect in any mode

### End-to-end
- [x] **TP-7 driven by the app on iPhone over USB** — auto-detect, 6 strips, no pan knobs,
      profile transport symbols, faders reaching the device, and a working volume LFO

### Documentation
- [x] `RESEARCH.md` — full CC tables, hardware findings, and an at-a-glance table of the six
      places the published references are wrong
- [x] `CLAUDE.md` — device list, 6-colour palette, new accessibility ids, and the fact that
      MIDI cannot be tested in the simulator at all
- [x] In-app help shows per-device setup steps (`setupSteps`)

---

## Still to do

### 🔴 High — untested paths that could be broken right now

- [ ] **Run the OP-1 on hardware.** Its entire MIDI path was rewritten. The golden byte table
      proves the model is self-consistent; it does not prove the OP-1 agrees. Check: volume /
      pan / mute on all 4 tracks, master fx and compressor, tape prev/next, clock in both
      directions, and an LFO running
- [ ] **Decide whether play-resumes applies to the OP-1.** Play now sends Continue rather than
      Start, so the first play no longer rewinds. Applied to all devices; not yet judged on the
      OP-1. Reversible — move it into `TransportMap` if it should be per-device
- [ ] **Run the TX-6 through the app.** Protocol is verified by script but the UI has never
      driven it. Bigger profile than the TP-7 (33 params, master bus, two FX buses), so more
      surface to get wrong. Needs `midi control = in` on the device
- [ ] **Test BLE.** Nothing has been tested over Bluetooth. The peripheral names for TX-6 and
      TP-7 are guesses — if they differ from the USB names, auto-detect silently fails and the
      user has to find the manual override. The TX-6 may not expose BLE MIDI at all

### 🟠 Medium — verifying things currently taken on trust

- [ ] **TX-6: 13 per-channel parameters never sent** — filter, EQ high/mid/low, comp, synth
      wave/freq/len/detune, fx1 send, aux send, aux2 send, seq pattern
- [ ] **TX-6: master bus never sent** — main vol, aux vol, cue vol, local control
- [ ] **TP-7: does recording overwrite or create a new take?** Observed non-destructive (new
      track) in one test, but the guide's record menu is images-only and could not be read. If
      an overwrite setting exists, the app must warn before arming record
- [ ] **TP-7: transport in `cue` mode** — the last empty cell in the mode table
- [ ] **TX-6: does it follow MIDI clock?** It never sends clock, but following is untested
- [ ] Verify the 6-track layout on iPad, both orientations. Only iPhone has been checked on
      hardware; iPad has simulator screenshots only

### 🎛️ Requested TP-7 parameters and transport behaviour — implemented, needs hardware testing

All seven are built and unit-tested. **None have been tried on the device yet.**

- [x] **1. Speed parameter** (`tp7.speed`) — pitch bend, 0-127 mapped across the full 14-bit
      range so an LFO sweeps x0.25 to x2.0, with 64 at centre
- [x] **2. Direction parameter** (`tp7.direction`) — two-state on `CC 18` like mute: above the
      threshold 68 (forward 1x), below 60 (reverse 1x). Never emits an intermediate value
- [x] **3. Tempo parameter** (`tp7.tempo`) — `.virtualTempo`, retunes the app's clock, which the
      TP-7 follows in `sync` mode. `hasTempoParam` flipped to true
- [x] **4. Play/stop parameter** (`tp7.play`) — new `ParamBinding.transport` case for real-time
      messages. **Edge-triggered**, so a sustained LFO value does not re-fire every clock tick
- [x] **5. Record sequence** (`tp7.recSeq`) — stop (only if playing), arm, play. Off stops and
      disarms. ⚠️ Destructive, so kept out of the LFO picker
- [x] **6. Play reverses when already playing** — `caps.playReversesWhenPlaying`, TP-7 only.
      Reverses at 1x, since it is a playback change rather than a seek
- [x] **7. Momentary scrub** — `ScrubBtn` / `ScrubColBtn` act while held, starting at 1x and
      ramping to 8x over ~3s, returning `CC 18` to centre on release and restoring the user's
      configured speed. Falls back to a single nudge on the OP-1

Still to verify on hardware:
- [ ] Does the speed parameter actually sweep playback rate, and does an LFO on it sound musical?
- [ ] Does direction switch cleanly, or does it click/glitch at the crossover?
- [ ] Does tempo modulation actually move the TP-7 (needs `sync` mode)?
- [ ] Does play/stop as an LFO target gate playback usefully, or is it too abrupt?
- [ ] Does the record sequence reliably start a recording?
- [ ] Does play-reverses feel right, or should it reverse at the current speed rather than 1x?
- [ ] Does the scrub ramp feel right — 1x to 8x over 3s, or too slow/fast?

### 🟡 Low — features and polish

- [ ] **Wire up double-stop to rewind.** `ClockEngine.rewindToStart()` exists and is tested but
      nothing calls it. The OP-1 also needs `CC 84` in its transport map. Note the TP-7 already
      does this itself, so only the OP-1 needs the app to implement it
- [ ] **TP-7 pitch bend as a playback-speed parameter.** Verified as an independent x0.25-x2.0
      multiplier. `ParamBinding.pitchBend` exists unused. Must return to centre (8192) on stop,
      or a stray value silently pitch-shifts everything with no on-screen feedback
- [ ] **TP-7 reverse playback as a real control.** Reachable via `CC 18` below centre and
      verified working, but there is no explicit direction control in the UI
- [ ] **Expose `ClockEngine.transportSpeed` in the UI** — how fast prev/next move the tape.
      Currently fixed at 2x
- [ ] **Read the TX-6's control surface as app input.** Its faders/knobs/buttons transmit a full
      map on ch 1 in `out` mode. Would need a separate transmit table, since it collides with
      the receive map — and `out` mode means the app cannot send while listening
- [ ] **Read the TP-7's controller-mode CCs as app input** (cc 20-27, mode cc 28, wheel cc 30,
      rocker pitch bend). Same caveat: `ctrl` blocks all output
- [ ] **Detection fallback on manufacturer/model.** CoreMIDI exposes `teenage engineering` and
      the model name; currently only the endpoint display name is matched, which fails for hubs
      that rename ports
- [ ] **TP-7: grey out input gain on tracks 4-6** rather than hiding it, now that gain is known
      to address jacks rather than tracks
- [ ] Document the TX-6 fader-fight behaviour in help — grabbing a fader while an LFO runs on
      that channel produces stuttering, not takeover

### ⚠️ Known hazards to keep in mind

- [ ] **`CC 120` is standard MIDI "all sound off".** The TX-6 and TP-7 reuse it per channel for
      mute, so sending it will also silence unrelated gear sharing a hub. Not currently guarded
- [ ] **TX-6 `CC 46` is a stateless toggle.** The app gates it on its own `isPlaying`, which can
      desync if the user starts the transport from the device panel
- [ ] **TP-7 record is reachable over MIDI.** `CC 14` + play records. `tp7.rec` is marked
      non-LFO-targetable, but the capability exists

---

## Deliberately excluded

- [x] **`tp7.loop`** — a state machine; an LFO sweep would discard most values and drop loop
      points at arbitrary moments
- [x] **`tp7.cueRec`** — no observable effect, and unverifiable on a device that never reports
      its state
- [x] **`tp7.rec`** — automating a record arm has no musical use and can destroy a take
- [x] **TX-6 `CC 47` (tempo relative)** — a relative encoder, so an LFO would drift the tempo in
      one direction forever instead of oscillating. Reachable from the transport buttons only
- [x] **Per-device display scale** — the app shows 0-99 on every device by design, so there is
      deliberately no scale knob on `DeviceProfile` that could let them diverge
