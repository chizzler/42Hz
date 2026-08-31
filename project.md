# 42Hz

An ultra-minimal, Omarchy-native control surface for PipeWire audio, derived
from EasyEffects. It keeps EasyEffects' PipeWire integration, stream routing and
DSP hosting, and replaces its Kirigami frontend with a responsive,
spectrum-first Qt/QML one.

- **Public name:** 42Hz **Executable:** `42hz` **Application ID:** `io.github.chizzler.42Hz`
- **Upstream base:** EasyEffects `v8.2.8`, GPL-3.0-or-later
- **Status:** milestones 1, 3 and 4 complete; milestone 2 all but a whole-theme
  switch under load. Chronology is in [`docs/dev-diary.md`](docs/dev-diary.md).

This document records what is true about the design: the decisions, and the
constraints that were expensive to discover. It carries no dates and no
progress. What was tried, what it cost and what was rejected is in the diary.

## Goal and principles

42Hz gives access to the useful part of EasyEffects through a minimal window the
user places. It follows the economy of btop without copying it: density and
disclosed controls respond to available space, and placement, tiling, workspaces
and fullscreen stay the user's decision. At its smallest useful size it is a
live spectrum that confirms audio activity.

**Responsive, not prescribed.** No layout is privileged. The interface stays
legible across a broad range of window dimensions, reorganising or progressively
disclosing rather than switching among fixed modes.

**Spectrum first.** The live signal is the resting surface, not decoration
around a settings panel. No signal, unavailable audio and processing failure are
distinct states and all are reported.

The spectrum shows **absolute level**, not shape: a bar's height is the
magnitude the core reported, placed in a fixed dB window, so quiet audio draws a
quiet spectrum. Rescaling each frame to its own range is forbidden — it makes a
whisper and a peak pixel-identical.

The window is anchored at both ends. The core delivers dBFS clamped at -100, and
a 0 dBFS signal reads **-6 dB** there, because the core mixes to mono as
`0.5 * (L + R)` and compensates the Hann window's coherent gain with a factor of
two. So the ceiling is -6 dB and the floor is -90 dB, above the core's clamp so
the clamp lands at the bottom of the window rather than below it. The floor is
shared with the state report, so "silent" appears exactly when the spectrum
would otherwise draw nothing.

**Mixing is central.** Users identify active playback streams — games, voice
chat, browsers, music players — and adjust volume, mute, and whether each passes
through processing.

Processing is **one chain**, and inclusion is the per-stream control.
`DbStreamOutputs::plugins` is one list and every non-blocklisted stream passes
through the same effects in the same order. Per-stream chains would mean
per-stream pipelines and node graphs — the rewrite this project exists to avoid.
So the equalizer is an *output* equalizer and a stream's relationship to it is
binary. Per-stream presets are not a goal and must not be implied by the
interface.

**Reveal on intent.** Stream controls are reachable from the spectrum. Effect
editors appear when selected and use direct graphical controls with precise
values. Hiding an editor never interrupts its processing.

**Omarchy-native.** An ordinary, well-mannered Hyprland client that continuously
reflects the active theme. No shell plugin, no daemon, no prescribed window
rules, no edits to user or packaged Omarchy configuration.

**Backend stability over reinvention.** Reuse the derived core's PipeWire
integration, pipelines, stream models, DSP hosting, presets, state and spectrum
production. 42Hz is a focused frontend over a minimally changed core.

## Scope

First release: responsive spectrum in two appearances; application-stream mixer
with volume, mute and processing inclusion; pipeline and endpoint state; global
bypass; on-demand output equalizer; keyboard and pointer navigation at every
size; live Omarchy palette and typography; explicit capability feedback;
one-command Arch installation.

Not in it: reproducing every EasyEffects screen or effect; a new audio engine or
session manager; a shell plugin or daemon; prescribing window size or placement;
modifying Hyprland or Omarchy configuration; decoration that does not improve
signal reading, mixing, navigation or state awareness.

Preset management, input-effects editing, the full effect catalogue and advanced
routing may follow. The architecture must preserve a path to them without
exposing unfinished controls.

## Architecture

One process, three parts:

- **EasyEffects-derived core** — PipeWire session integration, stream discovery
  and routing, pipelines, DSP/LV2 hosting, state, presets, spectrum production.
- **42Hz frontend** — window lifecycle, spectrum rendering, mixer, effect
  editors, interaction, Omarchy theme adapter.
