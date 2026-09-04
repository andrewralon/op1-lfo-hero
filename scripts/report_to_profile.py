#!/usr/bin/env python3
"""Turn a device report from docs/mapper/ into a draft DeviceProfile Swift literal.

    python3 scripts/report_to_profile.py notes/DEVICE_REPORTS/op-1-2026-09-04.json

Emits a Swift `DeviceProfile` literal — the data-only device abstraction that arrives
with the multi-device work. This script is standalone and needs nothing from the app, so
reports can be gathered and converted before that lands.

It produces a *first draft*, not an answer. Every inference the mapper was unsure about is
carried through as an `UNVERIFIED` comment rather than silently resolved, because the
whole reason this pipeline exists is that guessing at MIDI maps has been wrong before —
checking the published TE references against real hardware turned up six that were not
true. Read every warning before using any of it.
"""

import json
import re
import sys
from collections import defaultdict

PER_TRACK_STEPS = {"volume": "volume", "pan": "pan", "mute": "mute"}
ROLE_FOR_STEP = {"volume": ".volume", "pan": ".pan", "mute": ".mute"}
TE_SWITCH = {"onValue": 127, "offValue": 0, "threshold": 64}

warnings = []
blockers = []


def warn(msg):
    warnings.append(msg)


def block(msg):
    blockers.append(msg)


# ── report access ──────────────────────────────────────────────────────────────
def captures_by_step(report):
    out = defaultdict(list)
    for c in report.get("captures", []):
        out[c.get("stepId")].append(c)
    return out


def usable(c):
    """A capture we can actually read a binding out of."""
    return (
        not c.get("skipped")
        and c.get("analysis")
        and c["analysis"].get("primary")
    )


def step_absent(caps):
    """True when the contributor said the control does not exist, rather than
    that they could not find it. Only the first sets a capability to false."""
    real = [c for c in caps if c.get("skipped")]
    if not real:
        return False
    return all("no such control" in (c.get("skipReason") or "") for c in real)


# ── encoding ───────────────────────────────────────────────────────────────────
def swift_encoding(enc, ident):
    """Return (swift_expression_or_None, lfo_targetable, notes[])."""
    notes = []
    kind = enc.get("kind")

    if enc.get("ambiguous"):
        notes.append(
            "UNVERIFIED: the mapper could not tell this apart from another encoding. "
            + (enc.get("note") or "")
        )
    if enc.get("confidence") == "low":
        notes.append(
            "UNVERIFIED: low confidence — " + (enc.get("note") or "control may not have moved fully")
        )

    if kind == "continuous":
        return None, True, notes  # .continuous is the default

    if kind == "switching":
        on, off, thr = enc.get("onValue"), enc.get("offValue"), enc.get("threshold", 64)
        if (on, off, thr) == (TE_SWITCH["onValue"], TE_SWITCH["offValue"], TE_SWITCH["threshold"]):
            return "teSwitch", True, notes
        return (
            f".switching(SwitchEncoding(onValue: {on}, offValue: {off}, threshold: {thr}))",
            True,
            notes,
        )

    if kind == "relative":
        notes.append(
            "relative encoder — NOT an LFO target: an LFO would drift in one direction "
            "forever instead of oscillating (this is why the TX-6's CC 47 is excluded)"
        )
        return f".relative(center: {enc.get('center', 64)})", False, notes

    if kind == "enumerated":
        notes.append("discrete states — check an LFO sweep is musically meaningful before enabling")
        return f".enumerated(count: {enc.get('count')})", False, notes

    if kind == "single-value":
        block(f"{ident}: only one value was ever sent ({enc.get('value')}). Cannot infer an encoding.")
        return None, True, notes + ["UNVERIFIED: only one value seen — probably a button"]

    block(f"{ident}: unrecognised encoding kind {kind!r}")
    return None, True, notes


