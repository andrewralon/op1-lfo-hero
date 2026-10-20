# MIDI hardware probes

Standalone Swift command-line tools for measuring what a field device actually does over USB
MIDI, rather than trusting a published reference or a listening test.

They live here because every one of them earned its keep: the TP-7 transport calibration in
`notes/RESEARCH.md` came out of these, and several published claims turned out to be wrong.
Keeping them checked in means the measurements are reproducible.

## Build

```bash
cd tools/midi
./build.sh            # compiles each .swift to a binary alongside it (gitignored)
```

Each file is self-contained — no package, no dependencies beyond CoreMIDI.

## The tools

| tool | sends? | what it answers |
|---|---|---|
| `mididiag` | no | what endpoints exist, which are stale, USB vs virtual, driver owner |
| `anymidi` | no* | is the device transmitting **anything**? live per-second counts by message type |
| `clockrate` | no | playback rate, live, from the sync-mode clock (44 ticks/s = 1x) |
| `clocksuppress` | yes | does sending clock TO the TP-7 suppress the clock it sends back? |
| `wheel` | no | live-streams CC 30 (the controller-mode wheel) to settle its sign encoding |
| `revsync` | yes | does CC 18 stack on the device's own direction, and can the app resync? |
| `playpress` | yes | replays the app's three play presses and measures each phase |
| `cc18map` | yes | maps CC 18 across transport states — parked vs playing, the +708 null, the bend curve; `raw <b0> <b1> <b2>` sends one arbitrary message through the same proven connection, for quick one-off diagnostics |
| `looptest` | yes | walks CC 17 (loop) through set-in/set-out/resend-while-active/release, with pauses to read the display |

\* `anymidi ... kick` sends a single `0xFB` partway through, to test whether transmission only
starts after a transport message.

```bash
./mididiag
./anymidi  TP-7 15            # add `kick` to send one 0xFB at 4s
./clockrate TP-7 30
./clocksuppress TP-7
./wheel TP-7
./revsync  TP-7 model         # does CC 18 stack?
./revsync  TP-7 fix2ear       # can stop-then-play force a known direction? (by ear)
./playpress TP-7
./cc18map TP-7 control        # what the app sends today, measured — run this first
./cc18map TP-7 stopped        # is there a dead zone with the tape parked?
./cc18map TP-7 bendhold 0 10  # hold one bend value while playing, exact elapsed time, for counter cross-checks
```

## The measurement trick

**In `sync` mode the TP-7 transmits MIDI clock derived from tape speed.** Counting `0xF8` ticks
per second therefore measures playback rate directly, turning a listening test into an
instrument. `44.0 ticks/s = 110 BPM = 1x`.

It is self-diagnosing: if the clock were a fixed project tempo it would not move when CC 18
changed. It moves proportionally, so it is tape-derived.

## Gotchas — every one of these cost real time

- **The clock is unsigned.** It measures speed, never direction. Direction always needs ears.
- **No clock while stopped.** A reading of 0 means "the transport is parked", *not* "the motor is
  not turning". The instrument goes blind exactly when the transport is stopped.
- **Never send `0xFC` twice.** A stop while already stopped rewinds the TP-7 to zero. An early
  version of one tool did this and produced a spurious "31s -> 0s" jump that looked like a scrub.
- **Average over 10 s or more.** One-second windows alternate between ~43.8 and ~44.8 as ticks
  land on window boundaries.
- **Stale endpoints.** Unplugging leaves an endpoint with the same name behind. Binding to it
  looks identical to a device that has stopped transmitting. All tools here skip `offline`
  endpoints; `mididiag` shows them.
- **The device itself can silently hang.** Once, mid-session, the TP-7 stopped responding to any
  incoming CC at all — `sync` mode confirmed on its own screen, endpoint confirmed online, bytes
  confirmed sent (down to routing them through a known-good binary to rule out the tooling) — and
  a reboot fixed it instantly, same bytes, same code path. If a previously-working CC suddenly
  does nothing and everything checks out, reboot the device before spending more time distrusting
  the mode setting or the tool.
- **The midi mode decides whether anything comes back at all:**

  | mode | receives CC | transmits |
  |---|---|---|
  | `off` | yes | nothing |
  | `sync` | yes | clock, while the tape is rolling |
  | `ctrl` | **no** | buttons and wheel, no clock; stops playback |
  | `cue` | yes | nothing |

  `off` and `cue` both receive while sending nothing — indistinguishable from a broken device
  unless you check. `ctrl` is the one mode that transmits without needing the tape to roll, which
  makes it the way to prove a receive path works.