- **Internal facade** — models and commands for streams, endpoints, pipelines,
  spectrum frames, effects, EQ, bypass, capabilities and errors. UI code must
  not depend on upstream EasyEffects screens.

One process and one package until measured reliability or multiple independent
clients justify a backend service. The facade must make a later split possible
without designing an IPC protocol prematurely.

42Hz is a derived application, not a remote control: a release build contains the
core it was tested against, and EasyEffects need not be installed.

Evidence for the claims below is in `docs/spike-*.md`: coupling and the
dependency reduction (01), first execution and the Omarchy resolver gap (02),
identity reassignment and milestone-1 verification (03), responsive behaviour
across geometries (04), and the unimplemented reconnection design (05).

### What the upstream base gives you

- Upstream is already Qt6/QML. This is a frontend replacement within one
  toolkit, not a port.
- KDE/Kirigami coupling is confined to the entry point and the colour-scheme
  adapter. PipeWire, DSP, routing, preset and state layers carry no KDE UI
  dependency and need no modification.
- The spectrum reaches QML as a pull-based singleton delivering points already
  resampled to a configurable count. Responsive resampling is a settings
  binding, not new DSP.
- No upstream QML is reusable. 42Hz supplies its entire frontend.

### Three traps in the base

- **A Release build cannot be verified from its own logs.** Upstream includes
  KDE's `KDECompilerSettings`, which defines `QT_NO_DEBUG_OUTPUT` for Release, so
  `console.log` and QML's diagnostics are compiled out — and QML resolves
  undefined identifiers at runtime. A Release build fails silently by
  construction. An empty log means *muted*, never *clean*.
- **A Debug build is silent until asked.** The core calls
  `QLoggingCategory::setFilterRules("42hz.debug=false")` at the top of `main()`,
  after Qt has read `QT_LOGGING_RULES`, so only `--debug` turns the category back
  on. Where the output lands is not reliably where you redirected it: runs with
  stderr pointed at a file have written nothing there while `journalctl` carried
  the whole log. Check `journalctl` before concluding a build is mute, and launch
  from a terminal when the log matters.
- **A node name may not begin with a digit.** The core resolves `target.object`
  by attempting a numeric parse first, and its `str_to_num` helper accepts a
  partial `std::from_chars` result, so a leading-digit name is misread as a
  serial and the stream is dropped from the model while staying audible. Handled
  in the patch inventory for `target.object`; the shared helper is left lenient.
  More generally, a rename is not cosmetic when the new name has a different
  *shape* — leading digits, length, character class — from the old.

### Identity

Every identity surface the core inherited is reassigned: executable, config
directory and the KConfig paths that decide where settings land, presets
directory, single-instance lock and socket, logging category, virtual node names,
filter node prefix, node groups, media classes, desktop entry, metainfo, icons,
portal token. All of it derives from constants at the top of
`spike/reduce-deps.py`. 42Hz reads none of EasyEffects' settings and runs
alongside it, so development runs need no `XDG_CONFIG_HOME` fence.

The ID's final component begins with a digit. Desktop entries, AppStream and
Wayland `app_id` permit that; Flatpak IDs and D-Bus bus names do not. Neither
binds 42Hz, but a Flatpak would need a different ID.

## Window and layout

A conventional Wayland toplevel with a stable application ID, which is also the
class Hyprland window rules match. Hyprland owns placement; 42Hz supplies an
initial size and stays usable tiled, floated, resized, moved between monitors or
fullscreen.

Two chrome modes, both permanent and user-switchable:

- **Bare** — the spectrum alone, edge to edge. Nothing else is drawn.
- **Framed** — the spectrum inside a drawn border carrying pinned labels.

The frame is drawn geometrically, not typed, so it cannot be broken by
`omarchy font set`. Labels sit on the border line, which breaks around them.

The spectrum has exactly two appearances: **bars**, filled pixel columns, and
**cells**, a character grid of U+2581..U+2588 block elements. Cells follow
`omarchy font set`, being measured in whatever `monospace` resolves to. Both read
the same fixed dB window, so switching must never look like the signal changed.
Density applies to both; a cell grid rounds it to a whole number of cells per
column, and that coarseness is the honest answer rather than a control showing a
value it ignores.

### How the layout gives things up

- **Chrome yields before signal.** Labels, legends, restated values and
  decoration go, in that order. The spectrum, the state report and every reported
  state do not. A component that will not fit is dropped whole, never elided to a
  stub: a column reserving the width of a word to render `S…` costs the space and
  delivers none of the meaning.
