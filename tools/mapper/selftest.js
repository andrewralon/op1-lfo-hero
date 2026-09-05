// self-test for the device mapper's inference logic.
//
// feeds synthetic captures that mimic controls measured on real hardware and asserts
// the mapper re-derives the same conclusion.
// if the mapper cannot reproduce profiles we already know, it cannot be trusted on
// a device we don't own.
//
//   node tools/mapper/selftest.js

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '../..');

// ── minimal dom stub, enough for mapper.js's IIFE to run ─────────────────────
function stubEl() {
  const el = {
    hidden: false, disabled: false, value: '', textContent: '', innerHTML: '',
    selectedIndex: 0, checked: false, style: {},
    addEventListener() {}, appendChild() {}, removeChild() {},
    getAttribute() { return null; }, setAttribute() {}
  };
  return el;
}
const els = {};
// in-memory stand-in for localStorage, with a settable byte budget so the
// out-of-quota path can be exercised the way a real browser would trigger it
const store = {
  data: {}, limit: Infinity,
  getItem(k) { return Object.prototype.hasOwnProperty.call(this.data, k) ? this.data[k] : null; },
  setItem(k, v) {
    if (String(v).length > this.limit) {
      const e = new Error('quota'); e.name = 'QuotaExceededError'; throw e;
    }
    this.data[k] = String(v);
  },
  removeItem(k) { delete this.data[k]; }
};
const sandbox = {
  console,
  document: {
    getElementById(id) { return (els[id] = els[id] || stubEl()); },
    createElement: stubEl,
    body: { appendChild() {}, removeChild() {} }
  },
  navigator: { userAgent: 'selftest', requestMIDIAccess: undefined },
  performance: { now: () => Date.now() },
  window: {},
  addEventListener() {},
  scrollTo() {},
  location: { reload() {} },
  localStorage: store,
  setTimeout, clearTimeout, setInterval, clearInterval,
  MutationObserver: class { observe() {} },
  Blob: class {}, URL: { createObjectURL: () => '', revokeObjectURL() {} },
  Promise, Math, Date, Object, Array, String, Number, JSON
};
sandbox.window = sandbox;
vm.createContext(sandbox);

vm.runInContext(fs.readFileSync(path.join(ROOT, 'docs/mapper/steps.js'), 'utf8'), sandbox);
vm.runInContext(fs.readFileSync(path.join(ROOT, 'docs/mapper/mapper.js'), 'utf8'), sandbox);

const { analyze, classify } = sandbox.window.__mapper;
const { expandSteps, CAPTURE_STEPS } = sandbox;

// ── helpers to build synthetic captures ────────────────────────────────────
let t = 0;
const msg = (bytes) => ({ tMs: (t += 20), bytes });
const cc = (ch, num, vals) => vals.map((v) => msg([0xB0 | ch, num, v]));
const sweep = (from, to, stepBy = 3) => {
  const out = [];
  for (let v = from; v <= to; v += stepBy) out.push(v);
  for (let v = to; v >= from; v -= stepBy) out.push(v);
  return out;
};

let pass = 0, fail = 0;
function check(name, got, want) {
  const ok = got === want;
  if (ok) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; console.log(`  FAIL ${name}\n         got  ${got}\n         want ${want}`); }
}

// ── 1. controls we have actually measured ──────────────────────────────────
console.log('\nre-deriving facts measured on real hardware:');

// tx-6 / tp-7 track volume: cc 7, full sweep -> continuous
{
  const a = analyze(cc(0, 7, sweep(0, 127)));
  check('tx-6 vol -> cc 7', a.primary.cc, 7);
  check('tx-6 vol -> channel 1', a.primary.channel, 0);
  check('tx-6 vol -> continuous', a.primary.encoding.kind, 'continuous');
  check('tx-6 vol -> high confidence', a.primary.encoding.confidence, 'high');
}

// tx-6 pan: cc 8
{
  const a = analyze(cc(1, 8, sweep(0, 127)));
  check('tx-6 track2 pan -> cc 8 ch 2', `${a.primary.cc}/${a.primary.channel + 1}`, '8/2');
}

