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
| `revsync` | yes | does CC 18 stack on the device's own direction, and can the app resync? |
| `playpress` | yes | replays the app's three play presses and measures each phase |

\* `anymidi ... kick` sends a single `0xFB` partway through, to test whether transmission only
starts after a transport message.

```bash
./mididiag
./anymidi  TP-7 15            # add `kick` to send one 0xFB at 4s
./clockrate TP-7 30
./revsync  TP-7 model         # does CC 18 stack?
./revsync  TP-7 fix2ear       # can stop-then-play force a known direction? (by ear)
./playpress TP-7
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
