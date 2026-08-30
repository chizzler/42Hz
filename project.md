# 42Hz

42Hz is an ultra-minimal, Omarchy-native control surface derived from EasyEffects. It preserves EasyEffects' proven PipeWire, stream-routing, and DSP foundations while replacing its conventional interface with a responsive, spectrum-first Qt/QML frontend.

- **Public name:** 42Hz
- **Executable:** `42hz`
- **Working directory:** `~/Work/42Hz/`
- **Status:** milestone 1 complete; milestones 2 and 3 in progress. Milestone 2's responsive sweep has been run and its defects fixed, the theme is verified across every shipped theme and follows a live text-size change; a whole-theme switch under load is what remains. Milestone 3 has been swept at graph level and the two defects it found are fixed — a feedback loop 42Hz built through its own sink, and its overriding of a filter-chain stream's `node.dont-move` pin. Speaker-tuning coexistence is verified against a hand-built filter chain; browser and game streams and the mixer's on-screen display remain. Progress, verification and open threads are tracked in [`docs/dev-diary.md`](docs/dev-diary.md), not here.

### How to read this document

**Commitments** are settled and should be argued with rather than quietly
revised: the product principles, the initial scope, the architecture and its
single-process constraint, the licensing and upstream obligations, the
milestones, and the non-goals.

**Sketches** are provisional and expected to change. They are marked where they
appear. A sketch is a record of current intent, not a hard specification.

**This document records what is *true* about the design** — commitments,
constraints, and requirements, in the present tense. It carries no dates, no
progress, and no account of how anything was discovered.

That account lives in [`docs/dev-diary.md`](docs/dev-diary.md): chronological,
newest first, one entry per working session, recording what changed, what was
decided and why, what was verified, and what remains open. Detailed evidence
lives in `docs/spike-*.md`.

Findings graduate from the diary into this document once durable, and arrive
stripped of their narrative. If you want to know *why* a constraint here exists
or *when* it was established, search the diary for it.

## Product goal

42Hz provides access to the useful functionality of EasyEffects with a ultra
minimal UI allowing the user control on placement. It is a normal
Wayland application window.

The interface follows the economy of BTOP but doesn't slavishly copy its appearance. Information density, layout, and disclosed controls respond to available space. Placement, tiling, floating, workspaces, and fullscreen remain the user's decision.

At its smallest useful size, 42Hz is a live spectrum that quietly confirms audio activity and invites interaction. In it's initial state it appears without permanent sidebars, card grids, fake hardware, or decorative chrome.

## Product principles

### Responsive, not prescribed

No layout is privileged. The interface must remain legible and useful across
a broad range of window dimensions, reorganizing or progressively disclosing
content rather than enforcing a fixed mode or location.

### Spectrum first

The live signal is the resting surface, not decoration around a settings panel.
No signal, unavailable audio, and processing failure are distinct states and
must be reported.

**The spectrum shows level, not shape.** A bar's height is the absolute
magnitude the core reported, placed in a fixed dB window; quiet audio draws a
quiet spectrum. Rescaling each frame to its own minimum and maximum is
forbidden, however much livelier it looks: it makes a whisper and a peak
pixel-identical, and a resting surface that never rests reports nothing at all.

The window is anchored at both ends. The core delivers magnitudes in dB
referenced to full scale and clamped at -100, and a 0 dBFS signal reads **-6 dB**
there — the core mixes to mono as `0.5 * (L + R)` and compensates the Hann
window's coherent gain with a factor of two, which leaves a half. So the ceiling
is -6 dB, where a full-scale signal fills the window exactly and nothing clips,
and the floor is -90 dB, above the core's own clamp so that the clamp lands at
the bottom of the window rather than below it.

The floor is shared with the state report rather than owned by the renderer.
Silence is reported when every point falls below it, so the message appears
exactly when there would otherwise be nothing on screen.

### Mixing is central

42Hz must preserve EasyEffects' application-stream model. Users can identify
active playback streams such as games, voice chat, browsers, and music players;
adjust volume and mute state; and control whether each stream passes through
processing.

**Processing is one chain, and inclusion is the per-stream control.** The
derived core runs a single output pipeline: `DbStreamOutputs::plugins` is one
list, and every stream that is not blocklisted passes through the same effects
in the same order. There are no per-stream chains, and adding them would mean
per-stream pipelines and node graphs — a rewrite of the layer this project
exists not to rewrite.

So the equalizer is an *output* equalizer, and a stream's relationship to it is
binary: included and equalised, or excluded and untouched. That is not a
reduction of the mixer's job but a statement of it — the processing-inclusion
toggle is what applies the EQ to a stream, and it is already there. Per-stream
presets are not a goal of the first release and must not be implied by the
interface.

### Reveal on intent

Stream controls are immediately reachable from the spectrum. EQ and other effects appear when selected and use direct graphical controls with precise values. Hiding an editor never interrupts its processing.

### Omarchy-native

The application behaves as an ordinary, well-mannered Hyprland client and
continuously reflects the active Omarchy theme. It does not install a shell
plugin, require a daemon, prescribe window rules, or modify user or packaged
Omarchy configuration.

### Backend stability over reinvention