// tx-6 + tp-7 mute: cc 120, absolute 127 = muted -> two states
{
  const a = analyze(cc(0, 120, [0, 127, 0, 127]));
  check('mute -> cc 120', a.primary.cc, 120);
  check('mute -> switching', a.primary.encoding.kind, 'switching');
  check('mute -> on value 127', a.primary.encoding.onValue, 127);
  check('mute -> off value 0', a.primary.encoding.offValue, 0);
}

// op-1 mute: hard 127/0 on cc 9
{
  const a = analyze(cc(2, 9, [127, 0, 127]));
  check('op-1 mute -> cc 9 switching', `${a.primary.cc}/${a.primary.encoding.kind}`, '9/switching');
}

// tx-6 tempo cc 47: RELATIVE encoder. deliberately excluded from the app
// because an lfo on it would drift forever instead of oscillating.
{
  const a = analyze(cc(6, 47, [1, 1, 1, 127, 127, 1, 127]));
  check('tx-6 tempo -> relative (not continuous)', a.primary.encoding.kind, 'relative');
  check('tx-6 tempo -> two\'s complement centre 0', a.primary.encoding.center, 0);
  check('tx-6 tempo -> flagged ambiguous (only 2 values seen)', a.primary.encoding.ambiguous, true);
  check('tx-6 tempo -> note explains how to disambiguate',
    a.primary.encoding.note.includes('keep turning'), true);
}

// a relative encoder turned further: many values, still relative, now unambiguous
{
  const a = analyze(cc(6, 47, [1, 2, 3, 127, 126, 125, 1]));
  check('tempo turned further -> relative, high confidence', a.primary.encoding.confidence, 'high');
  check('tempo turned further -> not ambiguous', !!a.primary.encoding.ambiguous, false);
}

// a real two-state mute must NOT be swept up into the relative branch
{
  const a = analyze(cc(0, 120, [0, 127]));
  check('0/127 stays switching', a.primary.encoding.kind, 'switching');
}

// tp-7 loop cc 17: a 3-state machine, not a continuous value
{
  const a = analyze(cc(0, 17, [0, 64, 127, 0, 64]));
  check('tp-7 loop -> enumerated', a.primary.encoding.kind, 'enumerated');
  check('tp-7 loop -> 3 states', a.primary.encoding.count, 3);
}

// tp-7 speed: pitch bend, 14-bit
{
  const a = analyze([msg([0xE0, 0x00, 0x40]), msg([0xE0, 0x00, 0x60]), msg([0xE0, 0x64, 0x4B])]);
  check('tp-7 speed -> pitchbend', a.status, 'pitchbend');
  check('tp-7 speed -> 3 bend messages', a.pitchBend.count, 3);
}

// transport press -> realtime bytes, no cc at all
{
  const a = analyze([msg([0xFB]), msg([0xF8]), msg([0xF8]), msg([0xFC])]);
  check('transport -> realtime', a.status, 'realtime');
  check('transport -> saw continue', a.realtime['continue'], 1);
  check('transport -> saw stop', a.realtime['stop'], 1);
}

// ── 2. failure modes that must not silently look like success ──────────────
console.log('\nfailure modes:');

{
  const a = analyze([]);
  check('nothing captured -> status nothing', a.status, 'nothing');
  check('nothing captured -> no primary', a.primary, null);
}
{
  // a control barely nudged: must NOT claim high confidence
  const a = analyze(cc(0, 7, [64, 65, 66, 67]));
  check('barely-moved control -> low confidence', a.primary.encoding.confidence, 'low');
}
{
  // a button that only ever sends one value
  const a = analyze(cc(0, 64, [127, 127, 127]));
  check('single-value control flagged', a.primary.encoding.kind, 'single-value');
}
{
  // two controls moved at once -> must be flagged, not silently averaged
  const a = analyze([...cc(0, 7, sweep(0, 127)), ...cc(0, 10, sweep(0, 60))]);
  check('two controls moved -> status multiple', a.status, 'multiple');
  check('two controls -> both groups kept', a.groups.length, 2);
}
{
  // clock streaming during a capture must not drown out the real control
  const clock = Array.from({ length: 200 }, () => msg([0xF8]));
  const a = analyze([...clock, ...cc(0, 7, sweep(0, 127))]);
  check('clock noise -> cc still found', a.primary.cc, 7);
  check('clock noise -> clock counted separately', a.realtime['clock'], 200);
}

