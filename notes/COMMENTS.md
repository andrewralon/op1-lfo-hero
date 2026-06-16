# Comments

## To fix
- [ ] MED - start and stop lfos automatically, with start/stop buttons, in time with the op1 tempo
- [ ] MED - show the scrub UI boxes differently so it's obvious they are scrubbable (vs dropdown, for example) - 2 thin vertical lines next to box? Different color border (white vs gray)? BEST: Single thin vertical white line just to the right of the box
  * fun idea - BPM box could use a way to show the user it can be scrubbed. maybe like it's a big rotating wheel or an old analog clock. maybe clip the top and bottom of the next entries so they're cut off at the edges of the box?
- [ ] MED - pan knob is weird (scrubs up and down, not turning or left-to-right). Not sure how to fix it cause there's no room to scrub horizontally on the screen.
  * tap pan -> open modal with horizontal slider and grip fader thingy? Hmmm.... TWO TAPS: 1 opens modal, 2 slides fader. let go makes it close automatically.
  * no other obvious solution
- [ ] MED - pause or stop LFO chaos - maybe stop button should stop lfo activity while setting up new LFOs cause it's distracting. Play should start it. Or a better way?
- [ ] MED - rate/speed needs all of the OP-1 options - 25 options (in order): 8 to 1 (relative tempo time) + 17 for clock symbols 0 to 30 minutes (absolute time)
- [ ] LOW - depth & center spinboxes have no visual feedback for what they do since the waveform doesn't change.... not clear without trying it.
- [ ] LOW - add parameter: SUSTAIN - CC 64 >= 64 = down
- [ ] LOW - add OCTAVE shift capability - CC 79 < 64 = down, ≥ 64 = up
- [ ] LOW - volume value is hidden by thumb. Move higher? fine with scrubbing.... 
- [ ] LOW - icons: center could use some clarity

## Later (or not possible)
- [ ] LOW - fix left/right scrub mode if possible, like pressing them on the op1! tried and reverted, see commit history.

## Done
- [x] HIGH - reorder text for active lfo's to be same order as UI - `t1*volume*sine` (not `sine*volume*t1`)
- [x] HIGH - volume values don't match (app to op1) - off by 1 here and there
- [x] MED - disable all button animations / transition times. just flipping toggle the button fast! this doesn't seem to be working: ".animation(.none, value: state)"
- [x] MED - disable PLAY button if/when it can't be used
- [x] MED - icons: metronome is too tall compared to row elements. remove text and center vertically?
- [x] MED - icons: parameter umbrella??? -> replace with thunderbolt / lightning
- [x] MED - disable PLAY button if/when it can't be used
- [x] MED - volume fader grip shape (square at 45 degree angle) is weird and too tall. make it a flatter rhombus / baseball diamond, like what python had