Reuse EasyEffects' PipeWire integration, processing pipelines, stream models,
DSP hosting, presets, state handling, and spectrum production wherever
practical. 42Hz is a focused frontend over a minimally changed derived core,
not a new audio engine.

## Initial scope

The first useful release includes:

- a responsive live spectrum analyzer, showing absolute level, in either of two appearances;
- an active application-stream mixer with volume, mute, and processing inclusion;
- clear input/output pipeline and endpoint state;
- global processing bypass;
- an on-demand output equalizer;
- keyboard and pointer navigation at every supported size;
- live synchronization with the complete active Omarchy palette and typography;
- explicit capability and recovery feedback;
- one-command Arch installation.

Preset management, input effects editing, the complete EasyEffects effect catalogue, advanced routing, and extensive per-plugin configuration may follow after the core interaction proves reliable. The architecture must preserve a path to them without exposing unfinished controls.

## Architecture

42Hz is initially one application process containing:

- **EasyEffects-derived core:** PipeWire session integration, stream discovery and routing, input/output pipelines, DSP/LV2 hosting, state, presets, and spectrum production.
- **42Hz frontend:** responsive window lifecycle, spectrum rendering, stream mixer, effect editors, keyboard/pointer interaction, and Omarchy theme adapter.
- **Internal facade:** models and commands for streams, endpoints, pipelines, spectrum frames, effects, EQ, bypass, capabilities, and errors. UI code must not depend directly on upstream EasyEffects screens.

One process and one package are preferred until measured reliability or multiple independent clients justify a backend service. The internal facade must make a later split possible without designing an IPC protocol prematurely.

### Upstream baseline

The derivation rests on the following properties of EasyEffects `v8.2.8`:

- Upstream is already a Qt6/QML application. The derivation is a frontend replacement within one toolkit, not a port.
- KDE/Kirigami coupling is confined to the application entry point and the KDE colour-scheme adapter. The PipeWire, DSP, routing, preset, and state layers carry no KDE UI dependency and require no modification.
- The spectrum is exposed to QML as a pull-based singleton API delivering points pre-resampled to a configurable point count. Responsive resampling is therefore a settings binding, not new DSP code.
- No upstream QML is reusable. 42Hz supplies its entire frontend, which dominates the effort in milestones 2-4.
- Spectrum delivery reaches a plain-QtQuick frontend with no Kirigami, QtGraphs, or KDE style present.

Three properties of the base constrain how work on it is done, and each is easy
to rediscover the expensive way:

- **A Release build cannot be verified from its own logs.** Upstream includes KDE's `KDECompilerSettings`, which defines `QT_NO_DEBUG_OUTPUT` for Release, so `console.log` and QML's own diagnostics are compiled out; QML also resolves undefined identifiers at runtime rather than at build time. A Release build therefore fails silently by construction. Diagnose in a Debug build, or observe the running process from outside it. An empty log means *muted*, never *clean*.
- **A Debug build is silent too, until it is asked.** The core calls
  `QLoggingCategory::setFilterRules("42hz.debug=false")` at the top of `main()`,
  after Qt has already read `QT_LOGGING_RULES`, so neither that environment
  variable nor a Debug build can turn the category back on. `--debug` is the
  only switch that works.
  Where its output lands is not reliably the place you redirected it: runs whose
  stderr was pointed at a file have been observed writing nothing to that file
  while `journalctl` carried the whole log, and one detached run produced
  neither. **Check `journalctl` before concluding a build is mute**, and treat an
  empty redirect file as no evidence at all. The routing has not been pinned
  down; when the log matters, launch from a terminal, where it is dependable.

- **A node name may not begin with a digit.** The core resolves a client's `target.object` by attempting a numeric parse first, and its `str_to_num` helper accepts a partial `std::from_chars` result, so a leading-digit name is misread as a serial and the stream is silently dropped from the model while remaining audible. Handled in the patch inventory for `target.object`; the shared helper is deliberately left lenient. More generally, a rename is not cosmetic when the new name has a different *shape* — leading digits, length, character class — from the old one.

Measured coupling and the patch inventory are recorded in `docs/spike-01-frontend-coupling.md`; first execution of the derived core in `docs/spike-02-first-run.md`; identity reassignment in `docs/spike-03-identity.md`; responsive behaviour across geometries in `docs/spike-04-responsive.md`; the
design for recovering from a PipeWire restart in `docs/spike-05-reconnection.md`.

42Hz is a derived application, not a remote control for an installed EasyEffects executable. A release build contains the EasyEffects-derived core it was tested against; EasyEffects does not need to be installed or running.

## Window and interaction behavior

42Hz uses a conventional Wayland toplevel with a stable application ID.

**The application ID is `io.github.chizzler.42Hz`**, which is also the Wayland
class any Hyprland window rule matches on. Every identity surface the derived
core inherited — executable, config directory and the KConfig file paths that
decide where settings land, presets directory, single-instance lock and socket,
logging category, virtual node names, filter node prefix, node groups, media
classes, desktop entry, metainfo, icons, and portal token — is reassigned, and
all of it derives from constants at the top of `spike/reduce-deps.py`. 42Hz
reads none of EasyEffects' settings and runs alongside it without collision, so
development runs need no `XDG_CONFIG_HOME` fence.

