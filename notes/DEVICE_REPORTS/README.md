# Device reports

Raw captures submitted by people who own hardware we don't. One file per report:

- `<device>-<date>.json` — from the [guided probe](../../docs/probe/index.html)
- `<device>-<date>.log` — a raw monitor export from the [manual path](../../docs/probe/manual.html),
  kept alongside a hand-written `.json` in the same shape once decoded

**These are evidence, not conclusions.** Keep them verbatim, exactly as submitted — including runs
that turned out wrong or incomplete. A report that contradicts a later one is the useful kind of
data, and rewriting it destroys the only record of what the hardware actually did.

Conclusions drawn from these belong in [RESEARCH.md](../RESEARCH.md), with a line saying which
report they came from.

## Turning one into a profile

```bash
python3 scripts/report_to_profile.py notes/DEVICE_REPORTS/<file>.json
```

Prints a **draft** `DeviceProfile` literal. It exits non-zero when the device cannot be expressed
at all, and it deliberately does not generate transport ops — it lists what each button
*transmitted* and leaves what to *send* to you, because guessing there is the destructive kind of
wrong (the TP-7's play button once sent CC 14, which arms recording over a take).

## Reading one

`analysis.primary` on each capture is the probe's *guess*, not a fact. Check it against the raw
bytes before trusting it, and pay attention to two flags:

- `confidence: "low"` — usually means the contributor didn't move the control through its full
  travel. Worth asking them to redo that step.
- `ambiguous: true` — the probe genuinely can't tell two encodings apart from what it saw. The
  common case is a relative encoder nudged once each way, which looks identical to an on/off
  switch. Resolve it before writing a profile: guessing "switch" when it's a relative encoder
  produces an LFO target that drifts in one direction forever.

Also check `channel` and `cc` **independently** across a device's tracks. A device that gives each
track its own MIDI channel and one that gives each track its own CC number on a single shared
channel look similar at a glance but need completely different handling, and a report recording
only one of the two cannot be read back later. The probe captures both — keep it that way.