- **A wider window never shows less.** Whatever is disclosed at one size is
  disclosed at every larger size. A rule that hands width back as the window
  narrows must not reintroduce something already dropped.
- **Each chrome mode declares its own floor**, and below it the window reports
  that it is too small, names the size it needs, and points at a mode that would
  fit. Framed pays for a title row, a legend row and border air; bare pays for
  none and stays useful far smaller. A single window-wide threshold would take a
  working bare window away to fix a framed problem.

Two ways a floor goes wrong:

- **`advanceWidth()` is a call, not a property.** A binding that only calls it
  captures no dependency and never re-runs, so the measurement freezes at
  whatever font was loaded at startup and stops following `omarchy display text
  size`. The binding must also read the `FontMetrics` object's own `font`
  property, which notifies — and reading that rather than the theme's keys is
  what keeps the measurement off a stale font, since both are bindings on the
  same signal and their order is undefined.
- **A floor must not depend on visibility.** QML propagates `visible` to
  children, so a minimum computed from live label geometry collapses the moment
  the shell is hidden for being too small, and the window oscillates between the
  two answers. The same trap catches any test that reads back the geometry of the
  thing it is deciding to hide.

### Pinned positions, framed mode

- **Top left:** identity and state.
- **Top right, on the line:** the spectrum's adjustments, drawn btop-style as a
  value with a minus left and a plus right. They sit in the border, which breaks
  around them as it does around the title, so they cost no signal height.
- **Bottom right:** actions and menus.
- **Centre:** capability and signal state, when there is something to report.

**An adjustment with a permanent on-screen value does not also announce itself**,
and one without a control does. Exactly one of the two says it at every width:
the controls are dropped when the top edge cannot hold them beside the title, and
the announcement returns at the same moment. Bare chrome draws no controls, so
there it always announces. Whether they fit is decided from font metrics, never
from the controls' own geometry — a width read off a hidden item is zero, so the
test that hid them would find room for them again and the window would latch.

**A key hint is drawn in the accent wherever it appears** — `[s]treams` carries
its `s`; a stepper carries the keys that actually move it, `-`/`+` for density
and `[`/`]` for style. Colour at rest, not on hover: a hint visible only under
the pointer reaches nobody who is not already using one.

**Announcements are drawn inside the border, never across it.** Anchored to the
window they land on the frame's linework, which reads as damage.

The legend ranks. The mixer and the equalizer are what the window is for; chrome
mode and spectrum appearance are tweaks and are given up first. An adjustment
that has become an on-screen control leaves the legend rather than restating
itself there.

### Keyboard

Every action is reachable by key at every window size. Only bindings backed by a
live capability are advertised.

**A missing capability is a different case from a window too narrow to mention
one.** Size decides what is *said*; the key still works. An absent capability
means there is nothing to act on, and the key answers by reporting why, in the
same place a mode change is reported, without touching the graph.

The equalizer is the standing example: the core creates its filter node whether
or not the LV2 provider is installed, so `[e]q` is advertised on
`packageInstalled` rather than on the instance existing. Pressed without it, the
key says the plugin is missing instead of opening an editor for something that
moves no samples.

Bindings are published as data that the key handler and the interface both read.
A binding carries its key, label, the priority at which it is given up when the
legend shortens, and whether a capability backs it. Advertising is gated on that
capability; the action never is.

| key | action |
|---|---|
| `s` | show or hide the mixer |
| `e` | show or hide the equalizer editor — advertised only while the LV2 provider is installed |
| `b` | bypass the equalizer — documented, not advertised; the editor draws it as a state |
| `f`, `1`, `2` | chrome mode — documented, not advertised |
| `-` / `+` | bar density — a control in framed chrome, not a legend entry |
| `[` / `]` | spectrum style — as above |
| `Escape` | dismiss transient controls; never stops audio |
| `q`, `Ctrl+W` | quit |

The mixer and the editor are mutually exclusive: both want the bottom of the
surface and both want the arrow keys. While the mixer is up it takes `↑`/`↓`
(select), `←`/`→` (volume), `m` (mute) and `p` (processing inclusion); while the
editor is up it takes `←`/`→` (band), `↑`/`↓` (gain) and `0` (flat). Everything
else still reaches the window, `b` included.

42Hz may ship optional example Hyprland rules, but installation never applies
them.

## Verifying responsive behaviour

