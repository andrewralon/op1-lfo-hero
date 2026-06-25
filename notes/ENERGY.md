# energy efficiency research

audit conducted 2026-06-24. goal: reduce battery drain when the app is left open in the background.

---

## findings: what runs in the background

### 1. master clock timer (40 Hz) — `ClockEngine.fireMasterTick()`

when `isClockMaster = true`, a `DispatchSourceTimer` on `.userInteractive` QoS fires ~40 times/second (at 100 BPM × 24 PPQN). each tick:
- calls `router.send([0xF8])` — MIDI bytes dropped silently if no device connected (both transports guard against nil/unconnected)
- calls `automation.onTick()` — lightweight if no active LFOs, but still runs

this timer has no background suppression. it runs at full rate regardless of whether the app is connected, playing, or even visible.

**severity: high.** `.userInteractive` 40 Hz timer with no background pause is meaningful continuous CPU drain.

### 2. USB MIDI poll timer (every 2s) — `USBMidi.startPolling()`

a `DispatchSourceTimer` fires every 2 seconds when not connected and calls `recreateClient()`, which:
- disposes the CoreMIDI input port, output port, and client via IPC to MIDIServer
- recreates all three from scratch
- re-registers the notification block
- calls `scanForOP1()` (iterates MIDI destinations via more IPC calls)

**severity: high.** heavy IPC to MIDIServer every 2 seconds even in deep background. the `audio` background mode in `Info.plist` prevents iOS from suspending the app, so this runs indefinitely.

### 3. waveform viewer — `WaveformView`, `MultiWaveformView`

uses SwiftUI `Canvas`. **not animated.** draws once when inputs change (wave shape, rate, depth, active LFOs). no `TimelineView`, no `withAnimation` loop, no `CADisplayLink`. the only animated element in the app is `ColorfulSplashWave` in `HelpView`/`SettingsView`, which only runs when those sheets are open.

**severity: none.** no action needed.

### 4. MIDI output when disconnected

- `BLEMidi.send()` guards `p.state == .connected` — bytes dropped if not connected
- `USBMidi.send()` guards `destRef != 0 && outPort != 0` — bytes dropped if not connected
- BLE scanning is bounded: `startScan()` runs for 5s then stops

**severity: none.** no MIDI bytes transmitted when disconnected. BLE scan is time-bounded.

---

## proposed improvements

### A. pause the master clock timer when backgrounded

**how:** observe `UIApplication.willResignActiveNotification` / `didBecomeActiveNotification`. when entering background: call `masterTimer?.suspend()`. when returning to foreground: call `masterTimer?.resume()`.

**tradeoff:** if the user backgrounds the app while the OP-1 is actively slaved to it (clock master mode), the OP-1 clock will stall. this is arguably correct behavior — there's nothing useful happening when the user isn't looking. a connected OP-1 may lose sync momentarily and need to re-lock. acceptable.

**gain:** eliminates the largest continuous CPU cost during background use.

### B. increase timer leeway (USB poll)

**how:** change `.milliseconds(500)` → `.seconds(2)` on the `pollTimer` schedule call in `USBMidi.startPolling()`.

**tradeoff:** none visible. leeway doesn't change the nominal interval — it just gives the OS permission to slide the actual fire time by up to 2s to batch it with other scheduled wakeups. the poll still fires roughly every 2s but can be deferred to align with other timers, reducing actual CPU wake events.

**gain:** significant reduction in background wakeups at zero cost.

**can be done regardless of other changes.**

### C. two-tier polling: lightweight scan most ticks, full recreate rarely

**how:** most `pollTimer` ticks call `scanForOP1()` (a cache read — much lighter than IPC teardown). only call `recreateClient()` every Nth tick (e.g., every 5th = every 10s) to force a fresh cache.

**tradeoff:** if the notification system is fully reliable, this is unnecessary. if notifications are unreliable, this reduces the heavy teardown from 30/min to 6/min while still recovering within ~10s.

**gain:** major reduction in IPC load per background tick.

### D. scan on foreground + slow poll interval