The ID's final component begins with a digit. Desktop entries, AppStream and
Wayland `app_id` all permit this; Flatpak application IDs and D-Bus bus names do
not. Neither binds 42Hz, which registers no D-Bus name and targets an Arch
package, but a Flatpak would need a different ID.

Hyprland owns placement and window management. 42Hz supplies a sensible initial
size, remembers valid user geometry where appropriate, and remains fully usable
when tiled, floated, resized, moved between monitors, or made fullscreen.

### Layout

Two chrome modes, both permanent and switchable by the user:

- **Bare:** the spectrum alone, edge to edge. Nothing else is ever drawn.
- **Framed:** the spectrum inside a drawn border carrying pinned labels.

The frame is drawn geometrically, not typed, so it does not depend on the font
carrying box-drawing glyphs and `omarchy font set` cannot break it. Labels sit
on the border line, which breaks around them.

Within either mode the layout responds to available space rather than switching
among product modes. Bar density is the first instance: the spectrum resamples
to however many bars fit at a target bar width, so a wider window shows more of
the signal instead of a stretched copy of the same picture.

The spectrum has two appearances, and they are the only two: **bars**, filled
pixel columns, and **cells**, a character grid built from the U+2581..U+2588
block elements the way cava and btop draw one. Cells follow `omarchy font set`,
since a character grid is measured in whatever `monospace` resolves to. Both
read the same fixed dB window, so switching between them must never look like
the signal changed. Density applies to both — a cell grid rounds it to a whole
number of cells per column, which is coarse, and coarse is the honest answer
rather than a control that shows a value it is ignoring.

Two rules govern how the layout gives things up as it narrows:

- **Chrome yields before signal.** Labels, legends, restated values and
  decoration are dropped in that order; the spectrum, the state report and every
  reported state are not. A component that will not fit is dropped, never elided
  to a stub — a column reserving the width of a word to render `S…`, or a
  measurement truncated to `at least 18…`, costs the space and delivers none of
  the meaning.
- **A wider window never shows less.** Whatever is disclosed at one size is
  disclosed at every larger size. Any rule that hands width back as the window
  narrows must not be allowed to reintroduce something that was dropped.

**Each chrome mode declares the smallest window it can work in**, and below that
the window reports that it is too small, names the size it needs, and points at
a mode that would fit. The floor belongs to the mode rather than the window:
framed chrome pays for a title row, a legend row and border air that do not
shrink, while bare chrome pays for none of it and stays useful far smaller. A
single window-wide threshold would take a working bare window away to fix a
framed-mode problem.

Every floor is derived from font metrics, so it follows `omarchy display text
size` rather than fixing a pixel count. **A measurement taken by calling
`advanceWidth()` does not follow it on its own.** The call is a method, not a
property, so a binding that only calls it captures no dependency and never
re-runs; the measurement freezes at whatever font was loaded at startup. The
binding must also read the `FontMetrics` object's own `font` property, which
notifies — and reading that rather than the theme's keys is what keeps the
measurement from being taken against a stale font, since both are bindings on
the same signal and their order is not defined.

A floor must not be derived from
anything that depends on visibility: QML propagates `visible` to children, so a
minimum computed from live label geometry collapses at the moment the shell is
hidden for being too small, and the window oscillates between the two answers.

Pinned positions in framed mode:

- **Top left:** identity and state.
- **Top right, on the line:** the spectrum's own adjustments, drawn btop-style
  as a value with a minus to its left and a plus to its right. They sit in the
  border, which breaks around them exactly as it breaks around the title, so
  they cost no signal height.
- **Bottom right:** actions and menus.
- **Centre:** capability and signal state, when there is something to report.

**An adjustment with a permanent value does not also announce itself.** A
control that shows what it is set to makes a transient message a restatement,
and restated values are the first thing the layout gives up. Bare chrome draws
none of these controls, so there it *does* announce — the rule is that exactly
one of the two says it, and it holds at every width, because the controls are
dropped when the top edge cannot hold them beside the title and the
announcement comes back at the same moment.

Whether they fit is decided from font metrics, never from the controls' own
geometry. A width read back off a hidden item is zero, so the test that hid them
would find room for them again and the window would latch — the same trap the
chrome floors avoid.

**A key hint is drawn in the accent, wherever it appears.** `[s]treams` carries
its `s`; a stepper carries the keys that actually move it — `-` and `+` for
density, `[` and `]` for style. A control drawn with `-` and `+` while the keys
that move it are `[` and `]` teaches the wrong thing, so the glyphs are the
bindings rather than generic arrows. This is how a keyboard-first window teaches
itself, so the colour is at rest, not on hover: a hint only visible under the
pointer reaches nobody who is not already using one.

**Announcements are drawn inside the border, never across it.** They belong to
the presentation space, not to the window: anchored to the window they land on
the frame's linework, which reads as damage.

Not everything the keyboard reaches is equal. The mixer and the equalizer are
what the window is for; chrome mode and the spectrum's appearance are tweaks,
and the legend gives up tweaks first. An adjustment that has become an on-screen
control leaves the legend entirely rather than restating itself there.

The tiers below are a *sketch* — useful names for regions of a continuum, not
breakpoints to implement:

- **Minimal:** spectrum, signal state, and essential processing status.
- **Compact:** spectrum plus active application streams and concise mix controls.
- **Expanded:** stream mixer, pipeline/effect navigation, and the selected effect editor.

Clicking or invoking a keyboard action reveals the next relevant control. Escape
dismisses transient controls without stopping audio. A second launch presents
the existing instance.

### Verifying responsive behaviour

Responsive claims are verified by capture, not by inspection, and not on a
desktop that is in use. A tiling parent undoes every resize within a second,
focus-follows-mouse hands keystrokes to whatever is under the pointer, and a
screenshot catches whichever window is on top.

`spike/nested-session.sh` starts a second Hyprland on its own Wayland socket
from a generated config, and `spike/geometry-sweep.sh` drives a capture sweep
through it. The nested session reads no user configuration and writes none.

Theme fidelity is verified the same way. The theme adapter resolves its state
path from the home directory, so `spike/theme-preview.sh` renders 42Hz under any
theme in `/usr/share/omarchy/themes` by giving it a fake `HOME` containing
nothing but the two files the adapter reads. No theme is switched and the
running desktop never changes.

The nested session must be visible on the parent's **active workspace** for the
whole of a sweep. A compositor nested in a window renders only while that window
receives frame callbacks, and an unmapped workspace delivers none — captures
then block rather than fail. There is no fix from inside the nested session.

Geometry is set on the *window*, never on the nested output. The output is a
surface in the parent session, so the parent's layout decides its size and a
`monitor` rule does not; a floating window sized with
`dispatch resizewindowpixel exact` is reliable to the pixel. The output is a
ceiling, geometries are clamped to it, and a capture is labelled with the size
actually granted rather than the size requested.

Three properties of the observation corrupt evidence quietly, in the same way
the Release build and the logging routing do:

- **A Hyprland config error is drawn into the output and reserves space in it.**
  One invalid key produces a banner across the top of every capture and a
  monitor `reserved` region that silently shrinks every tiled window.
  `Hyprland --verify-config -c` is the check.
- **`grim` captures the nested pointer**, which the nested compositor draws into
  its own output. `cursor:inactive_timeout` removes it.
- **`dispatch fullscreen 0` enters fullscreen; it does not leave it.**
  `fullscreenstate` names a state rather than toggling toward one.
- **A static nested output starves screencopy.** With VFR on, a compositor
  showing unchanging content stops producing frames and `grim` waits forever for
  one, so a capture of a silent, still window hangs while the same capture of a
  live spectrum returns at once. It reads as a wedged application.
  `debug:vfr = false` — the option is no longer under `misc:`.
- **A new instance draws timed warning banners into its own output** for about
  fifteen seconds. Wait them out before capturing.

Which form of `hyprctl dispatch` works is decided by how the *instance* was
configured, not by the Hyprland version. A Lua-configured Hyprland — a
`hyprland.lua` with no `hyprland.conf`, which is what Omarchy ships here —
parses `hyprctl dispatch ...` as a Lua expression, so every dispatcher fails on
its arguments and `hyprctl eval` with `hl.dispatch` is the only route. An
instance started with `-c` on a `.conf` runs the classic parser and takes native
dispatchers. The harness generates a `.conf` and therefore uses plain dispatch
for the nested session, reserving the Lua form for the one thing it asks of the
parent.

### Keyboard

Every action is reachable by key at every window size, and only bindings backed
by a live capability are advertised in the interface.

**A capability the binding does not have is a different case from a window too
narrow to mention it.** Size only decides what is *said*; the key still works.
An absent capability means there is nothing to act on, and there the key answers
instead — it reports why, in the same place a mode change is reported, and does
not touch the graph. A key that silently does nothing and a key that quietly
does damage are both worse than a key that says what is missing.

Global bypass is the standing example. It is backed not by the pipeline running
but by the output chain *containing something to switch off*, and until the
equalizer is in that chain there is nothing. The core implements bypass by
substituting an empty plugin list, so with the list already empty the graph it
rebuilds is identical to the one it tore down — an interruption, and a window
announcing a state it is not in.

The bindings are published as data that the key handler and the interface both
read. A binding carries its key, its label, the priority it is given up at when
the legend must shorten, and whether a live capability backs it. Advertising is
gated on that capability; the action never is, because every action stays
reachable by key at every size and a key that silently stops working is worse
than one that stops being mentioned.

| key | action |
|---|---|
| `s` | show or hide the mixer |
| `b` | global processing bypass — advertised only while the output chain holds an effect |
| `f`, `1`, `2` | chrome mode — documented, not advertised; the legend's room belongs to the mixer and the equalizer |
| `-` / `+` | bar density — shown as a control in framed chrome, not in the legend |
| `[` / `]` | spectrum style — as above; the bracket keys sit beside the density pair |
| `Escape` | dismiss transient controls; never stops audio |
| `q`, `Ctrl+W` | quit |

While the mixer is up it takes the keys it needs and the rest still reach the
window:

| key | action |
|---|---|
| `↑` / `↓` | select a stream |
| `←` / `→` | volume |
| `m` | mute |
| `p` | processing inclusion |

42Hz may ship optional example Hyprland rules for common arrangements, but installation never applies them automatically.

## Stream and routing model