Responsive claims are verified by capture, not inspection, and not on a desktop
in use: a tiling parent undoes every resize within a second, focus-follows-mouse
hands keystrokes to whatever is under the pointer, and a screenshot catches
whichever window is on top.

`spike/nested-session.sh` starts a second Hyprland on its own Wayland socket from
a generated config; `spike/geometry-sweep.sh` drives a capture sweep through it.
Neither reads nor writes user configuration. Theme fidelity uses
`spike/theme-preview.sh`, which renders 42Hz under any theme in
`/usr/share/omarchy/themes` by giving it a fake `HOME` containing only the two
files the adapter reads; no theme is switched and the running desktop never
changes.

**Run the sweeps at milestone boundaries and when a layout rule changes**, not
reflexively. A sweep costs minutes and produces twenty-one images that then have
to be read.

Geometry is set on the *window*, never on the nested output. The output is a
surface in the parent session, so the parent's layout decides its size and a
`monitor` rule does not; `dispatch resizewindowpixel exact` on a floating window
is reliable to the pixel. The output is a ceiling, geometries are clamped to it,
and a capture is labelled with the size granted rather than the size requested.

Clamping keeps a caption honest; it is not a way to sweep an output too small to
hold the cases. On a busy parent workspace the nested output is a tile a few
hundred pixels wide, every geometry collapses onto it, and the sweep passes with
twenty-one correctly labelled captures of the same window. The sweep refuses
below a size its cases are distinguishable at, and `nested-session.sh expand`
fullscreens the nested window on the parent to give it one — restating the
monitor rule at the size actually granted, since the rule written at startup
names the size that was asked for and a stale one holds the window at the old
geometry inside a bigger output.

Six things corrupt the evidence quietly:

- **A Hyprland config error is drawn into the output and reserves space in it.**
  One invalid key produces a banner across every capture and a monitor `reserved`
  region that shrinks every tiled window. `Hyprland --verify-config -c` is the
  check.
- **`grim` captures the nested pointer**, which the nested compositor draws into
  its own output. `cursor:inactive_timeout` removes it.
- **`dispatch fullscreen 0` enters fullscreen; it does not leave it.**
  `fullscreenstate` names a state rather than toggling toward one.
- **A static nested output starves screencopy.** With VFR on, a compositor
  showing unchanging content stops producing frames and `grim` waits forever, so
  a capture of a silent still window hangs while the same capture of a live
  spectrum returns at once. It reads as a wedged application.
  `debug:vfr = false` — no longer under `misc:`.
- **An idle-blanked parent starves it the same way from outside.** A nested
  compositor renders only while its own window receives frame callbacks, and a
  display the idle daemon switched off delivers none; captures then block,
  indistinguishably from the covered-window case. The parent's `dpmsStatus` tells
  them apart. The nested session must also stay on the parent's **active**
  workspace, since an unmapped one delivers no callbacks either.
- **A new instance draws timed warning banners into its own output** for about
  fifteen seconds. Wait them out.

Which form of `hyprctl dispatch` works is decided by how the *instance* was
configured, not by the Hyprland version. A Lua-configured Hyprland — a
`hyprland.lua` with no `hyprland.conf`, which is what Omarchy ships — parses
`hyprctl dispatch …` as a Lua expression, so every dispatcher fails on its
arguments and `hyprctl eval` with `hl.dispatch` is the only route. An instance
started with `-c` on a `.conf` runs the classic parser and takes native
dispatchers. The harness generates a `.conf`, so it uses plain dispatch for the
nested session and reserves the Lua form for what it asks of the parent.

## Stream and routing model

Preserve EasyEffects semantics rather than reducing audio to one ambiguous
"source" selector: enumerate live playback application streams; expose per-stream
volume and mute where supported; show and control whether a stream is processed;
keep input and output pipelines separate, each singular; distinguish virtual
processing nodes from physical endpoints; preserve Omarchy speaker-tuning chains;
change routing only after the replacement path is confirmed live; fall back to a
valid physical endpoint if the graph fails.

**Processing inclusion is two operations**, and doing one produces a control that
appears not to work. The core links every new output stream to its sink unless
the node is blocklisted, so clearing a link is undone as soon as the stream is
seen again — and for a client that pins its own target it never takes effect. The
blocklist entry makes the choice durable; the link change makes it happen now.
Both, in that order.