// ── 3. per-track cc vs per-track channel ───────────────────────────────────
// the app can currently only express "same cc, channel varies per track".
// a device doing the opposite must be visible in the data, not assumed away.
console.log('\nper-track addressing (the DeviceProfile gap):');
{
  const t1 = analyze(cc(0, 7, sweep(0, 127))).primary;
  const t2 = analyze(cc(1, 7, sweep(0, 127))).primary;
  check('channel-per-track shape detected', `cc${t1.cc}=cc${t2.cc} ch${t1.channel}!=ch${t2.channel}`,
    'cc7=cc7 ch0!=ch1');

  const u1 = analyze(cc(0, 20, sweep(0, 127))).primary;
  const u2 = analyze(cc(0, 21, sweep(0, 127))).primary;
  check('cc-per-track shape detected', `cc${u1.cc}!=cc${u2.cc} ch${u1.channel}=ch${u2.channel}`,
    'cc20!=cc21 ch0=ch0');
}

// ── 4. message classification ──────────────────────────────────────────────
console.log('\nmessage classification:');
check('clock', classify([0xF8]), 'clock');
check('start', classify([0xFA]), 'start');
check('continue', classify([0xFB]), 'continue');
check('stop', classify([0xFC]), 'stop');
check('cc names its channel 1-based', classify([0xB5, 7, 100]), 'cc 7 (ch 6)');
check('pitch bend', classify([0xE0, 0, 64]), 'pitch bend (ch 1)');
check('sysex', classify([0xF0, 0x7E]), 'sysex');

// ── 5. step list shared with manual.html ───────────────────────────────────
console.log('\nshared step list:');
{
  const s4 = expandSteps(4), s6 = expandSteps(6);
  check('4-track run has 21 steps', s4.length, 21);
  check('6-track run has 27 steps', s6.length, 27);
  check('steps numbered from 1', s4[0].number, 1);
  check('numbering is contiguous', s4.every((s, i) => s.number === i + 1), true);
  check('keys are unique', new Set(s4.map((s) => s.key)).size, s4.length);
  check('every step has a prompt', s4.every((s) => s.prompt && s.prompt.length >= 10), true);
  check('no unexpanded {n} placeholders', s4.some((s) => s.prompt.includes('{n}')), false);
  check('step ids are unique in source', new Set(CAPTURE_STEPS.map((s) => s.id)).size, CAPTURE_STEPS.length);
  // capability-bearing steps must be skippable, or we can never learn hasPan etc.
  ['pan', 'tempo', 'masterVolume'].forEach((id) => {
    check(`${id} is skippable`, CAPTURE_STEPS.find((s) => s.id === id).skippable, true);
  });
}

// ── 6. send-test safety filter ─────────────────────────────────────────────
// this decides what gets transmitted at a stranger's hardware. getting it wrong
// can arm a recording or silence unrelated gear on the same hub.
console.log('\nsend-test safety filter:');
{
  const { candidateCCs, report } = sandbox.window.__mapper;
  const cap = (stepId, ch, num, vals, extra = {}) => ({
    stepId, key: stepId, track: 1, label: '', skipped: false, skipReason: null,
    analysis: analyze(cc(ch, num, vals)), ...extra
  });

  report.captures.length = 0;
  report.captures.push(
    cap('volume', 0, 7, sweep(0, 127)),
    cap('transportRecord', 0, 14, [0, 127]),          // record arm — never replay
    cap('mute', 0, 120, [0, 127]),                    // all-sound-off, but it IS the mute
    cap('volume', 1, 120, [0, 127]),                  // cc 120 NOT from a mute step
    { stepId: 'pan', key: 'pan.1', skipped: true, skipReason: 'no pan', analysis: null },
    cap('volume', 0, 7, sweep(0, 127))                // duplicate ch:cc
  );
  const c = candidateCCs();
  const keys = c.map((x) => `${x.channel}:${x.cc}`);

  check('record-arm cc 14 excluded', keys.includes('0:14'), false);
  check('cc 120 kept when it is the mute', keys.includes('0:120'), true);
  check('cc 120 dropped when not a mute', keys.includes('1:120'), false);
  check('skipped captures excluded', c.length, 2);
  check('duplicate ch:cc deduped', keys.filter((k) => k === '0:7').length, 1);
  check('replay restores the original value', c[0].orig, 0);

  // hard cap so a freeform-heavy run cannot spray a device
  report.captures.length = 0;
  for (let i = 0; i < 30; i++) report.captures.push(cap('freeform', 0, 20 + i, sweep(0, 127)));
  check('candidate list capped at 12', candidateCCs().length, 12);
  report.captures.length = 0;
}