Preserve EasyEffects semantics rather than reducing audio to a single ambiguous "source" selector:

- enumerate live playback application streams;
- expose per-stream volume and mute when supported;
- show and control whether a stream is processed;

Controlling whether a stream is processed is two operations, and performing
only one of them produces a control that appears not to work. The core links
every new output stream to its sink unless the node is blocklisted, so clearing
a stream's link is undone as soon as the stream is seen again — and for a client
that pins its own target it never takes effect at all. The blocklist entry is
what makes the choice durable; the link change is what makes it happen now.
Both, always, in that order.

**The core already performs both, and the frontend must not.** Writing
`isBlocklisted` on a row of `ModelNodes.outputStreams` reaches `Nodes::setData`,
which chooses the blocklist key, honours `blocklistUsesMediaName`, and writes
the setting; the `blocklistChanged` handler then reconciles every row's
`is_blocklisted` and links or unlinks the stream. A frontend that instead
composes the blocklist entry itself is holding a second copy of that policy and
will choose a key the core does not match on — the core tests the node name, the
application id and the process binary, so an entry written under one of them
reads as absent under another, and the next toggle appends a duplicate rather
than clearing the original.

A stream whose client pins its own target — `pw-play --target=…` does — stays
where it is when it is bypassed, because the link change is metadata-only. It is
still refused capture the next time it appears. This is a limitation of the
mechanism, not of the control.

- keep input and output processing pipelines separate, and note that each is
  singular: one chain per direction, shared by every stream in it;
- distinguish virtual processing nodes from effective physical endpoints;
- preserve Omarchy speaker-tuning chains;
- never move a DSP filter's own stream as if it were an application, which in
  practice means honouring **`node.dont-move`**: some streams are not
  applications and their routing is a structural fact rather than a preference.
  Omarchy's speaker tuning sets it on the output leg of its filter-chain sink,
  with a comment naming the risk — anything rerouting "all streams" would drag
  the processing onto the wrong device, "or into the tuning's own sink, which is
  a cycle". It is not a `PW_KEY_` constant but a convention WirePlumber reads as
  a raw string, and it must be honoured on both paths that move a stream: the
  one taken when a node appears, and the one taken for nodes already present
  when 42Hz starts. Guarding only the first honours the pin for streams that
  arrive later and ignores it for everything already running;
- refuse to link a stream whose path returns to 42Hz's own sink;

**Detecting that path needs `node.link-group`, not the link graph.** The two
halves of a loopback — and of a filter-chain sink — are joined *inside* the
module, not by a PipeWire link, so no amount of walking links finds the
connection. PipeWire marks them with `PW_KEY_NODE_LINK_GROUP` instead, and that
is the only thing that relates the playback half to what its capture half is
pointed at.

Two properties of the core make this harder than it reads:

- **Neither `node.link-group` nor `target.object` is in the registry's global
  properties.** They arrive only in the node's own info properties, so reading
  them where a node is registered yields empty strings and a test built on them
  silently never fires.
- **The core discards the proof before it is needed.** A capture stream
  recording from 42Hz's sink is not recording from the microphone, so the input
  pipeline ignores it and *removes it from the node model* — the half that
  proves a loop exists is thrown away one step before the half that would close
  it is judged. The relationship must therefore be recorded ahead of those
  tests, not looked up afterwards.

A refusal releases the stream rather than merely skipping it. `onNodeInfo` fires
repeatedly and the two halves register in no guaranteed order, so an earlier
callback may already have pointed the stream at 42Hz; clearing `target.node` and
`target.object` undoes that, and the stream falls back to the default sink.

The guard upstream ships is not this. It compares the *default output device*
against 42Hz's sink by name — one arrangement — and a loopback sourced from
42Hz's own monitor closes a loop without the default device being involved.
- change routing only after the replacement processing path is confirmed live;
- fall back to a valid physical endpoint if the graph fails or disappears.

42Hz chains in front of a speaker-tuning filter-chain sink, and that
arrangement is verified: with the tuning sink selected as the default output,
applications land in 42Hz's sink, 42Hz's output leg follows the default onto the
tuning, and the tuning's own pinned leg reaches the device — `app → 42hz_sink →
spectrum → level → tuning → device`, with no cycle and the pin untouched. One hazard is inherited: a filter-chain sink whose playback stream pins no target follows the default sink, so making a DSP virtual sink the default closes a feedback loop through it. Stock EasyEffects behaves identically, but 42Hz must detect a cycle through its own sink rather than link it — hence the constraint above.

Omarchy's speaker tuning is a **native PipeWire filter-chain**, not an EasyEffects preset. `/usr/share/omarchy/default/audio/tunings/` ships `filter-chain.conf` files fitted by measurement from an EasyEffects profile, redistributing no upstream asset. Conflicting with the EasyEffects package therefore costs Omarchy's tuning nothing. The coexistence problem is 42Hz chained behind a filter-chain sink — an ordering and endpoint-resolution question — not 42Hz versus EasyEffects.

### DSP-sink volume resolution

Omarchy resolves a selected DSP sink to the physical sink whose volume it really controls, so that volume keys, the output switcher, and the shell audio panel act on the endpoint rather than on the level going *into* processing. `/usr/bin/omarchy-audio-output-sink` implements this by walking `pactl list sink-inputs`.

**That walk cannot see the EasyEffects-derived output leg.** The node feeding the physical device is a PipeWire filter node carrying no `media.class`, linked port to port. It is never enumerated as a sink-input, so the resolver falls through and returns the DSP sink itself.

This is a resolver limitation, not an identity-negotiation problem, and **no choice of node naming avoids it.** 42Hz must resolve it one of three ways — presenting a real sink-input for the output leg (a core modification), extending the resolver to walk PipeWire links rather than PulseAudio sink-inputs (an upstream Omarchy contribution that also fixes EasyEffects and tuning chains), or accepting the fallback and its consequences. The second is preferred. Evidence and trade-offs are in `docs/spike-02-first-run.md`.

For the first release, the Arch package should conflict with EasyEffects so two processors do not compete for the same streams and virtual-device role. Safe coexistence can be considered later only after application IDs, PipeWire nodes, settings, presets, autostart, and routing ownership are isolated and tested.

## Effects and dependencies

The first release ships one effect: an output equalizer backed by one pinned LV2
implementation. On Arch Linux this is the LSP equalizer
`http://lsp-plug.in/plugins/lv2/para_equalizer_x32_lr`, supplied by
`lsp-plugins-lv2`; its package is a required runtime dependency. The spectrum
separately uses `comp_delay_x2_stereo` from the same package for A/V sync
compensation.