**The core already does both, and the frontend must not.** Writing
`isBlocklisted` on a row of `ModelNodes.outputStreams` reaches `Nodes::setData`,
which chooses the blocklist key, honours `blocklistUsesMediaName`, writes the
setting, and whose `blocklistChanged` handler reconciles every row and relinks the
stream. A frontend composing the entry itself holds a second copy of that policy
and will choose a key the core does not match on — the core tests the node name,
the application id and the process binary, so an entry written under one reads as
absent under another and the next toggle appends a duplicate.

A stream whose client pins its own target (`pw-play --target=…`) stays put when
bypassed, because the link change is metadata-only. It is still refused capture
next time it appears. That is a limitation of the mechanism, not of the control.

**Volume is shown and stepped in the scale the rest of the desktop uses.** A
PipeWire node carries linear amplitude; `pactl` and `wpctl` both report its cube
root, and Omarchy's OSD reads `pactl`. A stream at 0.2 on the node is 58%
everywhere a user can already see it, so the panel displays, steps and fills its
meter in the cube root and cubes on the way back to the node. Presentation only;
nothing below the panel changes, and a 5% step then means what it means
everywhere else.

**Never move a DSP filter's own stream as if it were an application**, which in
practice means honouring **`node.dont-move`**. Omarchy's speaker tuning sets it on
the output leg of its filter-chain sink, with a comment naming the risk: anything
rerouting "all streams" would drag the processing onto the wrong device "or into
the tuning's own sink, which is a cycle". It is not a `PW_KEY_` constant but a
convention WirePlumber reads as a raw string, and it must be honoured on **both**
paths that move a stream — the one taken when a node appears, and the one taken
for nodes already present at startup. Guarding only the first honours the pin for
streams that arrive later and ignores it for everything already running, which is
the common case, since a tuning loads at login.

**Refuse to link a stream whose path returns to 42Hz's own sink.** Detecting that
needs `node.link-group`, not the link graph: the two halves of a loopback — and
of a filter-chain sink — are joined *inside* the module, so no amount of walking
links finds the connection, and `PW_KEY_NODE_LINK_GROUP` is the only thing
relating a playback half to what its capture half points at. Two properties of
the core make this harder than it reads:

- **Neither `node.link-group` nor `target.object` is in the registry's global
  properties.** They arrive only in the node's own info properties, so reading
  them where a node is registered yields empty strings and the test silently
  never fires.
- **The core discards the proof before it is needed.** A capture stream recording
  from 42Hz's sink is not recording from the microphone, so the input pipeline
  ignores it and *removes it from the node model* — the half proving a loop exists
  is thrown away one step before the half that would close it is judged. The
  relationship must be recorded ahead of those tests.

A refusal must **release** the stream, not merely skip it: `onNodeInfo` fires
repeatedly and the two halves register in no guaranteed order, so an earlier
callback may already have pointed the stream at 42Hz. Clearing `target.node` and
`target.object` undoes that and the stream falls back to the default sink.

The guard upstream ships is not this. It compares the default output device
against 42Hz's sink by name — one arrangement — and a loopback sourced from
42Hz's own monitor closes a loop without the default device being involved.

### Alongside Omarchy's speaker tuning

Omarchy ships tunings as **native PipeWire filter chains**, not EasyEffects
presets: `/usr/share/omarchy/default/audio/tunings/*/filter-chain.conf`, fitted by
measurement, redistributing no upstream asset. Conflicting with the EasyEffects
package therefore costs Omarchy nothing. The real question is ordering, and 42Hz
chains in front:

```
application → 42hz_sink → spectrum → level → tuning sink → device
```

With the tuning selected as the default output that forms on its own: 42Hz's
output leg follows the default onto the tuning, and the tuning's pinned leg
reaches the device. One hazard is inherited — a filter-chain sink whose playback
stream pins no target follows the default sink, so making a DSP virtual sink the
default closes a feedback loop through it. Stock EasyEffects behaves identically;
42Hz must detect the cycle rather than link it, hence the rule above.

### DSP-sink volume resolution

Omarchy resolves a selected DSP sink to the physical sink whose volume it really
controls, so volume keys and the output switcher act on the endpoint rather than
on the level going *into* processing. `/usr/bin/omarchy-audio-output-sink` does
this by walking `pactl list sink-inputs`.

