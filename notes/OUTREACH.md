# Asking people to run the device mapper

Copy-paste templates for recruiting device reports. Primary venue is **op-forums.com** — people
there own the gear, and they can DM the file straight back.

**Links to hand out:**

| | |
|---|---|
| Guided mapper | `https://andrewralon.github.io/op1-lfo-hero/mapper/` |
| Manual method (Safari / any monitor) | `https://andrewralon.github.io/op1-lfo-hero/mapper/manual.html` |

> ⚠️ **Both 404 until this work is on the live site.** Merge before you post, or the first person
> who clicks bounces and won't come back.

---

## Who to ask, in order

1. **OP-1 (original)** — the one people ask about most and the one you can't test.
2. **OP-Z** — large user base, very likely the next request.
3. **EP-133 K.O. II / EP-1320** — current gear, lots of owners.
4. **OB-4, PO series** — long shots, but a report costs them ten minutes.
5. **TX-6 / TP-7 owners** — worth accepting too. An independent report on hardware you've already
   measured is the only way you'd catch a bug in the mapper itself.

---

## 1. The op-forums post

Post it in whichever board fits — an OP-1 board if the ask is OG-specific, otherwise a general or
tools board. Read the board rules first; this is a request for help rather than a product
announcement, which lands fine most places, but posting it repeatedly does not.

**Title options:**
- `OP-1 (OG) owners: 10 minutes to get it supported in a free MIDI LFO app`
- `Need help mapping OP-1 OG MIDI — browser tool, no setup, ~10 min`

**Body:**

> i built **op1 lfo hero**, a free app that sends custom midi lfos to te gear — volume, pan, filter,
> fx, tape transport, clock sync. it currently supports the **op-1 field**, with **tx-6** and
> **tp-7** support in testing.
>
> i want to add the **op-1 (original)**, but i don't own one, and i've learned the hard way that i
> can't just read the published midi reference and write it down. when i checked those docs against
> real hardware, six things were wrong — one of them would have made the tp-7's play button arm a
> recording over your take.
>
> so instead: **a browser page that measures your device for you.**
>
> https://andrewralon.github.io/op1-lfo-hero/mapper/
>
> plug the op-1 in over usb, open that in chrome or edge, and it walks you through one prompt at a
> time — "move track 1's volume", "press play", that sort of thing. it records what your device
> sends and hands you a file at the end. **about 10 minutes, and you don't need to know anything
> about midi.** dm it to me when you're done.
>
> - **nothing is uploaded.** it all runs in your browser; the only thing that leaves is the file you
>   download.
> - **it only listens.** there's an optional section at the end that sends midi *to* your device,
>   behind a checkbox with a warning. it never touches record-arm. skip it and the report is still
>   useful.
> - **safari won't work** — apple has never shipped web midi. chrome, edge or firefox on a computer
>   will. if you'd rather use a midi monitor you already trust, there's a manual version:
>   https://andrewralon.github.io/op1-lfo-hero/mapper/manual.html
>
> most useful right now: **op-1 og**, op-z, ep-133. but any te device is welcome — including a
> tx-6 or tp-7, since an independent report is the only way i'd catch a bug in the tool itself.
>
> happy to answer anything here.

**Keep the thread alive.** On a forum the thread becomes the canonical place people find this, so
edit the first post as things land: which devices you've had reports for, which are still open,
and what shipped as a result. A thread showing "op-1 og support added, thanks to @someone" recruits
the next three people better than any wording change.

---

## 2. Short version (Discord, a reply, a DM)

> anyone here have an **op-1 (original)**? i make a free midi lfo app for te gear (op-1 field, with
> tx-6 and tp-7 in testing) and i'd love to add the og, but i don't own one and can't test against it.
>
> there's a browser page that walks you through it — plug the op-1 in, click through prompts like
> "move track 1's volume", and it spits out a file you dm me. about 10 minutes, no midi knowledge
> needed, nothing gets uploaded anywhere. needs chrome or edge on a computer.
>
> https://andrewralon.github.io/op1-lfo-hero/mapper/

Swap the device name. Keep it this short — the page does the explaining.

---

## 3. When someone says yes

> amazing, thank you. link again:
> https://andrewralon.github.io/op1-lfo-hero/mapper/
>
> **chrome or edge on a computer** — safari can't do this, apple never implemented the browser midi
> api. plug the op-1 in over usb first, then open the page and hit "connect to midi". it'll ask
> permission twice (midi, then sysex) — both are needed.
>
> two things that decide whether the report is usable:
>
> 1. **move each control through its whole travel**, slowly. a fader nudged an inch tells me almost
>    nothing; one taken from bottom to top tells me exactly what i need.
> 2. **if your device doesn't have a control, hit "skip — no such control"** rather than
>    "can't find it". those mean completely different things to me — the first says the feature
>    doesn't exist, the second says ask you again.
>
> if anything is confusing or the page misbehaves, tell me — that's useful too. you're the first
> person to run this on that device.

---

## 4. Setting expectations honestly

Say this if someone seems to expect a guaranteed result. It costs nothing and avoids souring a
volunteer:

> worth saying up front: a report doesn't automatically mean support. some devices address their
> mixer in a way the app can't currently express, and if yours is one of those it's a bigger change
> than a config file. but i genuinely can't tell without the data — and if it *does* turn out to
> need that change, you'll have been the reason i knew.

---

## 5. After a report arrives

> got it, thank you — this is exactly what i needed.
>
> [one specific thing you learned, e.g. "turns out it puts every track on midi channel 1 and varies
> the cc, which is different from every device i've seen"]
>
> i'll let you know when there's something to try. if you'd be up for testing a build later, say so
> and i'll ping you.

Naming the specific thing you learned is what makes someone willing to do it again, and willing to
tell the next person it was worth their time. A bare "thanks!" does not.

---

## Questions you'll actually get

**"Is this safe? Will it mess up my device?"**
> by default it only listens — it can't change anything. there's one optional section at the end
> that sends midi to your device to test whether it responds, and that's behind a checkbox with a
> warning. even then it only replays controls your device itself just sent, never touches
> record-arm, and puts every value back where it found it. skip it entirely and the report is still
> useful.

**"What data does it collect? Where does it go?"**
> nothing leaves your browser. it runs entirely locally — no server, no analytics, no account. at
> the end it gives you a summary to copy and a file to download, and you decide whether to send
> either. they hold the midi your device sent, the port name, and whatever you typed in the boxes.
> read the whole thing before sending; it's plain text.

**"Can't you just read the MIDI implementation chart?"**
> i tried that. when i checked the published references against real hardware, six things were
> wrong — including one that would have made the tp-7's play button arm a recording over your take.
> measuring is the only thing that's actually worked.

**"It says my browser isn't supported."**
> that'll be safari — apple has never implemented web midi, on mac or ios, so there's no version of
> that page that would work there. chrome, edge or firefox on a computer will. or use the manual
> method, which works with any midi monitor including on safari:
> https://andrewralon.github.io/op1-lfo-hero/mapper/manual.html

**"I plugged it in and nothing shows up."**
> three things, in order: try a different usb cable (loads of usb-c cables are charge-only and carry
> no data at all); check the device's own midi settings, since several te devices ship with midi
> output off or have in/out modes that disable each other; and if it's a recorder, it may only
> transmit while the tape is actually rolling. the tx-6 sends nothing until you set
> `midi control = in`, which cost me an afternoon.

**"Will you support my device if I do this?"**
> see section 4 — don't promise.

**"How long, really?"**
> about ten minutes for a 4-track device, fifteen with the optional send tests. you can stop partway
> and send what you've got; a partial report still beats nothing.
