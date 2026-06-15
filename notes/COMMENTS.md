# Comments

## To fix
- HIGH - reorder text for active lfo's to be same order as UI - `t1*volume*sine` (not `sine*volume*t1`)
- HIGH - show the scrub UI boxes differently so it's obvious they are scrubbable (vs dropdown, for example) - 2 thin vertical lines next to box? Different color border (white vs gray)? BEST: Single thin vertical white line just to the right of the box
  * fun idea - BPM box could use a way to show the user it can be scrubbed. maybe like it's a big rotating wheel or an old analog clock. maybe clip the top and bottom of the next entries so they're cut off at the edges of the box?
- MED - pan knob is weird (scrubs up and down, not turning or left-to-right). Not sure how to fix it cause there's no room to scrub horizontally on the screen.
  * tap pan -> open modal with horizontal slider and grip fader thingy? Hmmm.... TWO TAPS: 1 opens modal, 2 slides fader. let go makes it close automatically.
  * no other obvious solution
- MED - pause or stop LFO chaos - maybe stop button should stop lfo activity while setting up new LFOs cause it's distracting. Play should start it. Or a better way?
- MED - disable PLAY button if/when it can't be used
- MED - volume fader shape (angled square) is weird. make it a flatter rhombus / baseball diamond, like in python
- MED - icons....
  * metronome is too tall compared to row elements. remove text and center vertically?
  * umbrella??? -> replace with thunderbolt / lightning
  * rate looks good. maybe call it "speed" internally to match the op1.
  * depth / amplitude / peak-to-peak & center - no visual feedback for what they do since the waveform doesn't change.... not clear without trying it.
- MED - rate/speed needs all of the OP-1 options - 25 options (in order): 8 to 1 (relative tempo time) + 17 for clock symbols 0 to 30 minutes (absolute time)
- LOW - volume value is hidden by thumb. Move higher? fine with scrubbing.... 
