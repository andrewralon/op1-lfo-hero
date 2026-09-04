// canonical capture step list.
//
// index.html renders this as a click-through wizard; manual.html renders the same
// array as a numbered list for people using an off-the-shelf midi monitor. one
// source of truth, so the two paths cannot drift and one decoder handles both.
//
// fields:
//   id        stable identifier, written into the report — never rename one
//   prompt    what the contributor is asked to do, lowercase per project style
//   perTrack  expand into one step per mixer track
//   skippable can legitimately not exist on a device (drives DeviceCapabilities)
//   expects   what a good capture looks like: cc | switch | transport | tempo | any
//   why       shown as a hint; explains what the step is for
//   repeat    contributor may run this step as many times as they like

var CAPTURE_STEPS = [
  {
    id: 'volume',
    prompt: 'move the volume / level control for track {n} slowly from all the way down to all the way up, then back down',
    perTrack: true, skippable: true, expects: 'cc',
    why: 'the single most important mapping — this becomes the volume parameter'
  },
  {
    id: 'pan',
    prompt: 'sweep the pan control for track {n} fully left, fully right, then back to centre',
    perTrack: true, skippable: true, expects: 'cc',
    why: 'a device with no pan at all is a real answer — skip it and say so'
  },
  {
    id: 'mute',
    prompt: 'mute track {n}, wait a moment, then unmute it',
    perTrack: true, skippable: true, expects: 'switch',
    why: 'tells us the on value, the off value, and which way round they are'
  },
  {
    id: 'masterVolume',
    prompt: 'move the master / main output volume from minimum to maximum and back',
    perTrack: false, skippable: true, expects: 'cc',
    why: 'master often lives on its own midi channel, separate from the tracks'
  },
  {
    id: 'masterMute',
    prompt: 'mute the master output, then unmute it',
    perTrack: false, skippable: true, expects: 'switch'
  },
  {
    id: 'transportPlay',
    prompt: 'press play',
    perTrack: false, skippable: true, expects: 'transport'
  },
  {
    id: 'transportStop',
    prompt: 'press stop',
    perTrack: false, skippable: true, expects: 'transport'
  },
  {
    id: 'transportPrev',
    prompt: 'press rewind / previous / back',
    perTrack: false, skippable: true, expects: 'transport'
  },
  {
    id: 'transportNext',
    prompt: 'press fast-forward / next',
    perTrack: false, skippable: true, expects: 'transport'
  },
  {
    id: 'transportRecord',
    prompt: 'press record — but do NOT actually record over anything you care about',
    perTrack: false, skippable: true, expects: 'transport',
    why: 'we need to know which message means record so the app never sends it by accident'
  },
  {
    id: 'tempo',
    prompt: 'change the tempo / bpm on the device — nudge it up several steps, then back down',
    perTrack: false, skippable: true, expects: 'tempo',
    why: 'distinguishes an absolute tempo value from a relative encoder that only sends "up" or "down"'
  },
  {
    id: 'freeform',
    prompt: 'move any other control you would like the app to be able to automate, and type what it was',
    perTrack: false, skippable: true, expects: 'any', repeat: true,
    why: 'filters, eq, sends, fx — anything with a knob. do this as many times as you like'
  }
];

// expand the per-track steps for a given mixer size into one flat, numbered list.
// both pages render the result of this, so numbering always agrees.
function expandSteps(trackCount) {
  var out = [];
  CAPTURE_STEPS.forEach(function (s) {
    if (s.perTrack) {
      for (var t = 1; t <= trackCount; t++) {
        out.push(Object.assign({}, s, {
          key: s.id + '.' + t,
          track: t,
          prompt: s.prompt.replace('{n}', String(t))
        }));
      }
    } else {
      out.push(Object.assign({}, s, { key: s.id, track: 0 }));
    }
  });
  out.forEach(function (s, i) { s.number = i + 1; });
  return out;
}

if (typeof module !== 'undefined') { module.exports = { CAPTURE_STEPS: CAPTURE_STEPS, expandSteps: expandSteps }; }