**There is no per-source effect UI to build**, because there is no per-source
chain to configure — see *Mixing is central*. The effect list is one list for
the whole output pipeline; a stream is either included in processing or it is
not, and that control is already in the mixer. What a later release may add is
more effects *in* that chain, never a chain per stream.

The chain is currently empty. `DbStreamOutputs::plugins` defaults to no plugins,
so the output pipeline runs as a live passthrough, and global bypass has nothing
to switch off — which is why its binding is not advertised until the equalizer
is in that list. Putting it there is the first step of milestone 4.

## Omarchy theme integration

42Hz must fully and continuously adapt to the Omarchy theme selected by the user. Theme integration is functional behavior, not a one-time approximation at launch.

- Read the resolved palette from `~/.local/state/omarchy/current/theme/colors.toml`, and per-surface role overrides from the adjacent `shell.toml`, when available. A theme may ship `shell.toml` directly to override the generated file.
- Layer `~/.config/omarchy/shell.toml` on top of both. It is a machine-level override that survives theme switches and is where `omarchy display text size` writes `[font] base-size`, so its keys must win over the theme's.
- Map the complete usable palette into semantic UI tokens, including background levels, foreground levels, muted state, accent, selection, warning, error, and spectrum colors.
- **The spectrum carries the theme's colour.** It is the largest surface in the
  application and the state it rests in, so it is where a theme is either
  recognisable or not. Its ramp takes its lightness from the theme's foreground
  levels — which already encode how far from the background each end should sit,
  in the correct direction for a light theme as well as a dark one — and its
  hue and chroma from the palette. Three rules, each of which a shipped theme
  breaks when it is missing:
  - **A hue that already exists is kept, and saturation only ever rises.** The
    accent is not always the more colourful of the two: gruvbox's is a pale teal
    at 0.16 saturation against a bright foreground at 0.59, so deferring to the
    accent there makes the spectrum duller and colder than the theme it came
    from. A foreground level with no hue of its own borrows the accent's.
  - **The ramp has one hue, decided once.** Choosing per end gives a cool floor
    and a warm peak, which reads as two colours rather than one signal getting
    louder.
  - **An achromatic accent lends nothing.** A monochrome theme stays
    monochrome rather than being handed a colour it did not choose.
- Follow the active Omarchy font and text scaling where exposed.
- Watch the atomically replaced current-theme state and apply changes live without restarting the application or audio graph. **Watch the parent directory, not the theme directory or its files.** `omarchy-theme-set` replaces `current/theme` by removal and rename, so a watch on `theme/` or on `colors.toml` is dropped by the swap and never recovers, even though a file reappears at the same path moments later. `~/.local/state/omarchy/current/` outlives the swap and is the only durable signal. Re-establish the finer-grained watches after every load, and coalesce: one switch produces a burst of events.
- Use theme and font hooks only as optional low-latency notifications; file/state monitoring remains the reliable path. Omarchy's own shell is notified through Quickshell IPC, which 42Hz cannot receive, so this is not a preference but the only available route.
- Follow the font family Omarchy manages system-wide, which is the fontconfig alias `monospace` rather than a concrete family. Naming a resolved family defeats `omarchy font set`.
- Derive contrast-safe fallbacks when a theme omits a value or produces an illegible pairing. Two tiers, because one ratio applied everywhere is wrong in both directions. Body text is held to 4.5:1 and replaced outright when it fails. Secondary text — the legend, the state report's qualifier, the media-name column, an unselected stream's name — is dimmer by design, so it is held to 3:1 and *lifted* toward white or black only as far as that ratio, which keeps the theme's hue instead of swapping the colour for a neutral. Both tiers are text; neither `muted` nor `dark_foreground` is decoration.
- Start with built-in fallback tokens if Omarchy state is unavailable.
- Keep all 42Hz mappings inside the application; never edit `/usr/share/omarchy/`, stock themes, or user configuration.