**how:** observe `UIApplication.willEnterForegroundNotification` → call `recreateClient()` immediately. with this in place, lengthen the poll interval from 2s to 15-30s (or eliminate it entirely if notifications are reliable — see research below).

**tradeoff:** detection delay increases in the pathological case where a device is plugged in while the app is foregrounded but a notification was missed. that case is now caught on the next slow poll or next foreground.

**gain:** 10-15× fewer background wakeups from the poll timer.

---

## status

| item | status |
|---|---|
| USB poll timer (2s recreateClient loop) | **removed** — replaced with foreground rescan |
| master clock timer background pause | pending |
| timer leeway increase | superseded (poll removed entirely) |

---

## research: is the CoreMIDI notification unreliability assumption valid?

### background

the polling was introduced in commit `f4a881d` (2026-06-15) in a commit titled "fix USB detection/connection/re-connection after plug cycle". the comment in `startPolling()` says:

> "Even with a persistent run loop, CoreMIDI's add/remove notifications have proven unreliable across repeated connect/disconnect cycles on-device — they fire sometimes and not others, with no obvious trigger."

### what the git history actually shows

tracing the evolution of `USBMidi.swift`:

1. **early code** (`da037b9`, before June 15): `setupMIDI()` called on a throwaway `DispatchQueue.global()` thread. the thread exits the instant its block returns. `MIDIClientCreateWithBlock` ties notifications to whichever run loop is current when the client is created — on a DispatchQueue worker thread, there is no run loop, so notifications were delivered to... nowhere, or to the main thread, depending on CoreMIDI internals.

2. **`3bbf8d0` (June 15, 10am)**: still on a throwaway thread. notifications are being used but the `MIDIPortDisconnectSource` on a dead endpoint was found to corrupt the port. scan-on-notification added a 0.5s retry.

3. **`c8cf16e` (June 15, 3pm)**: moved retry scans off main thread. startup slowness investigated. still on throwaway thread.

4. **`f4a881d` (June 15, 10pm)**: **the persistent thread + poll were added in the same commit.** this is the key fact. the persistent thread with a live run loop (`RunLoop.current.run()`) was the actual fix for the notification delivery problem. the polling was added at the same time, apparently defensively.

### the critical question

**the comment claims notifications are unreliable "even with a persistent run loop" — but the persistent run loop and the polling were introduced together.** the notification reliability has never been tested in isolation with just the persistent thread and no poll.

the original problem (notifications not firing) had a clear mechanical cause: the throwaway DispatchQueue thread's run loop died immediately, so CoreMIDI had nowhere to deliver notifications. the persistent thread with `RunLoop.current.run()` directly fixes that cause.

it's plausible — possibly likely — that the polling is compensating for a bug that the persistent thread fix already resolved.

### additional observations

- `recreateClient()` itself re-registers the notification block. so each poll tick creates a fresh notification subscription. if notifications are actually working, this is redundant but harmless.
- the notification callback already double-scans (0.15s and 0.5s after the event) to handle enumeration timing. this pattern is correct and should survive plug cycles.
- `msgObjectAdded` specifically clears `suppressAutoScan` — showing the notification path is at least partially expected to work.

### test results (2026-06-24)

`startPolling()` was commented out and tested on device with 6-7 repeated plug/unplug cycles. every plug-in was detected reliably and quickly (~1s). the poll is not needed.

**conclusion:** the notification unreliability was caused by the throwaway DispatchQueue thread (pre-`f4a881d`), not an inherent CoreMIDI bug. the persistent run loop fix was sufficient. the poll was added defensively in the same commit without separate validation.

**action taken:** `startPolling()`, `pollTimer`, and the stale unreliability comment were removed entirely. a `UIApplication.willEnterForegroundNotification` observer was added instead — it calls `recreateClient()` once when the app foregrounds, catching any plug/unplug that happened while backgrounded.

---

## implementation priority

| improvement | depends on | effort |
|---|---|---|
| B: increase timer leeway | nothing | trivial — one line |
| A: pause master clock when backgrounded | nothing | small |
| test notifications without poll | above research | manual testing on device |
| D: scan on foreground + slow/remove poll | test results | small-medium |
| C: two-tier soft/hard poll | test results (if poll stays) | small |