# ── per-track addressing ───────────────────────────────────────────────────────
def track_addressing(caps, step_id):
    """Work out how the device addresses each track.

    DeviceProfile can only express "one fixed CC, channel varies per track"
    (ParamBinding.cc takes a fixed `cc` plus a ChannelRule). A device that varies
    the CC instead is currently inexpressible and must be reported, not smoothed over.
    """
    rows = [(c["track"], c["analysis"]["primary"]) for c in caps if usable(c) and c.get("track", 0) >= 1]
    if not rows:
        return None
    rows.sort()
    ccs = {p["cc"] for _, p in rows}
    chans = {p["channel"] for _, p in rows}

    if len(ccs) == 1 and len(chans) == len(rows) and len(rows) > 1:
        offsets = {p["channel"] - (t - 1) for t, p in rows}
        if len(offsets) == 1:
            return {"mode": "channel-per-track", "cc": rows[0][1]["cc"],
                    "offset": offsets.pop(), "primary": rows[0][1], "tracks": [t for t, _ in rows]}
        block(f"{step_id}: channel does not advance evenly with track "
              f"({', '.join(f'track {t}->ch {p['channel']}' for t, p in rows)}). "
              "ChannelRule.trackRelative cannot express this.")
        return None

    if len(chans) == 1 and len(ccs) > 1:
        block(
            f"{step_id}: this device varies the CC per track on a single channel "
            f"(channel {rows[0][1]['channel']}, CCs {sorted(ccs)}). "
            "ParamBinding.cc takes a FIXED cc plus a per-track ChannelRule, so this shape is "
            "NOT expressible today. Supporting it needs a CCRule enum mirroring ChannelRule."
        )
        return None

    if len(rows) == 1:
        return {"mode": "single", "cc": rows[0][1]["cc"], "offset": rows[0][1]["channel"],
                "primary": rows[0][1], "tracks": [rows[0][0]]}

    block(f"{step_id}: inconsistent addressing — CCs {sorted(ccs)}, channels {sorted(chans)}. "
          "Look at the raw bytes before trusting any of it.")
    return None


# ── emit ───────────────────────────────────────────────────────────────────────
def ident_for(prefix, step_id, user_label=None):
    if user_label:
        slug = re.sub(r"[^a-z0-9]+", " ", user_label.lower()).title().replace(" ", "")
        slug = slug[0].lower() + slug[1:] if slug else "param"
        return f"{prefix}.{slug}"
    return f"{prefix}.{step_id}"


def emit_params(report, prefix, by_step):
    lines, seen_ids = [], set()

    def add(ident, name, short, builder):
        if ident in seen_ids:
            warn(f"duplicate param id {ident} — ids must be globally unique across ALL profiles "
                 "(see DeviceDetectionTests.testParamIdsAreUniqueAcrossProfiles)")
        seen_ids.add(ident)
        lines.append(builder)

    for step_id in ("volume", "pan", "mute"):
        caps = by_step.get(step_id, [])
        if not caps:
            continue
        if step_absent(caps):
            continue
        addr = track_addressing(caps, step_id)
        if not addr:
            continue
        ident = ident_for(prefix, step_id)
        enc_expr, targetable, notes = swift_encoding(addr["primary"]["encoding"], ident)
        args = [f'"{ident}"', f'"{step_id}"', f'"{step_id[:3]}"', f'cc: {addr["cc"]}']
        args.append(f"role: {ROLE_FOR_STEP[step_id]}")
        if enc_expr:
            args.append(f"encoding: {enc_expr}")
        if addr["mode"] == "channel-per-track" and addr["offset"] != 0:
            warn(f"{ident}: channel offset is {addr['offset']}, not 0. perTrack() hardcodes "
                 "trackRelative(offset: 0) — write this ParamSpec out longhand.")
        if not targetable:
            warn(f"{ident}: perTrack() has no lfoTargetable argument — write this one longhand "
                 "with lfoTargetable: false.")
        for n in notes:
            lines.append(f"        // {n}")
        add(ident, step_id, step_id[:3], f"        perTrack({', '.join(args)}),")

    for step_id, label in (("masterVolume", "main vol"), ("masterMute", "main mute")):
        caps = [c for c in by_step.get(step_id, []) if usable(c)]
        if not caps:
            continue
        p = caps[0]["analysis"]["primary"]
        ident = ident_for(prefix, step_id)
        enc_expr, targetable, notes = swift_encoding(p["encoding"], ident)
        args = [f'"{ident}"', f'"{label}"', f'"{label[:3].strip()}"',
                f'cc: {p["cc"]}', f'channel: {p["channel"]}']
        if enc_expr:
            args.append(f"encoding: {enc_expr}")
        if not targetable:
            args.append("lfoTargetable: false")
        for n in notes:
            lines.append(f"        // {n}")
        add(ident, label, label[:3], f"        masterOnly({', '.join(args)}),")

    for c in by_step.get("freeform", []):
        if not usable(c):
            continue
        p = c["analysis"]["primary"]
        label = (c.get("userLabel") or "unnamed").lower()
        ident = ident_for(prefix, "freeform", c.get("userLabel"))
        enc_expr, targetable, notes = swift_encoding(p["encoding"], ident)
        notes.insert(0, f'contributor called this "{label}"')
        args = [f'"{ident}"', f'"{label}"', f'"{label[:3]}"',
                f'cc: {p["cc"]}', f'channel: {p["channel"]}']
        if enc_expr:
            args.append(f"encoding: {enc_expr}")
        if not targetable:
            args.append("lfoTargetable: false")
        for n in notes:
            lines.append(f"        // {n}")
        add(ident, label, label[:3], f"        masterOnly({', '.join(args)}),")

    return lines