// ── 7. element ids referenced by mapper.js exist in index.html ───────────────
console.log('\nhtml/js wiring:');
{
  const html = fs.readFileSync(path.join(ROOT, 'docs/mapper/index.html'), 'utf8');
  const js = fs.readFileSync(path.join(ROOT, 'docs/mapper/mapper.js'), 'utf8');
  const defined = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]));
  // ids the script injects into the dom itself, so they are not in the static html
  const injected = new Set(['btnSendDone']);
  const used = new Set([...js.matchAll(/\$\('([^']+)'\)/g)].map((m) => m[1]));
  const missing = [...used].filter((id) => !defined.has(id) && !injected.has(id));
  check('no mapper.js id is missing from index.html', missing.join(',') || 'none', 'none');
  for (const id of injected) {
    check(`injected id ${id} is actually created`, js.includes(`id="${id}"`), true);
  }
}

// ── 8. report -> DeviceProfile converter ───────────────────────────────────
// builds reports through the real analyze(), runs scripts/report_to_profile.py on
// them, and checks the draft reproduces facts we already know from hardware.
console.log('\nreport -> profile converter:');
{
  const { execFileSync } = require('child_process');
  const os = require('os');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mapper-selftest-'));

  const cap = (stepId, key, track, raw, extra = {}) => ({
    stepId, key, track, label: stepId, skipped: false, skipReason: null,
    userLabel: null, ignoredMessages: 0, raw, analysis: analyze(raw), ...extra
  });
  const skip = (stepId, key, track, reason) => ({
    stepId, key, track, label: stepId, skipped: true, skipReason: reason, raw: [], analysis: null });

  const baseReport = (over) => ({
    schemaVersion: 1, toolVersion: '1.0.0', capturedAt: '2026-09-04T12:00:00.000Z',
    userAgent: 'selftest',
    device: { userProvidedName: 'dev', firmware: '', trackCount: 4,
      ports: { inputs: [], outputs: [] }, selectedInput: null, selectedOutput: null,
      sysexPermitted: false, identityReply: null },
    passiveListen: { durationMs: 20000, messageTally: {}, totalMessages: 0, sawClock: false, clockTicksPerSec: 0 },
    captures: [],
    sendTests: { attempted: false, mirrorsIncomingCC: null, followsClock: null, transport: null, sent: [] },
    freeform: { anythingWeird: '', deviceSettingsChangedToMakeThisWork: '' },
    ...over
  });

  function convert(report, name) {
    const f = path.join(tmp, name + '.json');
    fs.writeFileSync(f, JSON.stringify(report));
    try {
      const out = execFileSync('python3', [path.join(ROOT, 'scripts/report_to_profile.py'), f],
        { encoding: 'utf8' });
      return { code: 0, out };
    } catch (e) {
      return { code: e.status, out: (e.stdout || '') + (e.stderr || '') };
    }
  }

  // (a) a tx-6-shaped device: channel follows the track. we know the right answers.
  const tx6 = baseReport({
    device: { userProvidedName: 'zx-9', firmware: '1.0', trackCount: 6,
      ports: { inputs: [], outputs: [] },
      selectedInput: { name: 'ZX-9', manufacturer: 'Teenage Engineering' },
      selectedOutput: null, sysexPermitted: true, identityReply: [] },
    sendTests: { attempted: true, mirrorsIncomingCC: 'no', followsClock: 'yes', transport: 'yes', sent: [] },
    freeform: { anythingWeird: '', deviceSettingsChangedToMakeThisWork: 'set midi control = in' }
  });
  for (let tr = 1; tr <= 6; tr++) tx6.captures.push(cap('volume', `volume.${tr}`, tr, cc(tr - 1, 7, sweep(0, 127))));
  for (let tr = 1; tr <= 6; tr++) tx6.captures.push(cap('pan', `pan.${tr}`, tr, cc(tr - 1, 8, sweep(0, 127))));
  for (let tr = 1; tr <= 6; tr++) tx6.captures.push(cap('mute', `mute.${tr}`, tr, cc(tr - 1, 120, [0, 127, 0, 127])));
  tx6.captures.push(cap('masterVolume', 'masterVolume', 0, cc(6, 7, sweep(0, 127))));
  tx6.captures.push(cap('tempo', 'tempo', 0, cc(6, 47, [1, 1, 127, 127, 1])));

  const a = convert(tx6, 'tx6');
  check('clean report exits 0', a.code, 0);
  check('volume -> cc 7 with .volume role', a.out.includes('cc: 7, role: .volume'), true);
  check('pan -> cc 8 with .pan role', a.out.includes('cc: 8, role: .pan'), true);
  check('mute -> cc 120 as teSwitch', a.out.includes('cc: 120, role: .mute, encoding: teSwitch'), true);
  check('masterChannel derived from the master capture', a.out.includes('masterChannel: 6'), true);
  check('hasPan true when pan was captured', a.out.includes('hasPan: true'), true);
  check('relative tempo -> hasTempoParam false', a.out.includes('hasTempoParam: false'), true);
  check('send-test answer honoured', a.out.includes('mirrorsIncomingCC: false'), true);
  check('setup step carried through', a.out.includes('set midi control = in'), true);
  check('a comma never lands inside a comment',
    /:\s*(true|false)\s+\/\/[^\n]*,\s*$/m.test(a.out), false);

  // (b) per-track CC on one channel — inexpressible, must block rather than guess
  const single = baseReport({});
  for (let tr = 1; tr <= 4; tr++) single.captures.push(cap('volume', `volume.${tr}`, tr, cc(0, 19 + tr, sweep(0, 127))));
  for (let tr = 1; tr <= 4; tr++) single.captures.push(skip('pan', `pan.${tr}`, tr, 'no such control on this device'));

  const b = convert(single, 'single');
  check('inexpressible shape exits non-zero', b.code, 1);
  check('inexpressible shape is named as a blocker', b.out.includes('NOT expressible today'), true);
  check('blocker names the fix', b.out.includes('CCRule'), true);
  check('"no such control" sets hasPan false', b.out.includes('hasPan: false'), true);
  check('unestablished capability is marked UNVERIFIED', b.out.includes('UNVERIFIED: send tests not run'), true);

  // (c) both drafts must be valid swift
  let swiftc = true;
  try { execFileSync('swiftc', ['--version'], { stdio: 'ignore' }); } catch { swiftc = false; }
  if (swiftc) {
    for (const [name, res] of [['tx6', a], ['single', b]]) {
      const sf = path.join(tmp, name + '.swift');
      fs.writeFileSync(sf, res.out);
      let ok = true;
      try { execFileSync('swiftc', ['-parse', sf], { stdio: 'pipe' }); } catch { ok = false; }
      check(`generated ${name} draft is valid swift`, ok, true);
    }
  } else {
    console.log('  skip swiftc -parse (no swift toolchain)');
  }

  fs.rmSync(tmp, { recursive: true, force: true });
}

// ── 9. how the results leave the page ──────────────────────────────────────
// the file exists to be attached to a forum message, and the summary exists to
// be pasted into one. both routes have to keep working.
console.log('\nsending results back:');
{
  const js = fs.readFileSync(path.join(ROOT, 'docs/mapper/mapper.js'), 'utf8');
  const html = fs.readFileSync(path.join(ROOT, 'docs/mapper/index.html'), 'utf8');
  const manual = fs.readFileSync(path.join(ROOT, 'docs/mapper/manual.html'), 'utf8');

  // .json uploads are rejected by discourse and several chat apps; .txt is not
  check('download is named .txt, not .json', /\.txt';/.test(js), true);
  check('download blob is text/plain', js.includes("type: 'text/plain'"), true);
  check('no .json filename left behind', js.includes("+ '.json'"), false);

  // pasting needs no upload permission, which a new forum account may not have
  check('copy-summary button exists', html.includes('id="btnCopy"'), true);
  check('copy-summary handler is wired', js.includes("$('btnCopy').addEventListener"), true);
  check('clipboard has a non-secure-context fallback', js.includes('execCommand'), true);

  // both pages must name the same destination
  for (const [name, src] of [['guided mapper', html], ['manual page', manual]]) {
    check(`${name} names the op-forums route`, src.includes('op-forums.com/new-message?username=andrewralon'), true);
  }
}


// ── 10. going back, and surviving a refresh ────────────────────────────────
// back makes revisiting a step possible for the first time, so every write into
// report.captures has to be idempotent. and the session now autosaves, because
// the report is never uploaded and a stray refresh used to cost all ten minutes.
console.log('\nnavigation and persistence:');
{
  const m = sandbox.window.__mapper;
  const js = fs.readFileSync(path.join(ROOT, 'docs/mapper/mapper.js'), 'utf8');
  const html = fs.readFileSync(path.join(ROOT, 'docs/mapper/index.html'), 'utf8');
  // the stub cache fills lazily, and these inputs are only read inside handlers
  const el = (id) => sandbox.document.getElementById(id);

  // a 2-track device keeps the step list short enough to walk in a test
  el('devName').value = 'test device';
  el('devFirmware').value = '';
  el('devTracks').value = '2';
  m.goToWizard();
  const total = m.state().steps;
  check('setup leads into the wizard', m.state().screen, 's-wizard');
  check('wizard starts at the first step', m.state().idx, 0);

  // back out of step 1 and in again: the position is kept, not reset
  m.back();
  check('back from step 1 lands on setup', m.state().screen, 's-setup');
  m.goToWizard();
  m.advance(); m.advance();
  check('advanced to step 3', m.state().idx, 2);
  m.back();
  check('back steps within the wizard', m.state().idx, 1);
  m.back(); m.back();
  check('back past step 1 leaves the wizard', m.state().screen, 's-setup');
  m.goToWizard();
  check('re-entering the wizard resumes, not restarts', m.state().idx, 0);

  // re-answering a revisited step must replace its entry, never append a second
  m.recordSkip('no such control on this device');
  m.advance();
  m.back();
  const before = m.report.captures.length;
  m.recordSkip('could not find it');
  check('re-answering replaces, does not append', m.report.captures.length, before);
  check('the replacement is the one kept', m.report.captures[0].skipReason, 'could not find it');

  while (m.state().screen === 's-wizard') m.advance();
  check('walking every step reaches the send screen', m.state().screen, 's-send');
  m.back();
  check('back from send returns to the last step', m.state().idx, total - 1);

  // ...but the last step is `repeat`, and those are one entry per control: a skip
  // placeholder makes way for the first real answer, then answers accumulate.
  const repeatStep = expandSteps(2)[total - 1];
  check('the last step is the repeatable one', repeatStep.id, 'freeform');
  const beforeRepeat = m.report.captures.length;
  m.recordSkip('could not find it');
  check('a repeat step can be skipped', m.report.captures.length, beforeRepeat + 1);
  const answer = (key) => ({ stepId: 'freeform', key, skipped: false, raw: [], analysis: null });
  m.storeCapture(answer('freeform.1'));
  check('the first real answer replaces the placeholder', m.report.captures.length, beforeRepeat + 1);
  m.storeCapture(answer('freeform.2'));
  check('further answers accumulate', m.report.captures.length, beforeRepeat + 2);
  m.recordSkip('could not find it');
  check('a skip is dropped once real answers exist', m.report.captures.length, beforeRepeat + 2);

  // the send and done screens are reachable in both directions
  m.show('s-done');
  m.back();
  check('back from done returns to the send tests', m.state().screen, 's-send');

  // ── autosave ──
  m.setDirty(true);
  m.saveSession();
  const saved = m.loadSession();
  check('a session is written', !!saved, true);
  check('saved captures match the live ones', saved.report.captures.length, m.report.captures.length);
  check('the screen is remembered', saved.screen, 's-send');

  // a report written by a different shape must be ignored, not half-restored
  store.data['op1lfohero.mapper.session.v1'] =
    JSON.stringify({ schemaVersion: 99, screen: 's-done', report: { captures: [] } });
  check('a foreign schemaVersion is refused', m.loadSession(), null);

  // out of quota: the raw byte log goes, the derived analysis stays
  const slimmed = m.slim(m.report);
  check('slim drops the raw bytes', slimmed.captures.every((c) => c.raw.length === 0), true);
  check('slim marks what it dropped', slimmed.captures[0].rawDropped, true);
  store.data = {};
  store.limit = 200;   // small enough that even the slim copy will not fit
  m.saveSession();
  check('an unwritable session leaves nothing behind', store.getItem('op1lfohero.mapper.session.v1'), null);
  store.limit = Infinity;

  // restore has to rebuild the step list, not just the report
  m.clearSession();
  m.saveSession();
  const round = m.loadSession();
  m.restoreState(round);
  check('restore rebuilds the step list', m.state().steps, total);
  check('restore keeps the captures', m.report.captures.length, round.report.captures.length);

  // every track of a per-track step shares one stepId. matching an answer on that
  // alone would show track 1's capture on track 2 and then overwrite it, silently
  // losing a measurement that cost someone a fader sweep.
  // park on a known step and start from an empty report, wherever the block above left off
  m.show('s-wizard');
  while (m.state().idx > 0) m.back();
  m.report.captures.length = 0;

  const twoTrack = expandSteps(2);
  check('step 1 and step 2 are one control on two tracks',
    twoTrack[0].id + '/' + twoTrack[1].id, 'volume/volume');
  m.storeCapture({ stepId: 'volume', key: 'volume.1', track: 1, skipped: false, raw: [], analysis: null });
  m.advance();                       // now on volume.2: same stepId, different track
  check('track 2 has no answer of its own yet', m.captureIndexFor(twoTrack[1]), -1);
  m.storeCapture({ stepId: 'volume', key: 'volume.2', track: 2, skipped: false, raw: [], analysis: null });
  check('track 2 does not overwrite track 1', m.report.captures.length, 2);
  const t1 = m.report.captures.filter((c) => c.stepId === 'volume' && c.track === 1);
  check('track 1 keeps exactly one answer', t1.length, 1);
  check('and it is still track 1\'s', t1[0].key, 'volume.1');

  // a 6-second wait times 24 steps is most of why this takes ten minutes, so the
  // countdown can be cut short once the control has actually been moved
  check('an early-stop button exists', html.includes('id="btnDoneRec"'), true);
  check('it starts hidden', /id="btnDoneRec" hidden/.test(html), true);
  check('it is bound once, outside doRecord', js.includes("$('btnDoneRec').addEventListener"), true);
  check('recording only ever finishes once', js.includes('if (done) return;'), true);

  // the unload warning is the half that stops the mistake happening at all
  check('a beforeunload guard is registered', js.includes("'beforeunload'"), true);
  check('the guard is armed by a dirty flag', /if \(!dirty\) return undefined;/.test(js), true);

  // an unanswered step still records why it was passed over, and that wording must
  // not read as "no such control" — report_to_profile.py turns that into a false
  // capability, which is a claim about hardware nobody made.
  check('skip reasons stay distinguishable',
    js.includes("recordSkip('could not find it')"), true);
}

console.log(`\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
