# Spike 04 — responsive behaviour across geometries

**Date:** 2026-08-30
**Milestone:** 2 (responsive spectrum shell)
**Status:** verification complete; four defects found, none fixed here
**Binary:** `build-debug/42hz`, Debug, run with `--debug`

Milestone 2 asks that the spectrum and essential state "remain useful across
representative tiled, floating, narrow, wide, and fullscreen geometries". Three
sessions had left that unverified for the same reason each time: it cannot be
done on a desktop that is in use. This spike builds the environment that makes
it repeatable, then runs it.

## Method

### Why a nested compositor

Every previous attempt failed the same way. The parent tiling layout undid each
resize within a second; focus-follows-mouse handed keystrokes to whatever was
under the pointer between focusing 42Hz and typing at it; and a screenshot
caught whichever window happened to be on top of a tab group. None of those are
faults in 42Hz, and all of them are fatal to a geometry sweep.

`spike/nested-session.sh` starts a second Hyprland on its own Wayland socket,
with a generated config passed by `-c` — so the user's `~/.config/hypr` is
neither read nor written. Inside it there is one window, no layout policy but
ours, `follow_mouse = 0`, and `grim` capturing exactly the rectangle under test.

A headless session would have been tidier still — no window on the user's
screen at all. This Hyprland's aquamarine has no backend-selection environment
variable and `Hyprland --help` offers no `--headless`, so nesting inside the
running session is the only route.

### Geometry is set on the window, not the output

The obvious approach — size the nested *output* and let a single tiled window
fill it — does not work. The nested output is a surface in the parent session,
so the parent's layout decides how large it is; a `monitor` rule loses that
argument, and the granted size is not the same twice. Asked for 1280x720, the
nested output came back as 1226x688, then 1788x688, then 1223x688 across three
runs, purely from what else was on the parent's workspace.

A *floating* window inside the nested session has no such problem.
`dispatch resizewindowpixel exact W H` landed on the requested pixel every time
across 21 cases. So the sweep sets window geometry and treats the output only
as a ceiling, clamping to it and reporting the size actually granted rather
than the size requested.

`hyprctl dispatch` works. The 2026-08-30 (afternoon) diary entry records that
this Hyprland's dispatchers are a Lua API reachable only through `hyprctl eval`;
that is not true of `setfloating`, `settiled`, `resizewindowpixel`,
`centerwindow`, `focuswindow` or `fullscreenstate`, all of which were driven
here through plain `hyprctl dispatch` against a nested instance of the same
binary. What went wrong in the earlier session was not diagnosed and is not
explained by this.

### Cases

21 captures: framed and bare chrome, mixer open and closed, at window widths
from 160 to 1223 px and heights from 60 to 688 px, plus tiled and fullscreen
states. Two long-lived playback streams with distinct media names supplied
broadband content, so bar density is legible as the resolution of a visible
shape rather than the position of a few isolated spikes.

Thresholds were then bracketed with narrower sweeps at fixed height.

## Findings

### 1. Framed chrome has no minimum size, and eats the signal before it yields

At 160x60 framed, **the spectrum is not drawn at all.** The frame's fixed
insets, the title row and the legend row consume the entire window, leaving no
interior. Bare mode at the same 160x60 draws the spectrum correctly and fills
the window.

This is the failure `project.md` names — "an empty window is not an acceptable
report of anything" — arrived at from an unexpected direction. The window is
not empty because a capability is missing; it is empty because the chrome took
the room. Framed mode needs a floor below which it drops chrome and keeps
signal, rather than the other way round.

### 2. The legend is a fixed string and does not respond to width

`ShellFramed.qml` sets `legend` to one of two literals. Neither has a narrow
form, so below the width the string needs, it overruns the frame, is clipped
mid-word, and consumes the whole bottom border on the way — the frame stops
being closed.

Measured at height 140, mixer closed, legend
`[s]treams   [b]ypass   [f]rame   [-/+] density   [q]uit`:

| width | result |
|---|---|
| 360 | clipped after `[-/+] d`; no bottom border |
| 400 | clipped after `[q]`; no bottom border |
| 440 | `[q]uit` overruns the right border |
| 480 | fits, border closes after it |

So the closed-mixer legend needs roughly **460 px** of window width. The
mixer-open legend is shorter and fits at 480.

This is the same defect already recorded as a maintenance problem — the keymap
is a string literal in the legend while the bindings live in `Main` — seen from
the layout side. Publishing the binding table as data both read would let the
legend drop entries by priority as width falls, which is the fix for both.

### 3. Mixer rows collide below ~320 px

The row lays name, media name, meter and percentage out at fixed proportions of
the row width, with no narrow behaviour. Measured at height 200, framed:

| width | result |
|---|---|
| 260 | the volume meter is drawn straight through the stream name |
| 300 | meter touches the end of the name |
| 340 | clean |
| 380 | clean |

The media-name column does degrade — it elides to `S…` / `V…` around 480 and
disappears below roughly 340 — but eliding a column to a single character plus
an ellipsis reserves space to say nothing. It should drop out entirely at the
width where it stops carrying a word.

At the other end the same fixed proportions leave the row very sparse: at
1223 px the four columns sit at roughly 2%, 33%, 64% and 87% with dead space
between them.

### 4. The state report has no narrow form either

With nothing playing, `StateReport` draws title and detail centred. The detail
line has no width behaviour:

- at 640x260 and 480x200 and 320x180: fits.
- at 200x100: `nothing is playing through 42Hz` overflows both edges and is
  clipped to `thing is playing through 42`.
- at 160x60: title and detail both overflow, and `no audio` collides with the
  frame's own `42Hz` title label.

The report is the one thing that must survive a small window, since it is what
distinguishes silence from a dead pipeline. Below some width it should drop the
detail and keep the title.

### 5. What works

Everything at 480 px and wider is sound, in both chrome modes:

- **Bar density follows width** across the whole range — 1200x120 renders a
  dense wide spectrum, 240x600 a sparse narrow one, and neither is a stretched
  copy of the other. This is the responsive behaviour the milestone was mainly
  asking about, and it is correct.
- **Bare mode is correct at every size tested**, down to 160x60.
- **Wide-short, tall-narrow, tiled and fullscreen** all render cleanly.
- **The mixer takes only the height it needs**, two rows deep at 688 px tall
  rather than expanding to its half-surface allowance.
- The frame closes correctly, and its line breaks around the title label,
  wherever the legend fits.

## Incidental

- **A Hyprland config error reserves 26 px and is drawn into the output.** An
  invalid key in the generated config (`misc:vfr`, removed upstream) produced an
  error banner that `grim` captured over the top of every full-height shot, and
  a matching 26 px monitor `reserved` region that silently shrank every tiled
  window. Both vanished when the key was removed. `Hyprland --verify-config -c`
  is the check; the harness now generates a config that passes it.
- **`grim` captures the nested pointer**, which the nested compositor draws into
  its own output. `cursor:inactive_timeout = 1` removes it, since the harness
  drives the session with dispatchers and never moves the pointer.
- **`dispatch fullscreen 0` enters fullscreen; it does not leave it.** Using it
  to clear the state captured each window state under the *previous* case's
  label. `fullscreenstate <internal> <client>` names the state instead of
  toggling toward it.
