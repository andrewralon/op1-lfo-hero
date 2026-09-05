// device mapper. everything runs locally; nothing is ever sent anywhere.
// the capture step list lives in steps.js and is shared with manual.html.
(function () {
  'use strict';

  var SCREENS = ['s-intro', 's-unsupported', 's-identity', 's-setup', 's-wizard', 's-send', 's-done'];
  var VIRTUAL = ['iac driver', 'network session', 'bluetooth'];
  var RECORD_MS = 6000;
  var LISTEN_MS = 20000;
  // active sensing floods at ~300/s and would bloat the report to no purpose.
  // still counted in the tally, just not stored message-by-message.
  var RAW_IGNORE = [0xFE];

  var report = {
    schemaVersion: 1,
    toolVersion: '1.0.0',
    capturedAt: null,
    userAgent: navigator.userAgent,
    device: {
      userProvidedName: '', firmware: '', trackCount: 4,
      ports: { inputs: [], outputs: [] },
      selectedInput: null, selectedOutput: null,
      sysexPermitted: false,
      identityReply: null
    },
    passiveListen: null,
    captures: [],
    sendTests: { attempted: false, mirrorsIncomingCC: null, followsClock: null, transport: null, sent: [] },
    freeform: { anythingWeird: '', deviceSettingsChangedToMakeThisWork: '' }
  };

  var midi = null, sysexOK = false;
  var inputs = [], outputs = [], selIn = null, selOut = null;
  var sink = null, t0 = 0;
  var current = 's-intro';
  // set once there is something a refresh would cost. drives the unload warning.
  var dirty = false;
  // names of the ports a restored session was using, so the selects can be put back
  // by name — port ids are not stable across a reload.
  var restorePorts = null;

  // ── helpers ────────────────────────────────────────────────────────────────
  function $(id) { return document.getElementById(id); }
  function show(id) {
    current = id;
    SCREENS.forEach(function (s) { var e = $(s); if (e) e.hidden = (s !== id); });
    renderBack();
    save();
    window.scrollTo(0, 0);
  }
  function hex(b) {
    return Array.prototype.map.call(b, function (x) {
      return ('0' + x.toString(16)).slice(-2).toUpperCase();
    }).join(' ');
  }
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  function classify(b) {
    var s = b[0];
    if (s === 0xF8) return 'clock';
    if (s === 0xFA) return 'start';
    if (s === 0xFB) return 'continue';
    if (s === 0xFC) return 'stop';
    if (s === 0xFE) return 'active sensing';
    if (s === 0xF2) return 'song position';
    if (s === 0xF0) return 'sysex';
    var t = s & 0xF0, ch = (s & 0x0F) + 1;
    if (t === 0xB0) return 'cc ' + b[1] + ' (ch ' + ch + ')';
    if (t === 0xE0) return 'pitch bend (ch ' + ch + ')';
    if (t === 0x90) return 'note on (ch ' + ch + ')';
    if (t === 0x80) return 'note off (ch ' + ch + ')';
    return 'other 0x' + s.toString(16).toUpperCase();
  }

  function startSink(fn) { t0 = performance.now(); sink = fn; }
  function stopSink() { sink = null; }

  // ── back navigation ────────────────────────────────────────────────────────
  // one button, in the same place above every screen. inside the wizard it steps
  // back through the capture list rather than out of it, so a mis-skip or a fader
  // that did not actually move can be redone.
  function backTarget() {
    if (current === 's-identity') {
      return { hint: 'back to the start', go: function () { show('s-intro'); } };
    }
    if (current === 's-setup') {
      return { hint: 'back to what\'s connected', go: function () { show('s-identity'); } };
    }
    if (current === 's-wizard') {
      if (idx > 0) {
        return {
          hint: 'back to step ' + steps[idx - 1].number + ' of ' + steps.length,
          go: function () { idx--; renderStep(); }
        };
      }
      return { hint: 'back to your device details', go: function () { show('s-setup'); } };
    }
    if (current === 's-send') {
      if (!steps.length) return { hint: 'back to your device details', go: function () { show('s-setup'); } };
      return {
        hint: 'back to step ' + steps.length + ' of ' + steps.length,
        go: function () { idx = steps.length - 1; show('s-wizard'); renderStep(); }
      };
    }
    if (current === 's-done') {
      return { hint: 'back to the send tests', go: function () { show('s-send'); } };
    }
    return null;  // the intro has nowhere behind it, and unsupported is a dead end
  }

  function renderBack() {
    var t = backTarget();
    $('navBack').hidden = !t;
    $('backHint').textContent = t ? t.hint : '';
  }

  $('btnBack').addEventListener('click', function () {
    var t = backTarget();
    if (t) t.go();
  });

  // ── session persistence ────────────────────────────────────────────────────
  // the report is deliberately never uploaded, which used to mean a refresh or a
  // closed tab cost the whole ten-minute session. localStorage is same-origin and
  // never transmitted, so autosaving here keeps that promise intact.
  var SESSION_KEY = 'op1lfohero.mapper.session.v1';
  var saveDegraded = false;

  function storage() {
    // private-mode browsers throw on the property access itself, not on get/set
    try { return window.localStorage || null; } catch (e) { return null; }
  }

  function slim(r) {
    var copy = JSON.parse(JSON.stringify(r));
    copy.captures.forEach(function (c) { c.raw = []; c.rawDropped = true; });
    return copy;
  }

  function save() {
    if (!dirty) return;
    var s = storage();
    if (!s) return;
    var state = {
      savedAt: new Date().toISOString(),
      schemaVersion: report.schemaVersion,
      screen: current, idx: idx, wizardStarted: wizardStarted,
      report: report
    };
    try { s.setItem(SESSION_KEY, JSON.stringify(state)); return; } catch (e) { /* quota */ }
    // out of room. the raw byte log dwarfs everything else, so drop it from the saved
    // copy only — the in-memory report keeps every byte, and so does the download.
    try {
      state.report = slim(report);
      state.rawDropped = true;
      s.setItem(SESSION_KEY, JSON.stringify(state));
      if (!saveDegraded) {
        saveDegraded = true;
        $('saveNote').textContent = 'this browser ran out of storage, so the saved copy no longer '
          + 'holds the raw bytes — download the report before you close the tab.';
      }
    } catch (e2) {
      // a half-written session is worse than none: it would restore as truth
      try { s.removeItem(SESSION_KEY); } catch (e3) { /* nothing left to try */ }
    }
  }

  function loadSession() {
    var s = storage();
    if (!s) return null;
    var raw, st;
    try { raw = s.getItem(SESSION_KEY); } catch (e) { return null; }
    if (!raw) return null;
    try { st = JSON.parse(raw); } catch (e) { return null; }
    // a session written by a different report shape is not safely half-restorable
    if (!st || !st.report || st.schemaVersion !== report.schemaVersion) return null;
    if (SCREENS.indexOf(st.screen) === -1) return null;
    return st;
  }

  function clearSession() {
    var s = storage();
    if (!s) return;
    try { s.removeItem(SESSION_KEY); } catch (e) { /* nothing to do */ }
  }

  function restoreState(st) {
    var r = st.report;
    Object.keys(report).forEach(function (k) { if (k in r) report[k] = r[k]; });
    // port ids are not stable across a reload, so remember the names instead
    restorePorts = {
      input: r.device && r.device.selectedInput ? r.device.selectedInput.name : null,
      output: r.device && r.device.selectedOutput ? r.device.selectedOutput.name : null
    };
    $('devName').value = report.device.userProvidedName || '';
    $('devFirmware').value = report.device.firmware || '';
    $('devTracks').value = report.device.trackCount;
    $('qSetup').value = report.freeform.deviceSettingsChangedToMakeThisWork || '';
    $('qWeird').value = report.freeform.anythingWeird || '';
    if (report.passiveListen) $('btnToSetup').disabled = false;
    steps = expandSteps(report.device.trackCount);
    wizardStarted = !!st.wizardStarted;
    idx = Math.max(0, Math.min(steps.length - 1, st.idx || 0));
    dirty = true;
    $('resumeBanner').hidden = true;
  }

  function renderResumeBanner() {
    var st = loadSession();
    if (!st) return;
    var tracks = (st.report.device && st.report.device.trackCount) || 4;
    var total = expandSteps(tracks).length;
    var answered = (st.report.captures || []).filter(function (c) { return !c.skipped; }).length;
    var when = new Date(st.savedAt);
    var ago = isNaN(when.getTime()) ? '' : ' from ' + when.toLocaleString().toLowerCase();
    $('resumeSummary').textContent = answered + ' of ' + total + ' steps captured' + ago
      + '. resume where you left off, or start again from scratch.';
    $('resumeBanner').hidden = false;
  }

  $('btnResume').addEventListener('click', function () {
    var st = loadSession();
    if (!st) { $('resumeBanner').hidden = true; return; }
    restoreState(st);
    // web midi access does not survive a reload — it has to be asked for again
    connect(function (ok) {
      if (ok) {
        show(st.screen);
        if (st.screen === 's-wizard') renderStep();
        return;
      }
      // losing midi must not also lose the report: land on the screen that can
      // still download and copy it.
      show('s-done');
      $('downloadNote').textContent = 'could not reconnect to midi, but your saved report is '
        + 'intact — download or copy it below.';
    });
  });

  $('btnStartOver').addEventListener('click', function () {
    clearSession();
    dirty = false;   // don't warn about state we were just told to discard
    window.location.reload();
  });

  // a refresh no longer costs the session, but it still costs the midi connection
  // and the place in the list, so it is worth one confirm.
  window.addEventListener('beforeunload', function (e) {
    if (!dirty) return undefined;
    e.preventDefault();
    e.returnValue = '';   // chrome and safari still require this
    return '';
  });

  // ── connect ────────────────────────────────────────────────────────────────
  function unsupported(detail) {
    $('unsupportedDetail').textContent = detail || '';
    show('s-unsupported');
  }

  // `done` lets a resumed session reuse this path and then choose its own screen;
  // without it the caller gets the normal "on to the identity screen" behaviour.
  function connect(done) {
    if (!navigator.requestMIDIAccess) {
      unsupported('this browser does not provide navigator.requestMIDIAccess.');
      if (done) done(false);
      return;
    }
    navigator.requestMIDIAccess({ sysex: true })
      .then(function (a) { sysexOK = true; onAccess(a, done); })
      .catch(function () {
        // sysex refused or unavailable — still worth continuing without it
        navigator.requestMIDIAccess()
          .then(function (a) { sysexOK = false; onAccess(a, done); })
          .catch(function (e) {
            unsupported('midi access was refused: ' + (e && e.message ? e.message : e));
            if (done) done(false);
          });
      });
  }

  $('btnConnect').addEventListener('click', function () { connect(null); });

  function onAccess(access, done) {
    midi = access;
    report.device.sysexPermitted = sysexOK;
    access.onstatechange = refreshPorts;
    refreshPorts();
    $('sysexNote').textContent = sysexOK
      ? 'sysex permission granted — the identity check below will work.'
      : 'sysex permission was not granted, so the identity check is unavailable. everything else still works.';
    $('btnIdentify').disabled = !sysexOK;
    if (done) { done(true); return; }
    show('s-identity');
  }

  function portInfo(p) {
    return {
      id: p.id, name: p.name || '', manufacturer: p.manufacturer || '',
      version: p.version || '', state: p.state, connection: p.connection, type: p.type
    };
  }
  function looksVirtual(p) {
    var n = (p.name || '').toLowerCase();
    return VIRTUAL.some(function (v) { return n.indexOf(v) !== -1; });
  }

  function refreshPorts() {
    inputs = []; outputs = [];
    midi.inputs.forEach(function (p) { inputs.push(p); });
    midi.outputs.forEach(function (p) { outputs.push(p); });
    report.device.ports = { inputs: inputs.map(portInfo), outputs: outputs.map(portInfo) };
    renderPortTable();
    fillSelect($('inputSelect'), inputs, restorePorts && restorePorts.input);
    fillSelect($('outputSelect'), outputs, restorePorts && restorePorts.output);
    // one shot only — after this a replug must not override a manual choice
    restorePorts = null;
    bindInput();
    bindOutput();
  }

  function renderPortTable() {
    if (!inputs.length && !outputs.length) {
      $('portTable').innerHTML = '<div class="warn"><strong>no midi ports found at all.</strong> '
        + 'check the cable — plenty of usb-c cables are charge-only and carry no data. some devices '
        + 'also need midi switched on in their own settings.</div>';
      return;
    }
    var rows = '<table><tr><th>dir</th><th>name</th><th>manufacturer</th><th>version</th><th>state</th></tr>';
    report.device.ports.inputs.forEach(function (p) { rows += row('in', p); });
    report.device.ports.outputs.forEach(function (p) { rows += row('out', p); });
    rows += '</table>';
    $('portTable').innerHTML = rows;
    function row(d, p) {
      return '<tr><td>' + d + '</td><td>' + esc(p.name || '—') + '</td><td>' + esc(p.manufacturer || '—')
        + '</td><td>' + esc(p.version || '—') + '</td><td>' + esc(p.state) + '</td></tr>';
    }
  }

  function fillSelect(sel, ports, wantName) {
    var prev = sel.selectedIndex;
    sel.innerHTML = '';
    ports.forEach(function (p) {
      var o = document.createElement('option');
      o.textContent = (p.name || '(unnamed)') + (p.manufacturer ? '  —  ' + p.manufacturer : '');
      sel.appendChild(o);
    });
    if (wantName) {
      var byName = -1;
      ports.forEach(function (p, i) { if (byName === -1 && (p.name || '') === wantName) byName = i; });
      if (byName !== -1) { sel.selectedIndex = byName; return; }
    }
    if (prev >= 0 && prev < ports.length) { sel.selectedIndex = prev; return; }
    // default to the first port that isn't an obvious virtual/software port
    var guess = ports.findIndex(function (p) { return !looksVirtual(p); });
    sel.selectedIndex = guess >= 0 ? guess : 0;
  }

  function bindInput() {
    inputs.forEach(function (p) { p.onmidimessage = null; });
    selIn = inputs[$('inputSelect').selectedIndex] || null;
    report.device.selectedInput = selIn ? portInfo(selIn) : null;
    if (!selIn) return;
    selIn.onmidimessage = function (e) {
      if (!sink) return;
      var bytes = Array.prototype.slice.call(e.data);
      sink({ tMs: Math.round(performance.now() - t0), bytes: bytes });
    };
  }
  function bindOutput() {
    selOut = outputs[$('outputSelect').selectedIndex] || null;
    report.device.selectedOutput = selOut ? portInfo(selOut) : null;
  }
  $('inputSelect').addEventListener('change', bindInput);
  $('outputSelect').addEventListener('change', bindOutput);

  // ── identity ───────────────────────────────────────────────────────────────
  $('btnIdentify').addEventListener('click', function () {
    if (!selOut) { $('identityResult').innerHTML = '<div class="warn">no output port to ask.</div>'; return; }
    var got = [];
    startSink(function (m) { if (m.bytes[0] === 0xF0) got.push(m.bytes); });
    try {
      selOut.send([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]);
    } catch (e) {
      stopSink();
      $('identityResult').innerHTML = '<div class="warn">could not send: ' + esc(e.message || e) + '</div>';
      return;
    }
    $('identityResult').innerHTML = '<p class="meta">asked. waiting 2.5s for a reply…</p>';
    setTimeout(function () {
      stopSink();
      report.device.identityReply = got.map(hex);
      if (!got.length) {
        $('identityResult').innerHTML = '<div class="warn note">no reply. that is a normal, '
          + 'recordable answer — plenty of devices simply don\'t respond to this.</div>';
        return;
      }
      var h = '<div class="warn ok"><strong>it replied:</strong>';
      got.forEach(function (b) {
        h += '<br><code>' + hex(b) + '</code>';
        if (b[5] === 0x00 && b[6] === 0x20 && b[7] === 0x76) h += ' <em>— teenage engineering</em>';
      });
      $('identityResult').innerHTML = h + '</div>';
    }, 2500);
  });

  // ── passive listen ─────────────────────────────────────────────────────────
  $('btnListen').addEventListener('click', function () {
    var btn = $('btnListen');
    btn.disabled = true;
    var tally = {}, total = 0, ignored = 0;
    startSink(function (m) {
      total++;
      var k = classify(m.bytes);
      tally[k] = (tally[k] || 0) + 1;
      if (RAW_IGNORE.indexOf(m.bytes[0]) !== -1) ignored++;
    });
    var left = LISTEN_MS / 1000;
    $('listenStatus').textContent = 'listening… ' + left + 's — don\'t touch the device';
    var iv = setInterval(function () {
      left--;
      $('listenStatus').textContent = left > 0
        ? 'listening… ' + left + 's — don\'t touch the device'
        : 'done.';
      if (left <= 0) { clearInterval(iv); finish(); }
    }, 1000);

    function finish() {
      stopSink();
      btn.disabled = false;
      btn.textContent = 'listen again';
      report.passiveListen = {
        durationMs: LISTEN_MS,
        messageTally: tally,
        totalMessages: total,
        sawClock: !!tally['clock'],
        clockTicksPerSec: tally['clock'] ? +(tally['clock'] / (LISTEN_MS / 1000)).toFixed(2) : 0
      };
      var h;
      if (!total) {
        h = '<div class="warn note"><strong>silence.</strong> that is a perfectly good result — '
          + 'many devices say nothing until you touch them. (if every later step is also silent, '
          + 'check the device\'s own midi settings.)</div>';
      } else {
        h = '<div class="warn ok"><strong>heard ' + total + ' messages:</strong><table>'
          + '<tr><th>message</th><th>count</th></tr>';
        Object.keys(tally).sort(function (a, b) { return tally[b] - tally[a]; }).forEach(function (k) {
          h += '<tr><td>' + esc(k) + '</td><td>' + tally[k] + '</td></tr>';
        });
        h += '</table>';
        if (tally['clock']) {
          h += '<p style="margin:0"><strong>it sends midi clock on its own</strong> ('
            + report.passiveListen.clockTicksPerSec + ' ticks/sec ≈ '
            + Math.round(report.passiveListen.clockTicksPerSec / 24 * 60) + ' bpm). useful — that '
            + 'means the app could follow its tempo.</p>';
        }
        h += '</div>';
      }
      $('listenResult').innerHTML = h;
      $('btnToSetup').disabled = false;
      dirty = true;   // twenty seconds of listening is now worth not losing
      save();
    }
  });

  $('btnToSetup').addEventListener('click', function () { show('s-setup'); });

  // ── setup ──────────────────────────────────────────────────────────────────
  // also the way back *into* the wizard, so it resumes at the current step rather
  // than restarting from the top.
  function goToWizard() {
    var prevTracks = report.device.trackCount;
    report.device.userProvidedName = $('devName').value.trim();
    report.device.firmware = $('devFirmware').value.trim();
    var n = Math.max(1, Math.min(8, parseInt($('devTracks').value, 10) || 4));
    report.device.trackCount = n;
    if (n !== prevTracks) {
      // a track that no longer exists must not leave captures behind: a 4-track
      // report claiming a volume.5 would be read as a 5-track device.
      report.captures = report.captures.filter(function (c) { return !c.track || c.track <= n; });
    }
    steps = expandSteps(n);
    if (!wizardStarted) { idx = 0; wizardStarted = true; }
    if (idx > steps.length - 1) idx = steps.length - 1;
    dirty = true;
    show('s-wizard');
    renderStep();
  }
  $('btnToWizard').addEventListener('click', goToWizard);

  // ── wizard ─────────────────────────────────────────────────────────────────
  var steps = [], idx = 0, wizardStarted = false;

  // the last answer recorded for a step, or -1. back makes revisiting possible, so
  // every write has to find an existing entry instead of blindly appending.
  //
  // stepId alone is NOT enough: every track of a per-track step shares one id, so
  // matching on it would show track 1's answer on track 2 and then overwrite it.
  function captureIndexFor(s) {
    for (var i = report.captures.length - 1; i >= 0; i--) {
      var c = report.captures[i];
      if (c.stepId === s.id && (c.track || 0) === (s.track || 0)) return i;
    }
    return -1;
  }

  function storeCapture(cap) {
    var s = steps[idx];
    var i = captureIndexFor(s);
    if (s.repeat) {
      // a repeat step holds one entry per control the contributor recorded. a
      // "skipped" placeholder makes way for the first real one and is not re-added.
      var hasReal = report.captures.some(function (c) { return c.stepId === s.id && !c.skipped; });
      if (cap.skipped && hasReal) { dirty = true; save(); return; }
      if (!cap.skipped && i !== -1 && report.captures[i].skipped) report.captures.splice(i, 1);
      report.captures.push(cap);
    } else if (i !== -1) {
      report.captures[i] = cap;
    } else {
      report.captures.push(cap);
    }
    dirty = true;
    save();
  }

  function renderStep() {
    var s = steps[idx];
    $('wizProgress').textContent = 'step ' + s.number + ' of ' + steps.length;
    $('wizPrompt').textContent = s.prompt;
    $('wizWhy').textContent = s.why || '';
    $('wizLabelWrap').hidden = !s.repeat;
    $('wizLabel').value = '';
    $('recStatus').textContent = '';
    $('recLive').innerHTML = '';
    $('recResult').innerHTML = '';
    $('btnRecord').disabled = false;
    $('btnDoneRec').hidden = true;
    $('btnRedo').hidden = true;
    $('btnAgain').hidden = true;
    $('btnNext').hidden = true;
    $('btnSkipNo').hidden = false;
    $('btnSkipCant').hidden = false;

    // a step reached by going back shows the answer it already holds, so it can be
    // reviewed, recorded over, or simply moved past again.
    var i = captureIndexFor(s);
    if (i !== -1) {
      var c = report.captures[i];
      $('btnNext').hidden = false;
      if (c.skipped) {
        $('recResult').innerHTML = '<div class="warn note"><p style="margin:0">skipped — '
          + esc(c.skipReason) + '. record it now to replace that.</p></div>';
      } else {
        $('wizLabel').value = c.userLabel || '';
        $('recResult').innerHTML = describe(c.analysis);
        $('btnRedo').hidden = false;
        $('btnAgain').hidden = !s.repeat;
      }
    }

    renderBack();
    save();
  }

  function advance() {
    idx++;
    if (idx >= steps.length) { show('s-send'); return; }
    renderStep();
  }

  function recordSkip(reason) {
    var s = steps[idx];
    storeCapture({
      stepId: s.id, key: s.key, track: s.track, label: s.prompt,
      skipped: true, skipReason: reason, raw: [], analysis: null
    });
  }
  $('btnSkipNo').addEventListener('click', function () {
    recordSkip('no such control on this device'); advance();
  });
  $('btnSkipCant').addEventListener('click', function () {
    recordSkip('could not find it'); advance();
  });

  // set while a recording is running so the one "done recording" handler can end it.
  // binding inside doRecord would stack a fresh listener on every step.
  var stopEarly = null;
  $('btnDoneRec').addEventListener('click', function () { if (stopEarly) stopEarly(); });

  $('btnRecord').addEventListener('click', function () { doRecord(); });
  $('btnRedo').addEventListener('click', function () {
    // drop the answer this step currently holds and offer it again. matched on
    // stepId rather than key, because repeat steps get a numeric suffix on theirs.
    var i = captureIndexFor(steps[idx]);
    if (i !== -1) report.captures.splice(i, 1);
    renderStep();
  });
  $('btnAgain').addEventListener('click', function () { renderStep(); });
  $('btnNext').addEventListener('click', function () { advance(); });

  function doRecord() {
    var s = steps[idx];
    var raw = [], ignored = 0, seen = {}, done = false;
    $('btnRecord').disabled = true;
    $('btnDoneRec').hidden = false;
    $('btnSkipNo').hidden = true;
    $('btnSkipCant').hidden = true;
    // re-recording a step the contributor came back to: clear the old answer off the
    // screen, and take away the ways forward until this take has finished
    $('recResult').innerHTML = '';
    $('btnRedo').hidden = true;
    $('btnAgain').hidden = true;
    $('btnNext').hidden = true;
    startSink(function (m) {
      if (RAW_IGNORE.indexOf(m.bytes[0]) !== -1) { ignored++; return; }
      raw.push(m);
      var k = classify(m.bytes);
      seen[k] = (seen[k] || 0) + 1;
      renderLive(seen, raw.length);
    });
    var left = RECORD_MS / 1000;
    $('recStatus').textContent = 'recording… ' + left + 's — go (or press done recording)';
    var iv = setInterval(function () {
      left--;
      $('recStatus').textContent = left > 0 ? 'recording… ' + left + 's' : 'done.';
      if (left <= 0) { clearInterval(iv); finish(); }
    }, 1000);
    // once the control has been moved there is nothing to gain from the rest of the
    // countdown, and 24 steps of dead waiting is most of why this takes ten minutes.
    stopEarly = function () { clearInterval(iv); finish(); };

    function renderLive(t, n) {
      var keys = Object.keys(t).sort(function (a, b) { return t[b] - t[a]; }).slice(0, 6);
      $('recLive').innerHTML = '<p class="meta">' + n + ' messages: '
        + keys.map(function (k) { return esc(k) + ' ×' + t[k]; }).join(', ') + '</p>';
    }

    function finish() {
      if (done) return;   // the timer and the button both land here; only one may win
      done = true;
      stopEarly = null;
      $('btnDoneRec').hidden = true;
      $('recStatus').textContent = 'done.';
      stopSink();
      var analysis = analyze(raw);
      var key = s.key;
      if (s.repeat) {
        // count only real answers: a skip placeholder is about to be dropped, and
        // numbering off it would leave a gap.
        var n = report.captures.filter(function (c) {
          return c.stepId === s.id && !c.skipped;
        }).length + 1;
        key = s.key + '.' + n;
      }
      var cap = {
        stepId: s.id, key: key, track: s.track, label: s.prompt,
        skipped: false, skipReason: null,
        userLabel: s.repeat ? $('wizLabel').value.trim() : null,
        ignoredMessages: ignored,
        raw: raw, analysis: analysis
      };
      storeCapture(cap);
      $('recResult').innerHTML = describe(analysis);
      $('btnRedo').hidden = false;
      $('btnNext').hidden = false;
      $('btnAgain').hidden = !s.repeat;
      $('recLive').innerHTML = '';
    }
  }

  // ── analysis ───────────────────────────────────────────────────────────────
  function inferEncoding(values) {
    var set = {}, i;
    for (i = 0; i < values.length; i++) set[values[i]] = 1;
    var distinct = Object.keys(set).map(Number).sort(function (a, b) { return a - b; });
    var min = distinct[0], max = distinct[distinct.length - 1], range = max - min;

    if (distinct.length === 1) {
      return { kind: 'single-value', value: min, confidence: 'low',
        note: 'only ever sent ' + min + ' — likely a button, or the control did not actually move' };
    }

    var lowSide = distinct.filter(function (v) { return v > 0 && v <= 8; });
    var highSide = distinct.filter(function (v) { return v >= 120; });
    var midCount = distinct.filter(function (v) { return v > 8 && v < 120; }).length;
    var below64 = distinct.filter(function (v) { return v < 64; }).length;
    var above64 = distinct.filter(function (v) { return v > 64; }).length;

    // relative encoder, two's complement: values hug both ends and never include 0
    // (0 means "no change" and is simply not transmitted). this is checked BEFORE the
    // two-state case on purpose — an encoder nudged one step each way sends only two
    // values and would otherwise look exactly like a switch. getting that wrong is
    // expensive: an lfo on a relative encoder drifts in one direction forever instead
    // of oscillating, which is why the tx-6's cc 47 is excluded from the app entirely.
    if (midCount === 0 && lowSide.length && highSide.length && min !== 0) {
      var twoOnly = distinct.length === 2;
      return {
        kind: 'relative', center: 0,
        confidence: twoOnly ? 'medium' : 'high',
        ambiguous: twoOnly,
        note: "two's complement relative encoder — 1..63 up, 127..65 down. never safe as an "
          + 'lfo target: it would drift in one direction forever instead of oscillating.'
          + (twoOnly
            ? ' NOTE: only two values (' + min + ', ' + max + ') were seen, so this could also be '
              + 'an on/off switch. to tell them apart: keep turning the control in one direction. '
              + 'a relative encoder keeps sending, a switch stops at its two states.'
            : '')
      };
    }

    if (distinct.length === 2) {
      return { kind: 'switching', onValue: max, offValue: min, threshold: 64,
        confidence: min === 0 ? 'high' : 'medium',
        note: 'two states only: ' + min + ' and ' + max };
    }

    // relative encoder, offset-64 style: clusters on 64 and moves BOTH ways from it.
    // requiring both directions is what stops a barely-nudged fader from landing here.
    if (range <= 16 && below64 && above64
        && distinct.every(function (v) { return v >= 56 && v <= 72; })) {
      return { kind: 'relative', center: 64, confidence: 'medium',
        note: 'values cluster around 64 and move both ways from it, which is how an offset-64 '
          + 'relative encoder looks. same warning: not safe as an lfo target' };
    }

    // genuine discrete states are spread across the range (the tp-7's 3-state loop sits
    // at 0 / 64 / 127). a handful of adjacent values is a control that barely moved.
    if (distinct.length <= 8 && range >= 32) {
      return { kind: 'enumerated', count: distinct.length, values: distinct, confidence: 'medium',
        note: 'a small set of discrete states: ' + distinct.join(', ') };
    }

    if (distinct.length >= 15 && range >= 60) {
      return { kind: 'continuous', min: min, max: max, confidence: 'high',
        note: distinct.length + ' distinct values spanning ' + min + '-' + max };
    }

    return { kind: 'continuous', min: min, max: max, confidence: 'low',
      note: 'only ' + distinct.length + ' distinct values over a range of ' + range
        + ' — the control may not have moved through its whole travel. worth redoing' };
  }

  function analyze(raw) {
    var res = { status: 'nothing', groups: [], primary: null, realtime: {},
      pitchBend: null, notes: null, messageCount: raw.length };
    if (!raw.length) return res;

    var cc = {}, pb = [], nts = [];
    raw.forEach(function (m) {
      var b = m.bytes, s = b[0];
      if (s >= 0xF0) { var k = classify(b); res.realtime[k] = (res.realtime[k] || 0) + 1; return; }
      var t = s & 0xF0, ch = s & 0x0F;
      if (t === 0xB0) {
        var key = ch + ':' + b[1];
        if (!cc[key]) cc[key] = { channel: ch, cc: b[1], values: [] };
        cc[key].values.push(b[2]);
      } else if (t === 0xE0) { pb.push((b[2] << 7) | b[1]); }
      else if (t === 0x90 || t === 0x80) { nts.push(b[1]); }
    });

    Object.keys(cc).forEach(function (k) {
      var g = cc[k];
      res.groups.push({
        channel: g.channel, cc: g.cc, count: g.values.length,
        first: g.values[0], min: Math.min.apply(null, g.values), max: Math.max.apply(null, g.values),
        encoding: inferEncoding(g.values)
      });
    });
    res.groups.sort(function (a, b) { return b.count - a.count; });

    if (pb.length) res.pitchBend = { count: pb.length, min: Math.min.apply(null, pb), max: Math.max.apply(null, pb) };
    if (nts.length) {
      var u = {}; nts.forEach(function (n) { u[n] = 1; });
      res.notes = { count: nts.length, numbers: Object.keys(u).map(Number) };
    }

    if (res.groups.length) { res.primary = res.groups[0]; res.status = res.groups.length > 1 ? 'multiple' : 'ok'; }
    else if (res.pitchBend) res.status = 'pitchbend';
    else if (res.notes) res.status = 'notes';
    else if (Object.keys(res.realtime).length) res.status = 'realtime';
    return res;
  }

  function describe(a) {
    // a restored session can carry a capture this build no longer understands;
    // showing nothing beats taking the whole page down with it
    if (!a) return '';
    if (a.status === 'nothing') {
      return '<div class="warn"><strong>nothing came through.</strong> if the control definitely '
        + 'moved, the device may not transmit it — that is worth knowing, so use '
        + '<em>skip — no such control</em> only if the control genuinely does not exist. otherwise '
        + 'check you picked the right input port at the top.</div>';
    }
    var h = '<div class="warn ok"><strong>heard ' + a.messageCount + ' messages.</strong>';
    if (a.primary) {
      a.groups.forEach(function (g, i) {
        h += '<br>' + (i === 0 ? '→ ' : '&nbsp;&nbsp; also: ')
          + '<code>cc ' + g.cc + '</code> on channel ' + (g.channel + 1)
          + ' — ' + g.count + ' messages, ' + g.min + '-' + g.max
          + ' → <strong>' + esc(g.encoding.kind) + '</strong>'
          + ' <span class="meta">[' + g.encoding.confidence + ' confidence]</span>';
        if (g.encoding.ambiguous) h += ' <strong style="color:#ff6a00">— ambiguous, please read</strong>';
        if (g.encoding.note) h += '<br><span class="meta">&nbsp;&nbsp;&nbsp;' + esc(g.encoding.note) + '</span>';
      });
      if (a.groups.length > 1) {
        h += '<br><span class="meta">more than one control moved — if that was accidental, redo the step.</span>';
      }
    }
    if (a.pitchBend) h += '<br>→ <strong>pitch bend</strong>, ' + a.pitchBend.count + ' messages, ' + a.pitchBend.min + '-' + a.pitchBend.max;
    if (a.notes) h += '<br>→ <strong>notes</strong>: ' + a.notes.numbers.join(', ');
    var rt = Object.keys(a.realtime).filter(function (k) { return k !== 'clock' && k !== 'active sensing'; });
    if (rt.length) h += '<br>→ <strong>transport</strong>: ' + rt.map(function (k) { return esc(k) + ' ×' + a.realtime[k]; }).join(', ');
    if (a.realtime['clock']) h += '<br><span class="meta">(also streaming clock throughout — normal, ignored)</span>';
    return h + '</div>';
  }

  // ── send tests ─────────────────────────────────────────────────────────────
  $('sendConsent').addEventListener('change', function () {
    $('btnSendTests').disabled = !this.checked || !selOut;
  });
  $('btnSkipSend').addEventListener('click', function () { show('s-done'); });

  // controls the device itself transmitted, safe to replay back at it.
  function candidateCCs() {
    var byKey = {}, out = [];
    report.captures.forEach(function (c) {
      if (c.skipped || !c.analysis || !c.analysis.primary) return;
      var g = c.analysis.primary;
      // never touch record-arm; only touch cc 120 if this device's own mute used it
      if (g.cc === 14) return;
      if (g.cc === 120 && c.stepId !== 'mute' && c.stepId !== 'masterMute') return;
      var k = g.channel + ':' + g.cc;
      if (byKey[k]) return;
      byKey[k] = 1;
      out.push({ channel: g.channel, cc: g.cc, lo: g.min, hi: g.max, orig: g.first, from: c.key });
    });
    return out.slice(0, 12);
  }

  function sendBytes(b) {
    try { selOut.send(b); report.sendTests.sent.push(hex(b)); } catch (e) { /* port vanished */ }
  }

  async function streamClock(bpm, ms) {
    var period = 60000 / (bpm * 24);
    var until = performance.now() + ms;
    while (performance.now() < until) {
      sendBytes([0xF8]);
      await sleep(period);
    }
  }

  $('btnSendTests').addEventListener('click', async function () {
    var btn = this;
    btn.disabled = true;
    $('sendConsent').disabled = true;
    report.sendTests.attempted = true;
    var cands = candidateCCs();

    function st(t) { $('sendStatus').textContent = t; }

    st('replaying ' + cands.length + ' controls your device sent…');
    for (var i = 0; i < cands.length; i++) {
      var c = cands[i];
      st('replaying control ' + (i + 1) + ' of ' + cands.length + ' — cc ' + c.cc + ' on channel ' + (c.channel + 1));
      sendBytes([0xB0 | c.channel, c.cc, c.lo]); await sleep(250);
      sendBytes([0xB0 | c.channel, c.cc, c.hi]); await sleep(250);
      sendBytes([0xB0 | c.channel, c.cc, c.orig]); await sleep(150);  // put it back
    }

    st('sending midi clock at 100 bpm for 4s…');
    await streamClock(100, 4000);
    st('now 140 bpm for 4s — watch the device\'s tempo display…');
    await streamClock(140, 4000);

    st('sending play, waiting, then stop…');
    sendBytes([0xFB]);
    await sleep(2500);
    // exactly one stop. sending stop twice rewinds a tp-7 to zero.
    sendBytes([0xFC]);

    st('done. three questions:');
    save();
    renderSendQuestions(cands);
  });

  function renderSendQuestions(cands) {
    var qs = [
      { id: 'mirrorsIncomingCC', q: 'while the controls were being replayed, did anything on the device move or change?',
        hint: 'faders, knob values, screen readouts — anything at all' },
      { id: 'followsClock', q: 'did the device\'s tempo / bpm display change when the clock was sent?',
        hint: 'it would have gone to roughly 100, then roughly 140' },
      { id: 'transport', q: 'did the device start playing, then stop?',
        hint: 'tape, sequencer, whatever it has that runs' }
    ];
    var h = '';
    qs.forEach(function (q) {
      h += '<label><strong>' + esc(q.q) + '</strong><br><span class="meta">' + esc(q.hint) + '</span><br>'
        + '<select data-q="' + q.id + '">'
        + '<option value="">— pick one —</option>'
        + '<option value="yes">yes</option>'
        + '<option value="no">no, nothing happened</option>'
        + '<option value="unsure">i couldn\'t tell</option>'
        + '</select></label>';
    });
    h += '<p><button class="primary" id="btnSendDone">finish →</button></p>';
    $('sendQuestions').innerHTML = h;

    $('sendQuestions').addEventListener('change', function (e) {
      var k = e.target.getAttribute('data-q');
      if (k) { report.sendTests[k] = e.target.value || null; save(); }
    });
    $('btnSendDone').addEventListener('click', function () { show('s-done'); });
  }

  // ── report ─────────────────────────────────────────────────────────────────
  function finalise() {
    report.capturedAt = new Date().toISOString();
    report.freeform.deviceSettingsChangedToMakeThisWork = $('qSetup').value.trim();
    report.freeform.anythingWeird = $('qWeird').value.trim();
  }

  function summarise() {
    var d = report.device, lines = [];
    lines.push('device: ' + (d.userProvidedName || '(not given)') + (d.firmware ? '  fw ' + d.firmware : ''));
    lines.push('tracks: ' + d.trackCount);
    if (d.selectedInput) lines.push('port:   "' + d.selectedInput.name + '"  mfr "' + (d.selectedInput.manufacturer || '') + '"');
    lines.push('identity reply: ' + (d.identityReply && d.identityReply.length ? d.identityReply.join(' | ') : 'none'));
    if (report.passiveListen) {
      lines.push('idle listen: ' + report.passiveListen.totalMessages + ' messages, clock '
        + (report.passiveListen.sawClock ? 'yes (' + report.passiveListen.clockTicksPerSec + '/s)' : 'no'));
    }
    lines.push('');
    lines.push('captures:');
    report.captures.forEach(function (c) {
      var name = c.userLabel ? c.key + ' "' + c.userLabel + '"' : c.key;
      if (c.skipped) { lines.push('  ' + pad(name) + 'skipped — ' + c.skipReason); return; }
      var a = c.analysis;
      if (a && a.primary) {
        lines.push('  ' + pad(name) + 'cc ' + a.primary.cc + ' ch ' + (a.primary.channel + 1)
          + '  ' + a.primary.min + '-' + a.primary.max + '  ' + a.primary.encoding.kind
          + ' [' + a.primary.encoding.confidence + ']');
      } else if (a) {
        lines.push('  ' + pad(name) + a.status + ' (' + a.messageCount + ' messages)');
      }
    });
    if (report.sendTests.attempted) {
      lines.push('');
      lines.push('send tests: responds=' + report.sendTests.mirrorsIncomingCC
        + '  follows clock=' + report.sendTests.followsClock
        + '  transport=' + report.sendTests.transport);
    } else {
      lines.push('');
      lines.push('send tests: skipped');
    }
    if (report.freeform.deviceSettingsChangedToMakeThisWork) {
      lines.push('');
      lines.push('device settings changed: ' + report.freeform.deviceSettingsChangedToMakeThisWork);
    }
    return lines.join('\n');
    function pad(s) { return (s + '                        ').slice(0, 24); }
  }

  ['qSetup', 'qWeird'].forEach(function (id) {
    $(id).addEventListener('input', function () {
      finalise();
      $('summary').textContent = summarise();
      save();
    });
  });

  $('btnDownload').addEventListener('click', function () {
    finalise();
    var name = (report.device.userProvidedName || 'device').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    // .txt rather than .json: the content is identical, but forums and chat apps
    // routinely reject a .json upload while accepting .txt, and this file exists to
    // be attached to a message.
    var fn = 'device-report-' + (name || 'device') + '-' + report.capturedAt.slice(0, 10) + '.txt';
    var blob = new Blob([JSON.stringify(report, null, 2)], { type: 'text/plain' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url; a.download = fn;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    $('downloadNote').textContent = 'saved as ' + fn;
  });

  $('btnCopy').addEventListener('click', function () {
    finalise();
    var text = summarise();
    var note = $('downloadNote');
    function ok() { note.textContent = 'summary copied — paste it into the message'; }
    function fail() { note.textContent = 'could not copy — select the text below and copy it manually'; }
    // clipboard API needs a secure context; fall back for anything that refuses
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(ok, legacy);
    } else { legacy(); }
    function legacy() {
      try {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        var done = document.execCommand('copy');
        document.body.removeChild(ta);
        done ? ok() : fail();
      } catch (e) { fail(); }
    }
  });

  // keep the summary current whenever the last screen appears
  new MutationObserver(function () {
    if (!$('s-done').hidden) { finalise(); $('summary').textContent = summarise(); }
  }).observe($('s-done'), { attributes: true, attributeFilter: ['hidden'] });

  // an unfinished session from a previous visit is offered before anything else
  renderResumeBanner();
  renderBack();

  // expose for the browser-side self-test in tests/
  window.__mapper = { analyze: analyze, inferEncoding: inferEncoding, classify: classify,
    candidateCCs: candidateCCs, summarise: summarise, report: report,
    back: function () { var t = backTarget(); if (t) t.go(); },
    backHint: function () { var t = backTarget(); return t ? t.hint : null; },
    state: function () {
      return { screen: current, idx: idx, steps: steps.length, dirty: dirty };
    },
    show: show, goToWizard: goToWizard, advance: advance, renderStep: renderStep,
    recordSkip: recordSkip, storeCapture: storeCapture, captureIndexFor: captureIndexFor,
    saveSession: save, loadSession: loadSession, clearSession: clearSession,
    restoreState: restoreState, slim: slim,
    setDirty: function (v) { dirty = v; } };
})();