**That walk cannot see the derived output leg.** The node feeding the physical
device is a PipeWire filter node carrying no `media.class`, linked port to port,
never enumerated as a sink-input — so the resolver falls through and returns the
DSP sink itself. It is a resolver limitation and **no choice of node naming avoids
it**. Three ways out: present a real sink-input for the output leg (a core
modification), extend the resolver to walk PipeWire links rather than PulseAudio
sink-inputs (an Omarchy contribution that also fixes EasyEffects and tuning
chains), or accept the fallback. The second is preferred. Evidence in
[`docs/spike-02-first-run.md`](docs/spike-02-first-run.md).

## Effects and dependencies

One effect in the first release: an output equalizer backed by one pinned LV2
implementation, the LSP equalizer
`http://lsp-plug.in/plugins/lv2/para_equalizer_x32_lr` from `lsp-plugins-lv2`, a
required runtime dependency. The spectrum separately uses `comp_delay_x2_stereo`
from the same package for A/V sync compensation.

There is **no per-source effect UI to build**, because there is no per-source
chain. A later release may add more effects to the one chain, never a chain per
stream.

**The equalizer is in the chain from startup and stays there.** "On demand" is
the *editor*, not the plugin: adding and removing it as the editor is shown and
hidden would rebuild the output path on every keypress, which is the
interruption milestone 4 forbids. 42Hz writes `DbStreamOutputs::plugins` as the
single entry `equalizer#0` at startup, which also repairs a settings file that
lost it, and offers no plugin management — the chain is that one entry.

**It is a graphic EQ, not upstream's 32-band parametric.** The core gives every
band a type, mode, slope, Q and width, and the defaults are already what a
graphic EQ wants: band type is Bell, mode RLC (BT), slope x1. `numBands` is set
to 10 and `calculateFrequencies()` divides 20 Hz–20 kHz logarithmically into
exactly that many, setting each band's frequency and Q. Only gain is exposed.

`DbSpectrum` draws the same 20 Hz–20 kHz on a logarithmic axis, so band *n* of
*N* sits at `(n + 0.5) / N` across the width — directly under the region of the
picture it affects, without either scale being told about the other. The
equalizer is also *upstream* of the spectrum in the chain, so a boost visibly
lifts the part of the picture it applies to.

**Bypass is the plugin's own flag, not `DbMain::bypass`.** Global bypass calls
`disconnect_filters()` then `connect_filters()`, tearing the output path down
and rebuilding it — the spectrum with it — on every toggle. The equalizer's
`bypass` is an atomic tested at the top of `Equalizer::process()`: the buffer
passes through untouched, the graph never moves, and the spectrum keeps running
while the two are compared. With one effect in the chain these mean the same
thing to a listener and only one of them is free.

**Instantiated is not the same as installed.** With the LV2 provider missing the
core still creates the filter node and passes audio through, so the editor and
its key are backed by `packageInstalled` rather than by the instance existing.

**Band values are flat properties** — `band0Gain` … `band31Gain`, per channel —
so a delegate over an index must reach them as `leftDB["band" + i + "Gain"]`.
That reads the current value and captures no dependency, the same family as
calling `advanceWidth()` in a binding, and there is no dynamic form that
notifies. The editor therefore holds the gains as its own array, seeded from the
settings and written through on change.

## Omarchy theme integration

Theme integration is functional behaviour, not a one-time approximation at
launch.

**Sources, layered in this order.** The resolved palette from
`~/.local/state/omarchy/current/theme/colors.toml`; per-surface role overrides
from the adjacent `shell.toml` (a theme may ship one directly); then
`~/.config/omarchy/shell.toml`, a machine-level override that survives theme
switches and is where `omarchy display text size` writes `[font] base-size`, so
its keys win.

Map the complete usable palette into semantic tokens: background levels,
foreground levels, muted, accent, selection, warning, error, spectrum.

**The spectrum carries the theme's colour.** It is the largest surface and the
state the window rests in, so it is where a theme is recognisable or not. Its
ramp takes lightness from the theme's foreground levels — which already encode how
far from the background each end sits, correctly for light themes as well as dark
— and hue and chroma from the palette. Three rules, each of which some shipped
theme breaks when it is missing:

- **A hue that already exists is kept, and saturation only rises.** The accent is
  not always the more colourful of the two: gruvbox's is a pale teal at 0.16
  saturation against a foreground at 0.59, so deferring to the accent there makes
  the spectrum duller than the theme it came from. A foreground level with no hue
  of its own borrows the accent's.
- **The ramp has one hue, decided once.** Choosing per end gives a cool floor and
  a warm peak, which reads as two colours rather than one signal getting louder.