def emit_transport(by_step):
    """Transport is reported, never auto-written — it is the part most likely to be
    destructive if guessed wrong (the TP-7's play once sent record-arm)."""
    out = []
    for step_id, arrow in (("transportPlay", "play"), ("transportStop", "stop"),
                           ("transportPrev", "prev"), ("transportNext", "next"),
                           ("transportRecord", "record")):
        caps = by_step.get(step_id, [])
        if not caps:
            out.append(f"            // {arrow}: not captured")
            continue
        c = caps[0]
        if c.get("skipped"):
            out.append(f"            // {arrow}: skipped — {c.get('skipReason')}")
            continue
        a = c.get("analysis") or {}
        bits = []
        for k, n in (a.get("realtime") or {}).items():
            if k not in ("clock", "active sensing"):
                bits.append(f"{k} x{n}")
        if a.get("primary"):
            p = a["primary"]
            bits.append(f"cc {p['cc']} ch {p['channel']} values {p['min']}-{p['max']}")
        out.append(f"            // {arrow}: {', '.join(bits) if bits else 'nothing observed'}")
    return out


def emit_caps(report, by_step):
    """Returns ([(swift_code, trailing_comment_or_None)], notes).

    Code and comment are kept apart so the caller can put the separating comma
    BEFORE the comment — appending it after produces a line the comment swallows,
    which does not compile.
    """
    st = report.get("sendTests") or {}
    pl = report.get("passiveListen") or {}
    lines, notes = [], []

    has_pan = not step_absent(by_step.get("pan", []))
    lines.append((f"            hasPan: {'true' if has_pan else 'false'}", None))

    lines.append((f"            canBeClockMaster: {'true' if pl.get('sawClock') else 'false'}", None))
    if not pl.get("sawClock"):
        notes.append("canBeClockMaster is false only because the device sent no clock while IDLE. "
                     "Some devices (the TP-7) transmit clock only while the transport is rolling — "
                     "verify before trusting this.")

    if st.get("followsClock") == "yes":
        lines.append(("            followsClock: true", None))
    elif st.get("followsClock") == "no":
        lines.append(("            followsClock: false", None))
    else:
        lines.append(("            followsClock: true",
                      "UNVERIFIED: send tests not run or unclear"))
        notes.append("followsClock was not established — the default true is a guess.")

    tempo_caps = by_step.get("tempo", [])
    has_tempo = bool(tempo_caps) and not step_absent(tempo_caps)
    tempo_usable = has_tempo
    for c in tempo_caps:
        if usable(c) and c["analysis"]["primary"]["encoding"].get("kind") == "relative":
            tempo_usable = False
            notes.append(
                "the tempo control is a RELATIVE encoder, so it cannot back a tempo parameter — "
                "an LFO on it would drift the tempo in one direction forever. hasTempoParam set "
                "false; reach it from the transport buttons via TransportOp.ccRelative instead "
                "(this is exactly what the TX-6 does with CC 47)."
            )
    lines.append((f"            hasTempoParam: {'true' if tempo_usable else 'false'}", None))

    if st.get("mirrorsIncomingCC") == "yes":
        lines.append(("            mirrorsIncomingCC: true", None))
    elif st.get("mirrorsIncomingCC") == "no":
        lines.append(("            mirrorsIncomingCC: false", None))
    else:
        lines.append(("            mirrorsIncomingCC: false", "UNVERIFIED: send tests not run"))
        notes.append("mirrorsIncomingCC defaulted to false, the safe choice — it only suppresses "
                     "mirroring inbound CC into the UI. Confirm before flipping it.")
    return lines, notes


def master_channel(by_step):
    """The channel the master bus actually answered on, from the master captures."""
    for step_id in ("masterVolume", "masterMute"):
        for c in by_step.get(step_id, []):
            if usable(c):
                return c["analysis"]["primary"]["channel"], True
    warn("masterChannel could not be derived — no master capture succeeded. Left at 0.")
    return 0, False