Omarchy's own shell is a Quickshell (QML) application, so 42Hz and the desktop shell share a toolkit. `/usr/share/omarchy/shell/Commons/Color.qml` is the reference implementation for resolving `colors.toml` and `shell.toml` into surface roles, including the `-alpha` companion keys and gradient-token handling.

Theme fidelity includes light and dark themes, but signal clarity, focus visibility, and readable contrast take priority over literal color reuse.

## Runtime states and recovery

Detect and report capabilities independently:

- **Application ready:** the binary and derived core started.
- **Audio service ready:** PipeWire and required session interfaces are reachable.
- **Processing ready:** virtual nodes and the processing graph are live.
- **EQ ready:** the supported LV2 provider was discovered and instantiated.
- **Omarchy theme ready:** resolved theme and font state were loaded.

A stream that is open and silent is one of these states and not a fault. It is
reported in words, because a truthful spectrum draws nothing for it; the report
is held for a moment first, since music has rests and a message that blinks on
every one of them is noise. Absence of frames is a different state from frames
that carry no signal, and the two are named differently.

Silence, an unreachable audio service, a stopped pipeline and a crashed process
must never look alike. Each is named in the centre of the window, in the space
the signal would otherwise occupy. An empty window is not an acceptable report
of anything.

**Losing the audio service is reported; failing to find it at startup is not,
and neither is recovering from it.** Three distinct gaps, of which one is
closed:

- *Closed.* A service that goes away no longer kills the process.
  `on_core_error` called `util::fatal` — `qCFatal`, which aborts — on
  `"connection error"`, so a `systemctl --user restart pipewire` took 42Hz with
  it. And `runtimeVersionChanged` was declared and emitted nowhere, which left
  `audioServiceReady` evaluated once at load and frozen for the life of the
  process, unable to go false for the very event it exists to report. Both are
  in the patch inventory, and the value is now written on the object's own
  thread rather than the PipeWire one, since a GUI-thread binding reads it.
- *Inherited, not fixed.* **42Hz does not reconnect.** After a restart it stays
  up and honestly reports no audio service, but its virtual nodes are gone and
  nothing rebuilds them. Recovery requires a manual restart of 42Hz.
- *Inherited, not fixed.* **An unreachable service at startup aborts.**
  `pw::Manager`'s constructor calls `util::fatal` when the context connection
  fails, from `CoreServices` in `main()`, before the QML engine loads. So
  *application ready* is not a state the window can report.

**These two are upstream defects, and 42Hz does not fix upstream defects.**
EasyEffects has both, from the same code, and the derivation inherits them. Each
would take a large, invasive rewrite of the core's connection handling — the
plugin filters are built against a core they cannot outlive, and three spin
loops have no exit when nothing will ever arrive — landing in the least
forgiving part of the derived core and carried across every version bump. That
is precisely the reinvention this project's architecture exists to avoid.

They are limitations of the release, are documented as such, and are not open
work. The design, if it is ever wanted, is recorded in
`docs/spike-05-reconnection.md`. What 42Hz owes here is honesty rather than
recovery: the loss of the audio service is reported and never mistaken for
silence, which it now is.

Startup proceeds in stages:

1. Acquire the single-instance identity and create the responsive window with safe fallback tokens.
2. Resolve and begin watching Omarchy theme state.
3. Connect to PipeWire and enumerate streams, devices, virtual nodes, and speaker tuning.
4. Discover required DSP capabilities.
5. Create the processing graph without changing existing defaults prematurely.
6. Reconcile streams and endpoints through the Omarchy-aware routing policy.
7. Start spectrum delivery and expose only controls backed by live capabilities.

The application should recover from PipeWire restarts and device churn without a UI restart. It must never leave the default route pointing at a dead 42Hz node. Tests must cover forced termination as well as graceful shutdown, and specifically the case the requirement exists for: killing the process while the default route points *at* a 42Hz node.

## Command surface

Not yet designed. The derived core carries upstream's `QCommandLineParser`
surface — quit, reset, hide-window, global bypass and its toggle, preset load
and query, service mode, and `--debug` — renamed to `42hz` but otherwise
inherited. Several of those options name features 42Hz has not committed to, so
this section stays empty of promises until milestone 5 settles which of them
42Hz owns.

One of them is load-bearing for development now: **`--debug` is the only way to
make the core say anything**, for the reason recorded under *Upstream baseline*.

## Packaging and upstream strategy

Ship one reproducible Arch package containing the application, desktop entry, symbolic icon, AppStream metadata, licenses, and required runtime dependencies. Installation must not require an Omarchy plugin, manual hook, service activation, or configuration edit.

42Hz is a GPL-compliant EasyEffects derivative. It must:

- retain applicable licensing, copyright notices, and source-availability obligations;
- credit EasyEffects and identify derived components;
- document meaningful modifications and the exact upstream base revision;
- use new modules and resources where possible;
- minimize unavoidable upstream edits and maintain a small patch inventory;
- test the boundary between the derived core and 42Hz frontend;
- avoid implying official affiliation with EasyEffects or Omarchy;
- track and integrate upstream changes at planned intervals.