- **An achromatic accent lends nothing.** A monochrome theme stays monochrome.

**Watch the parent directory, not the theme directory or its files.**
`omarchy-theme-set` replaces `current/theme` by removal and rename, so a watch on
`theme/` or on `colors.toml` is dropped by the swap and never recovers even though
a file reappears at the same path moments later.
`~/.local/state/omarchy/current/` outlives the swap and is the only durable
signal. Re-establish finer-grained watches after every load, and coalesce: one
switch produces a burst.

Theme and font hooks are optional low-latency notifications only; file/state
monitoring is the reliable path. Omarchy's own shell is notified through
Quickshell IPC, which 42Hz cannot receive.

**Follow the fontconfig alias `monospace`, not a resolved family** — naming a
concrete family defeats `omarchy font set`.

**Two contrast tiers.** One ratio applied everywhere is wrong in both directions.
Body text is held to 4.5:1 and replaced outright when it fails. Secondary text —
legend, state-report qualifier, media-name column, an unselected stream's name —
is dimmer by design, so it is held to 3:1 and *lifted* toward white or black only
as far as that ratio, keeping the theme's hue instead of swapping in a neutral.
Both tiers are text; neither `muted` nor `dark_foreground` is decoration.

Start with built-in fallback tokens if Omarchy state is unavailable, and never
edit `/usr/share/omarchy/`, stock themes or user configuration.

Omarchy's shell is itself a Quickshell (QML) application, so 42Hz and the desktop
share a toolkit. `/usr/share/omarchy/shell/Commons/Color.qml` is the reference
implementation for resolving `colors.toml` and `shell.toml` into surface roles,
including `-alpha` companion keys and gradient tokens.

## Runtime states and recovery

Five capabilities, detected and reported independently: application ready; audio
service ready; processing ready; EQ ready; Omarchy theme ready.

A stream that is open and silent is one of these states, not a fault. It is
reported in words, because a truthful spectrum draws nothing for it, and the
report is held for a moment first, since music has rests. Absence of frames is a
different state from frames carrying no signal, and the two are named
differently.

Silence, an unreachable audio service, a stopped pipeline and a crashed process
must never look alike. Each is named in the centre of the window. **An empty
window is not an acceptable report of anything.**

**Losing the audio service is reported; failing to find it at startup is not, and
neither is recovering.** Three gaps, one closed:

- *Closed.* A service that goes away no longer kills the process. `on_core_error`
  called `util::fatal` on `"connection error"`, so a `systemctl --user restart
  pipewire` took 42Hz with it; and `runtimeVersionChanged` was declared and
  emitted nowhere, leaving `audioServiceReady` evaluated once at load and frozen
  for the life of the process. Both are in the patch inventory, and the value is
  written on the object's own thread, since a GUI-thread binding reads it.
- *Inherited.* **42Hz does not reconnect.** After a restart it stays up and
  reports no audio service, but its virtual nodes are gone and nothing rebuilds
  them. Recovery is a manual restart.
- *Inherited.* **An unreachable service at startup aborts.** `pw::Manager`'s
  constructor calls `util::fatal` when the context connection fails, from
  `CoreServices` in `main()`, before the QML engine loads — so *application ready*
  is not a state the window can report.

The last two are upstream defects present in the same code in EasyEffects.
Closing either means a large, invasive rewrite of the core's connection handling —
the plugin filters are built against a core they cannot outlive, and three spin
loops have no exit when nothing will arrive — landing in the least forgiving part
of the derived core and carried across every version bump. That is the
reinvention this architecture exists to avoid. They are documented limitations,
not open work; the design, if ever wanted, is in
[`docs/spike-05-reconnection.md`](docs/spike-05-reconnection.md).

Startup stages: acquire the single-instance identity and create the window with
fallback tokens; resolve and watch theme state; connect to PipeWire and enumerate
streams, devices, virtual nodes and tunings; discover DSP capabilities; create the
processing graph without changing defaults prematurely; reconcile streams and
endpoints; start spectrum delivery and expose only controls backed by live
capabilities.

Device churn must not need a UI restart, and the default route must never be left
pointing at a dead 42Hz node. Tests cover forced termination as well as graceful
shutdown — specifically, killing the process while the default route points *at* a
42Hz node.

## Command surface

Not yet designed. The core carries upstream's `QCommandLineParser` surface — quit,
reset, hide-window, global bypass and its toggle, preset load and query, service
mode, `--debug` — renamed but otherwise inherited. Several name features 42Hz has
not committed to, so this stays empty of promises until milestone 5.