def name_tokens(report):
    port = (report.get("device") or {}).get("selectedInput") or {}
    raw = (port.get("name") or "").lower()
    toks = set()
    if raw:
        toks.add(raw)
        stripped = re.sub(r"\s*(midi|device|port|bluetooth|ble|usb)\s*", " ", raw).strip()
        if stripped:
            toks.add(stripped)
            toks.add(stripped.replace("-", ""))
    given = ((report.get("device") or {}).get("userProvidedName") or "").lower()
    m = re.match(r"[a-z]+-?\d+", given)
    if m:
        toks.add(m.group(0))
        toks.add(m.group(0).replace("-", ""))
    toks = sorted(t for t in toks if len(t) >= 2)
    if not toks:
        block("no usable name tokens — the port had no name and no device name was given. "
              "Auto-detection cannot work without one.")
    return toks


# ── main ───────────────────────────────────────────────────────────────────────
def main(path):
    with open(path) as f:
        report = json.load(f)

    if report.get("schemaVersion") != 1:
        warn(f"report schemaVersion is {report.get('schemaVersion')}, this script knows version 1")

    dev = report.get("device") or {}
    by_step = captures_by_step(report)
    prefix = re.sub(r"[^a-z0-9]+", "", (dev.get("userProvidedName") or "dev").lower())[:8] or "dev"
    tracks = dev.get("trackCount", 4)

    if prefix in ("op1", "tx6", "tp7"):
        warn(f'profile id "{prefix}" already exists in DeviceProfiles.swift. Pick a different id '
             "and param prefix — param ids must be globally unique across all profiles.")

    params = emit_params(report, prefix, by_step)
    caps_lines, caps_notes = emit_caps(report, by_step)
    for n in caps_notes:
        warn(n)
    toks = name_tokens(report)
    setup = (report.get("freeform") or {}).get("deviceSettingsChangedToMakeThisWork", "").strip()
    weird = (report.get("freeform") or {}).get("anythingWeird", "").strip()

    default_param = None
    for line in params:
        m = re.search(r'perTrack\("([^"]+)"', line)
        if m:
            default_param = m.group(1)
            break

    print("// " + "=" * 76)
    print(f"// DRAFT profile from {path}")
    print(f"// device: {dev.get('userProvidedName') or '(unnamed)'}"
          + (f"  firmware {dev.get('firmware')}" if dev.get("firmware") else ""))
    print(f"// captured: {report.get('capturedAt')}")
    print("//")
    print("// THIS IS A DRAFT. Every UNVERIFIED comment below is a real open question, not")
    print("// boilerplate. Resolve them against the raw bytes in the report before shipping.")
    print("// " + "=" * 76)
    print()

    if blockers:
        print("/* BLOCKERS — this profile cannot be completed as-is:")
        for b in blockers:
            print(f" *   - {b}")
        print(" */")
        print()
    if warnings:
        print("/* REVIEW:")
        for w in warnings:
            print(f" *   - {w}")
        print(" */")
        print()

    if weird:
        print(f"// contributor noted: {weird}")
        print()

    print("extension DeviceProfile {")
    print()
    print(f"    static let {prefix} = DeviceProfile(")
    print(f'        id: "{prefix}",')
    print(f'        displayName: "{(dev.get("userProvidedName") or prefix).lower()}",')
    print(f'        nameTokens: [{", ".join(chr(34) + t + chr(34) for t in toks)}],')
    print(f"        trackCount: {tracks},")
    mc, mc_known = master_channel(by_step)
    print(f"        masterChannel: {mc},"
          + ("" if mc_known else "  // UNVERIFIED: no master capture — this is a placeholder"))
    print(f"        params: {prefix}Params,")
    print(f'        defaultParamId: "{default_param or (prefix + ".volume")}",')
    print("        defaultVolume: 90,")
    print("        transport: TransportMap(")
    print("            // Transport is NOT auto-generated. What the device transmitted when each")
    print("            // button was pressed is listed below; the ops it should RECEIVE are a")
    print("            // separate question, and guessing wrong here is destructive — the TP-7's")
    print("            // play once sent CC 14, which is record arm.")
    for line in emit_transport(by_step):
        print(line)
    print("            play: [.midiStartOrContinue],")
    print("            stop: [.midiStop],")
    print("            prev: [],  // UNVERIFIED")
    print("            next: []   // UNVERIFIED")
    print("        ),")
    print("        caps: DeviceCapabilities(")
    for i, (code, comment) in enumerate(caps_lines):
        comma = "," if i < len(caps_lines) - 1 else ""
        print(code + comma + (f"  // {comment}" if comment else ""))
    print("        ),")
    if setup:
        print("        setupSteps: [")
        print(f'            "{setup.replace(chr(34), chr(39))}",')
        print("        ]")
    else:
        print("        setupSteps: []")
    print("    )")
    print()
    print(f"    private static let {prefix}Params: [ParamSpec] = [")
    for line in params:
        print(line)
    print("    ]")
    print("}")

    if blockers:
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