Contributions are authored under a real name with a dedicated public contact address, matching the convention of the GPL/system-tooling projects 42Hz sits among and of EasyEffects itself. This is not ceremony: relicensing requires agreement from every contributor, which is materially easier to obtain — or to prove — from identifiable ones.

Upstream's copyright notice is **extended, never replaced**. Dropping it from a GPL derivative would be a licence violation, and labels that describe genuinely upstream work — the plugin vendor string, for instance — keep naming upstream rather than 42Hz.

Generally useful backend-decoupling fixes may be offered upstream, but they are not a prerequisite for progress.

### Upstream working copy

The repository does not vendor EasyEffects source. `spike/fetch.sh` fetches and
verifies the pinned base into `upstream/`; `spike/reduce-deps.py` applies the
complete patch inventory to it. The build root is the repository itself: the
top-level `CMakeLists.txt` adds the patched core and then `frontend/`, so a
clean checkout reaches a built binary in four commands.

42Hz's own source is tracked in `frontend/` and is never copied into the
disposable tree — the file you edit is the file that compiles. Its QML is a
**separate Qt module** (`hz.ui`) linked into the core's target as a plugin,
rather than files added to the core's own module (`ee.ui`, which after patching
registers C++ types and ships no QML).

That separation is forced by Qt, which finalizes a QML module at the end of the
directory scope that declared it: QML contributed from `frontend/` to the core's
module is embedded in the binary but never reaches its `qmldir`, producing a
clean build that fails at load. The split is also useful — every `import ee.ui`
in 42Hz QML is a direct reach across the facade boundary, and greppable as
such.

The base is pinned three ways: the upstream commit, a checksum of the downloaded
archive, and a checksum of the extracted file tree. The last of these exists
because GitHub generates release archives on demand and does not guarantee they
are byte-stable, so a repackaged archive must be distinguishable from changed
source. Changed packaging warns and continues; changed source refuses to build.

**The extracted tree is disposable.** Re-running `fetch.sh` deletes and
re-extracts it without prompting, and takes any build directory inside it along.

This is the mechanism that makes the small-patch-inventory obligation
enforceable rather than aspirational. A modification that is not in
`reduce-deps.py` does not survive the next fetch, so no upstream edit can
quietly become load-bearing, and the patch inventory cannot drift out of step
with what is actually being built. Discarding the build directory is part of the
guarantee, not a cost of it: a rebuilt source tree deserves a fresh build, and a
build reflecting a source state that no longer exists is precisely the
inconsistency this arrangement prevents.

Consequently:

- Never treat a hand edit under `upstream/` as done. Prototype there freely, then
  fold the change into `reduce-deps.py` and re-run the cycle before relying on it.
- Every change to the derived core is a change to the patch script. Reviewing
  `reduce-deps.py` is reviewing the entire delta against upstream.
- A version bump is a change to the pinned values in `fetch.sh` followed by
  re-verification of each patch entry against the new base.

## Milestones

These are the definitions of done. Which parts are actually done, and what each
one cost, is recorded in [`docs/dev-diary.md`](docs/dev-diary.md).

1. **Repository and feasibility spike**  
   Pin the EasyEffects base, preserve licensing, map frontend/backend coupling, and prove access to live spectrum frames, application streams, PipeWire endpoints, and compatible Omarchy routing behavior. Build a 42Hz executable that owns its derived core and runs without the EasyEffects application installed. Validate the selected EQ LV2 URI and failure path. Reassign application identity across every surface the derived core inherited.

2. **Responsive spectrum shell**  
   Build a normal themed Wayland window whose spectrum and essential state remain useful across representative tiled, floating, narrow, wide, and fullscreen geometries. Establish stable application identity, single-instance presentation, keyboard navigation, and capability-specific empty states. Adapt continuously to the active Omarchy theme.

3. **Application mixer**  
   Expose live playback streams with supported volume, mute, and processing-inclusion controls. Verify game, voice-chat, browser, and music streams; device churn; speaker tuning; and virtual sinks. Graph failure is *reported*, not recovered from — see the inherited limitations under *Runtime states and recovery*; what this milestone verifies is that the report is correct and that nothing is left in a state that outlives the failure.

4. **On-demand EQ**  
   Add a responsive output equalizer backed by the validated LV2 provider. Verify that resizing or hiding the editor never interrupts audio and that missing-plugin behavior remains honest and recoverable.

5. **Omarchy integration hardening**  
   Validate live palette, font, scale, light/dark, and contrast behavior across representative Omarchy themes. Complete diagnostics and command controls, test PipeWire recovery and forced termination, and produce the reproducible Arch package.

6. **First release candidate**  
   Complete attribution, limitations, build documentation, integration tests, and the upstream update procedure; then publish the initial source release.

## Non-goals for the first release

- reproducing every EasyEffects screen or effect;
- inventing a new audio engine or PipeWire session manager;
- requiring an Omarchy shell plugin or persistent backend daemon;
- prescribing where or how large the application window should be;
- silently modifying Hyprland or Omarchy configuration;
- adding decoration that does not improve signal reading, mixing, navigation, or state awareness.

## Working test

42Hz is on course when a user can arrange it however they prefer, immediately understand active audio, mix application streams, bypass processing, and reach EQ in one brief interaction—while the entire interface remains visually coherent with the currently selected Omarchy theme.
