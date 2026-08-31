# Spike 04 — responsive behaviour across geometries

**2026-08-30.** Milestone 2. Debug build, run with `--debug`. Four defects
found; all fixed in the following session and the sweep re-run against the same
cases.

Milestone 2 asks that the spectrum and essential state "remain useful across
representative tiled, floating, narrow, wide, and fullscreen geometries". Three
sessions had left that unverified for the same reason each time: it cannot be
done on a desktop in use. The parent tiling layout undid each resize within a
second; focus-follows-mouse handed keystrokes to whatever was under the pointer;
and a screenshot caught whichever window was on top of a tab group.

The harness built here — `spike/nested-session.sh` and
`spike/geometry-sweep.sh` — and its hazards are described in *Verifying
responsive behaviour* in `project.md`. What follows is what the sweep measured.

## Cases

21 captures across framed and bare chrome, mixer open and closed, at widths from
160 to 1223 px and heights from 60 to 688 px, plus tiled and fullscreen. Two
long-lived playback streams with distinct media names supplied broadband
content, so bar density reads as the resolution of a visible shape rather than
the position of a few isolated spikes. Thresholds were then bracketed with
narrower sweeps at fixed height.

## What worked

Everything at 480 px and wider, in both chrome modes.

**Bar density follows width** across the whole range — 1200x120 renders a dense
wide spectrum, 240x600 a sparse narrow one, and neither is a stretched copy of
the other. This is the responsive behaviour the milestone was mainly asking
about, and it was already correct. **Bare mode is correct at every size tested**,
down to 160x60. Wide-short, tall-narrow, tiled and fullscreen all render
cleanly. The mixer takes only the height it needs. The frame closes correctly and
its line breaks around the title label wherever the legend fits.

## The four defects

All below 480 px, all in framed chrome, and all one cause: **every piece of
chrome was authored at one size.**

**1. Framed chrome had no minimum size and ate the signal before it yielded.**
At 160x60 the spectrum is not drawn at all — fixed insets, the title row and the
legend row consume the whole window, while bare mode at the same size draws it
correctly. That is `project.md`'s "an empty window is not an acceptable report of
anything", reached from a direction the requirement did not anticipate: the
window is empty not because a capability is missing but because the chrome took
the room.

**2. The legend was a fixed string.** Below the width the string needs it
overran the frame, was clipped mid-word, and consumed the bottom border on the
way. Measured at height 140, mixer closed, with
`[s]treams  [b]ypass  [f]rame  [-/+] density  [q]uit`:

| width | result |
|---|---|
| 360 | clipped after `[-/+] d`; no bottom border |
| 400 | clipped after `[q]`; no bottom border |
| 440 | `[q]uit` overruns the right border |
| 480 | fits, border closes after it |

So that legend needed roughly **460 px**. This is the same defect already
recorded as a maintenance problem — the keymap is a string literal in the legend
while the bindings live in `Main` — seen from the layout side, and publishing the
binding table as data both read fixes each.

**3. Mixer rows collided below ~320 px.** The row laid name, media name, meter
and percentage out at fixed proportions with no narrow behaviour. At height 200,
framed: 260 px drew the volume meter straight through the stream name; 300 px had
the meter touching the end of the name; 340 and 380 were clean. The media-name
column did degrade, eliding to `S…` around 480 and disappearing below ~340 — but
eliding a column to one character plus an ellipsis reserves space to say nothing.
At the other end the same proportions left the four columns stranded at roughly
2%, 33%, 64% and 87% at 1223 px.

**4. The state report had no narrow form.** Fine at 640x260, 480x200 and
320x180. At 200x100 `nothing is playing through 42Hz` overflowed both edges and
clipped to `thing is playing through 42`; at 160x60 title and detail both
overflowed and `no audio` collided with the frame's own `42Hz` label. The report
is the one thing that must survive a small window, since it is what distinguishes
silence from a dead pipeline.

## After the fixes

The floor a framed window reports — 179 × 108 px at the default text size — is
derived from font metrics rather than fixed, so it moves with
`omarchy display text size`.