`--debug` is load-bearing for development now, for the reason under *Three traps
in the base*.

## Packaging and upstream

Ship one reproducible Arch package: application, desktop entry, symbolic icon,
AppStream metadata, licences, runtime dependencies. Installation must not require
an Omarchy plugin, hook, service activation or configuration edit. The package
should conflict with EasyEffects so two processors do not compete for the same
streams and virtual-device role.

As a GPL derivative, 42Hz must retain licensing, copyright and
source-availability obligations; credit EasyEffects and identify derived
components; document meaningful modifications and the exact base revision; use
new modules and resources where possible; keep the patch inventory small; test
the boundary between core and frontend; avoid implying affiliation; and track
upstream at planned intervals. Upstream's copyright notice is **extended, never
replaced**, and labels describing genuinely upstream work keep naming upstream.

Contributions are authored under a real name with a public contact address:
relicensing requires agreement from every contributor, which is easier to obtain
or prove from identifiable ones.

### Upstream working copy

The repository vendors no EasyEffects source. `spike/fetch.sh` fetches and
verifies the pinned base into `upstream/`; `spike/reduce-deps.py` applies the
complete patch inventory to it. The build root is the repository: the top-level
`CMakeLists.txt` adds the patched core and then `frontend/`, so a clean checkout
reaches a binary in four commands.

`upstream/` is disposable — re-running `fetch.sh` replaces it wholesale. **Never
treat a hand edit there as done.** Prototype freely, then fold the change into
`reduce-deps.py` and re-run the cycle. Every change to the derived core is a
change to the patch script, so reviewing `reduce-deps.py` is reviewing the entire
delta against upstream. A version bump is a change to the pinned values in
`fetch.sh` followed by re-verification of each patch entry against the new base.

42Hz's own source is tracked in `frontend/` and never copied into the disposable
tree. Its QML is a **separate Qt module** (`hz.ui`) linked into the core's target
as a plugin, rather than files added to the core's module (`ee.ui`, which after
patching registers C++ types and ships no QML). Qt forces this: a QML module is
finalized at the end of the directory scope that declared it, so QML contributed
from `frontend/` to the core's module is embedded in the binary but never reaches
its `qmldir` — a clean build that fails at load. The split is also useful, since
every `import ee.ui` in 42Hz QML is a greppable reach across the facade boundary.

The base is pinned three ways: the upstream commit, a checksum of the downloaded
archive, and a checksum of the extracted file tree. The last exists because
GitHub generates release archives on demand and does not guarantee byte
stability, so a repackaged archive must be distinguishable from changed source.
Changed packaging warns and continues; changed source refuses to build.

## Milestones

1. **Repository and feasibility spike** — pin the base, preserve licensing, map
   frontend/backend coupling, prove access to live spectrum frames, application
   streams, PipeWire endpoints and Omarchy routing behaviour. Build a 42Hz
   executable that owns its derived core and runs without EasyEffects installed.
   Validate the EQ LV2 URI and its failure path. Reassign application identity
   across every inherited surface.
2. **Responsive spectrum shell** — a themed Wayland window whose spectrum and
   essential state stay useful across tiled, floating, narrow, wide and
   fullscreen geometries. Stable identity, single-instance presentation, keyboard
   navigation, capability-specific empty states, continuous adaptation to the
   active theme.
3. **Application mixer** — live playback streams with volume, mute and
   processing-inclusion controls. Verify game, voice-chat, browser and music
   streams; device churn; speaker tuning; virtual sinks. Graph failure is
   *reported*, not recovered from; what this verifies is that the report is
   correct and that nothing outlives the failure.
4. **On-demand EQ** — a responsive output equalizer on the validated LV2
   provider. Resizing or hiding the editor never interrupts audio, and
   missing-plugin behaviour stays honest and recoverable.
5. **Omarchy integration hardening** — live palette, font, scale, light/dark and
   contrast behaviour across representative themes. Diagnostics and command
   controls, PipeWire recovery and forced termination, reproducible Arch package.
6. **First release candidate** — attribution, limitations, build documentation,
   integration tests, upstream update procedure; publish the source release.

## Working test

42Hz is on course when a user can arrange it however they prefer, immediately
understand active audio, mix application streams, bypass processing, and reach EQ
in one brief interaction — while the interface stays visually coherent with the
current Omarchy theme.
