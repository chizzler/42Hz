# 42Hz dev diary

What happened, newest first, one entry per working session: what changed, what
was decided and why, what was verified, what stayed open. Commit hashes are
recorded; because a commit cannot contain its own hash, entries are backfilled
in a follow-up commit.

[`../project.md`](../project.md) records what is *true* about the design.
Findings graduate there once durable and are not repeated here at length.
Detailed evidence is in `docs/spike-*.md`.

---

## 2026-08-31 (night, second pass) — The theme switch under load, and what testing it found

Milestone 2's last item. Three sessions had recorded it as unverifiable because
theme state is machine-global, so switching meant switching the user's desktop.
That was wrong. `omarchy-theme-set` swaps themes with two filesystem
operations — `rm -rf current/theme`, `mv next-theme current/theme` — and a
watcher cannot tell who performed them, so performing them inside a fake `HOME`
is the same event. `spike/theme-switch.sh` does that under a running instance.

**The result: it works.** Six switches across dark to light and back, with a
stream playing throughout and `42hz_sink` reading `RUNNING` at every capture.
matte-black keeps its orange in the spectrum, vantablack stays monochrome down to
its key hints, gruvbox stays warm rather than being "improved" into teal. A burst
of seven swaps with no settling between them collapses to one reload on the last
theme, and a switch *after* the burst still lands — so the coalescer holds and
the watcher survives seven consecutive destructive renames. The EQ editor and the
mixer follow a switch as well as the chrome does.

Getting there found four things, three of them mine.

**A fake `HOME` is not an isolated run.** The adapter resolves its state path
from `QDir::homePath()`, so `HOME` redirects theming. Settings go through
`QStandardPaths`, which honours `XDG_CONFIG_HOME` — and Omarchy sets it. Both
theme harnesses set only `HOME`, so every run since they were written has been
reading and writing the user's real `~/.config/42hz` while carrying a comment
claiming otherwise. It surfaced as an audio profile applied in one run turning up
named in the next, on what was supposed to be a fresh config. spike 02 fenced all
four XDG directories by hand; the theme harness was written later and did not.

**And the leak was hiding a real defect.** With the fence in place and a genuinely
fresh settings file, the editor read band 0 as 22 Hz — the 32-band centre — where
ten bands put it at 30. The panel caches each band's frequency, `numBands` is what
makes it notice a change, and `calculateFrequencies()` writes the new frequencies
one step *after* that. So on a first run every profile was resolved against the
previous band layout. Nothing about those properties notifies, so the window now
signals the rewrite explicitly.

**A sweep needs a source that cannot stall.** A browser throttles its audio when
its window is occluded, and a fullscreen nested session guarantees that; the
sweep lost its spectrum halfway and photographed the silence report. A long noise
file through `mpv` does not. The harness also waits for `42hz_sink` to be
`RUNNING` rather than merely linked, because a captured-but-paused stream leaves
the output pipeline unlinked and every capture is then of `processing stopped`.

**`shot` blamed the wrong thing again.** A window bigger than its output, or
merely positioned past its edge, makes grim say "supplied geometry did not
intersect with any outputs", which reads like a bad rectangle. It is the parent
dropping the session out of fullscreen on a long run. `shot` names that now, and
the sweep re-asserts `expand` per capture rather than once at the start. First
attempt at the guard checked size and not position, and passed a window that fits
but hangs off the edge.

### Still open

Nothing in milestones 1 to 4. Next is milestone 5: the Arch package, the command
surface, and the diagnostics.

---

## 2026-08-31 (night) — The audio profiles, built

**Commit:** `d809ca2`

The design from the previous entry, implemented. `AudioProfiles.qml` is a
singleton holding five curves as anchor points; the editor resolves one against
the band frequencies the core actually produced and writes the result through
the same path a keypress uses.

The interpolation was checked by hand rather than by eye: `bass` at band 0
(29.95 Hz, between the +7 dB anchor at 20 and +6.5 at 60) should be 6.82, and
6.8 is what landed in `equalizerrc`. Bands 1 to 4 the same.

**A restored curve is still named.** `match()` compares the stored gains against
each profile resolved at the same frequencies, within half the editor's step, so
a restart presents `bass` as `bass` rather than as a custom edit. Verified across
a real quit and relaunch.

**Nudging a band drops the name**, and the readout keeps the band. Verified: 6.8
to 7.8 on band 0 and the name gone in the same frame.

One correction on the way. The name was drawn permanently in the readout row
*and* announced as a toast, which is the restatement the density and style
steppers already avoid. It now announces only when the row is not showing it --
so at 280x180 the row says `bass`, and at 200x140, where the row is dropped
entirely, the toast says it instead. Exactly one of the two, at every size.

### Still open

Milestone 2's whole-theme switch under load.

---

## 2026-08-31 (late, second pass) — Audio profiles, scoped

**Commit:** `52ecd6d`

No code. The design for a shipped set of EQ curves, written into `project.md`
before building it.

**Rejected: the core's preset system.** `PresetsManager` has
`loadLocalPresetFile()` and would work, but its presets are whole-pipeline JSON
in the user's config directory and loading one sets the plugins list — which
fights the rule that 42Hz's chain is exactly `equalizer#0`. It also brings add,
rename, import, export, community presets and per-device autoload, all of which
`project.md` defers. A table in the frontend has no file, no install step and no
way to collide with the chain.

**A profile is a curve, not ten gains.** Anchor points in Hz and dB,
interpolated onto whatever `calculateFrequencies()` produced. Ten hard-coded
numbers would be welded to `numBands = 10`, so changing the band count later
would move every curve to the wrong frequencies without anything failing.
Linear in log-frequency and linear in dB, holding the end value outside the
outermost anchors so an anchor at 60 Hz behaves as a shelf.

**Creative control, not correction.** Omarchy already ships speaker tunings
fitted by measurement. These are a different job, and naming them for genres
would blur the two — so they are named for what they do: `flat`, `loudness`,
`speech`, `bass`, `soft`.

Applying one writes the same band gains the editor writes, and nudging a band
drops the name rather than qualifying it.

Milestone 4 now owns this and is no longer closed.

---

## 2026-08-31 (late) — The equalizer

**Commit:** `354d940`

Milestone 4. The core already carried the whole thing — `equalizer.cpp`, 32
bands per channel, APO import/export — so this was a frontend job and a set of
decisions about what not to expose.

**The plugin goes in the chain at startup and stays.** "On demand" is the
editor. Adding and removing the plugin on show/hide would rebuild the output
path on every keypress, which is exactly the interruption the milestone
forbids, so the requirement is met by construction rather than by care.

**A graphic EQ, not upstream's parametric.** `numBands = 10`,
`calculateFrequencies()`, and only gain exposed. Type, mode, slope and width
already default to what a graphic EQ wants — Bell, RLC (BT), x1 — so there was
nothing to set. The layout then came free: `calculateFrequencies()` divides
20 Hz–20 kHz logarithmically, which is the spectrum's own axis, so band *n* of
*N* sits at `(n + 0.5) / N` under the frequencies it moves. The equalizer is
upstream of the spectrum in the chain, so a boost lifts that part of the
picture.

**Bypass moved off `DbMain`.** Global bypass runs `disconnect_filters()` then
`connect_filters()` — it tears the output path down and rebuilds it, spectrum
included, on every toggle. `Equalizer::process()` tests a plain atomic at the
top. With one effect in the chain those mean the same thing to a listener and
only one is free, so `b` drives the plugin's own flag, and the legend it used to
occupy is now `[s]treams  [e]q  [q]uit`.

**Three passes on the panel before it read right.** It first took the mixer's
whole half-surface allowance to draw a flat response, which is a lot of empty
air; the editor asks for four rows now. The zero line was drawn per band, which
came out as ten dashes rather than an axis. And it was drawn in the theme's
control *fill* alpha, which is for what sits behind a control, not for a line —
at that alpha it was rendered and invisible, and each band's minimum-height bar
became a tick with nothing to be measured from.

**Instantiated is not installed.** The core creates the filter node whether or
not the LV2 provider is present, so `[e]q` is advertised on `packageInstalled`
and the panel says so rather than drawing a curve that moves nothing.

The band properties are flat — `band0Gain` … `band31Gain` — so a delegate over
an index reaches them as `leftDB["band" + i + "Gain"]`, which reads and captures
no dependency. Third appearance of that family, after `advanceWidth()` and the
`columns` object. The panel holds the gains as its own array instead.

### Verified

On the debug build in the nested session, with a browser and a music stream
live. The chain formed as
`42hz_sink → hz_soe_equalizer → hz_soe_spectrum → hz_soe_output_level → device`.
Driving the keys: band 0 +8, band 4 −6, band 8 +5, with the readout tracking the
selection at 7.5 kHz for band 8 — which is what
`20 × 1.9953^8 + ½(freq1 − freq0)` predicts. A +12 dB boost on band 0 against
the same boost bypassed are two visibly different spectra, and the band bar goes
muted-grey when bypassed.

The milestone's own requirement, measured rather than assumed: `pw-link -l`
hashes identically across opening the editor, resizing the window to 320x200 and
back, and closing it. The only graph churn in the log is startup, and upstream's
idle unlink when nothing is playing.

Settings round-tripped: `plugins=equalizer#0` and `numBands=10` persist, a second
launch builds from them with no rebuild, and `[0]` leaves the gain keys absent
from `equalizerrc` entirely, since KConfig omits a value equal to its default.

Narrow: at 200x140 the readout row drops and the curve and its selection stay,
which is the right order.

### Still open

Milestone 2's whole-theme switch under load.

---

## 2026-08-31 (evening) — Cutting the documentation back

**Commit:** `b34141d`

4,578 lines of prose against 2,753 lines of frontend. The verification harness
earned its keep — it caught the feedback loop, the `node.dont-move` override and
the volume scale — but the writing had not: entries with section headings and
punchlines, and every session reading more than the last.

`project.md` keeps the decisions and the expensive constraints and loses the
narrative. This diary drops to one compact entry per session. The spike
documents keep their findings and lose their commentary. The sweeps stay, to be
run at milestone boundaries and when a layout rule changes, rather than
reflexively.

---

## 2026-08-31 (afternoon) — Milestone 3's last verification

**Commit:** `22cf9ae`

Browser and game streams, and the mixer's on-screen display, unswept since the
legend and top edge changed. Four defects.

**The mixer's volume was the node's linear amplitude.** `pactl`, `wpctl` and
Omarchy's OSD all report its cube root, so a stream at 0.2 read 58% everywhere a
user could already see it and 20% here. The panel now displays, steps and fills
its meter in that scale and cubes on the way back.

**Bare chrome gave the mixer no edge inset**, so the selection marker lost its
left half to the window edge and every reading lost its `%`. Framed chrome never
showed it, the border having already stood the surface back.

**A mixer too short for its list drew two of three streams silently.** The count
it cannot show is now set into the divider as `+N`.

**A game names its stream after its binary and gives the media name the same
string** — N++ arrived as `N++.bin.x86_64  N++.bin.x86_64`. The media-name column
is blank when it only repeats the name.

The harness had its own, and it is the one that mattered: on a busy parent
workspace the nested output is a small tile, every geometry clamps to it, and the
sweep passed with twenty-one captures of the same window. It now refuses below a
distinguishable size, and `expand` fullscreens the nested window on the parent —
waking the parent's displays, since an idle-blanked desk starves screencopy
exactly as a covered window does.

**Verified.** Full sweep at 2560x1440 with Chromium, mpv, N++ (launched through a
Steam inside the nested session) and an ALSA-compat stream live. All three
per-stream controls reach a browser and a game stream, checked at the graph.
Voice chat is covered only by analogy — Electron clients, so the browser case.
Restarting 42Hz destroys its sink; the session manager recaptures every surviving
stream, but mpv stays paused and Chromium destroys its output node, which is each
application's reaction to losing a sink rather than 42Hz's doing.

**Open:** milestone 2's whole-theme switch under load.

---

## 2026-08-31 — 42Hz was moving Omarchy's speaker tuning

**Commit:** `d3e217d`

`node.dont-move` appeared nowhere in the derived core. Omarchy's tuning
filter-chain sets it on its output leg with a comment naming the exact hazard,
and `project.md` requires 42Hz to honour it.

Reproduced with a null sink plus a pinned loopback, which is a filter-chain
sink's topology without touching any PipeWire config. 42Hz wrote its own sink
onto the pinned node — `target.object` → `42hz_sink` — and **WirePlumber refused
the move.** The tuning survived on someone else's guard; a chain that omits the
pin, or a different session manager, would not have.

Two mechanisms write the target: the node manager when a node appears, and
`Manager::connectStream{Output,Input}` from startup reconciliation and the
blocklist handler. Guarding only the first ignores the pin for everything already
running, which is the common case since a tuning loads at login. Fixing the
second needed `Nodes::get_node_by_id` to be `const`.

**Verified** from a clean cycle on the Release binary: the pinned leg stayed on
the headset with no metadata written to it at all, `mpv` was captured, and the
full chain formed with the tuning selected as default —
`mpv → 42hz_sink → hz_soe_spectrum → hz_soe_output_level → test_tuning → headset`.

This machine ships only the `dell-xps-2026` tuning and is not a Dell, so the
topology was reproduced by hand from the real conf's properties. A run on
matching hardware would be worth more.

---

## 2026-08-30 (night, seventh pass) — Teaching the keyboard

**Commit:** `c923c48`

Key hints now carry the accent at rest — `[s]treams` draws its `s` in accent and
the rest quiet, rendered as `StyledText` with the bracketed head in a `<font>`
tag so the width logic is untouched. Colour on hover teaches nobody who is not
already using a pointer.

The steppers drew `-` and `+` on both controls while style is bound to `[` and
`]`, so the style control advertised keys that move the other one. It reads
`[ bars ]` now.

Chrome mode left the legend: the key works at every size, it is simply not
advertised, and the room belongs to `[e]q` when there is one. That leaves
`[s]treams  [q]uit`.

Which found the collision the previous entry predicted — at 200 px the top edge
drew title and controls into each other. The controls are dropped whole when the
edge cannot hold them beside the title, and the toast comes back at the same
moment.

---

## 2026-08-30 (night, sixth pass) — Controls on the line, and a legend that ranks

**Commit:** `d797903`

The toast was a child of the `Window` and landed on the border line; it moved
into `Surface`, which both chrome modes contain, so it lands inside the border in
framed and at the window edge in bare. Driven by a counter rather than by its
text, since an unchanged property emits no signal and the same message twice
running would have shown once.

Density and style became btop-style steppers drawn into the frame's top edge,
which now walks a sorted list of gaps rather than special-casing the title. That
made `[-/+] density` a restatement of a number already on screen, so both left
the legend, and stopped raising toasts *in framed chrome only* — bare draws
neither readout, so it still announces. The bracket keys stopped being aliases
for `-`/`+` and now step style.

`SpectrumCells.qml` was restored from `d1cf525^` for the style option and arrived
pre-broken: still rescaling each frame to itself, and `cellWidth` called
`fm.advanceWidth()` with nothing else in the binding, so it froze at 10.8 px
against a real 7.2 and asked for 66 columns where 98 fit. A spectrum that stops
short of the right edge looks exactly like quiet high frequencies. One
instrumented run ended the guessing.

Density also had to become real in cells mode, rounded to a whole number of cells
per column — coarse steps of 1, 1, 2, 2, 3, which is what a character grid can
honestly offer.

---

## 2026-08-30 (night, fifth pass) — Refusing the loop

**Commit:** `0bd4ec2`

`pactl load-module module-loopback source=42hz_sink.monitor` no longer closes a
loop through the processing sink.

Walking the link graph could never have found it: the two halves of a loopback
are joined inside the module. Both carry the same `PW_KEY_NODE_LINK_GROUP`, and
the capture half carries `target.object = 42hz_sink`, so the playback half is
judged by what its sibling points at.

Two ways to write it that look right and do nothing. Reading the properties where
nodes are registered gets the registry's *global* props, which carry neither key —
the test ran and logged `link_group=[] target=[]` on every node. And looking the
sibling up in the node model fails because the core removes it first: a capture
stream recording from 42Hz's sink is not recording from the mic, so the input
pipeline drops it. The relationship is recorded ahead of those tests instead.

Refusing was not enough. `onNodeInfo` fires repeatedly and the halves register in
no fixed order, so an earlier callback had already pointed the stream at us. The
refusal clears `target.node` and `target.object`, and the stream falls back to
the default sink.

**Verified** from a clean cycle on the Release binary, with the loopback and two
ordinary streams live: the loopback landed on the headset, `mpv` and
`alsa_playback.nolo_client` in `42hz_sink`. That pairing matters more than the
refusal alone — a guard that also stopped normal capture would pass the cycle
test and break the product.

---

## 2026-08-30 (night, fourth pass) — The mixer sweep, and a cycle it let through

**Commit:** `849e7bb`

Milestone 3's verification at graph level rather than through captures, since the
claims are about link topology and `pactl`/`pw-link` read it directly.

Passed: a music stream captured and named; device churn moving 42Hz's output leg
from headset to HDMI with the captured stream still captured; a `module-null-sink`
appearing as a sink and never as a sink-input; and 42Hz as the default sink not
linking to itself, guarded by upstream at `stream_output_effects.cpp:202`.

Failed: **a stream whose path returns to 42Hz's own sink is linked, not refused.**
One command reproduced it, and the sink went to RUNNING with nothing playing. The
existing guard compares the default output device against 42Hz's sink by name —
one arrangement — and this cycle does not go through the default device at all.
That is 42Hz's own defect, not an inherited one: it is a stated requirement
upstream does not meet by design.

Not covered: browser and game streams, speaker-tuning coexistence, and the
mixer's display of any of it.

---

## 2026-08-30 (night, third pass) — 42Hz was dying every time PipeWire restarted

**Commit:** `76fe070`

Planning milestone 4 turned up two things worth more than the milestone.

**The per-stream EQ goal was never possible.** `DbStreamOutputs::plugins` is one
list for one output pipeline; there are no per-stream chains and adding them is
the rewrite this project avoids. The milestones had it right — both scope and
milestone 4 say *output* equalizer. Decided: one output EQ, and the per-stream
control is inclusion, which the mixer already does. The EQ itself is already in
the core (`equalizer.cpp`, 32 bands per channel, APO import/export), so milestone
4 is a frontend job; step one is putting `equalizer` in that empty list.

**`runtimeVersionChanged` was declared and emitted nowhere**, so `audioServiceReady`
was evaluated once at load and frozen for the life of the process. The whole
capability was decorative.

**And the process was dying anyway.** `on_core_error` called `util::fatal` —
`qCFatal`, which aborts — on `"connection error"`, so a PipeWire restart killed
42Hz rather than degrading it. Both halves are one patch; both writes moved onto
the object's own thread, since a GUI-thread binding now reads the value.

It does not reconnect, and it does not fix startup: `pw_filter_new()` and
`pw_filter_add_port()` both dereference the core, and three spin loops have no
exit when nothing will arrive. Scoping that honestly and stopping was the call;
the design is in [`spike-05-reconnection.md`](spike-05-reconnection.md).
Upstream has the identical bug from the identical code, which makes it the
clearest contribution candidate the project has produced.

**Verified** with a before/after through the same nested session and the same
`systemctl --user restart pipewire`: stack trace and process gone, then no abort
and process alive. Then the whole cycle from clean, on the Release binary.

---

## 2026-08-30 (night, second pass) — A spectrum that tells the truth about level

**Commit:** `d1cf525`

`Spectrum.qml` normalised every frame against its own minimum and maximum, so the
display spanned full height whatever was playing. A flattering bug, which is why
it survived four sessions of looking directly at it: the picture is lively and
moves convincingly with the music, and is not a measurement of anything.

The window's anchors came from reproducing the core's arithmetic offline over
synthetic signals: a 0 dBFS signal reads **-6 dB** (mono mix of `0.5 * (L + R)`
against the Hann window's compensating ×2), and **-90** for the floor, above the
core's -100 clamp.

That closed the empty-window case from a fifth direction: with truthful levels a
silent stream draws literally nothing, so `signalPresent` watches the frame peak
against the renderer's own floor — the only threshold that cannot disagree with
the picture — held 1500 ms, since music has rests. The floor became a singleton
because two components with no parent/child relationship have to agree on it.

**`advanceWidth()` was never following the font.** `StreamPanel`'s six column
widths and `ShellFramed`'s floor called it with nothing else in the binding, so
they captured no dependency. The fix names `metrics.font` rather than
`Theme.fontBaseSize`: both are bindings on the same signal and their order is
undefined.

**Secondary text was outside the contrast guard.** `muted` and `foregroundDim`
carry the legend, the state report's qualifier, the media-name column and every
unselected stream name. They could not simply be added — `legibleOn` replaces a
failing colour with white or black, which would take the theme's hue out of
exactly the places it is most visible — so a second tier at 3:1, reached by
*lifting*. Measured across all 22 themes: 31 of 44 pairs lifted, none replaced.
`matte-black`'s muted was worst at 1.48:1.

**One object was worse than six statements.** Gathering the column widths into a
single object produced four `Cannot read property of undefined` errors: an object
property is undefined until its own binding has run, and the widths reading it
are not guaranteed to run second. It recovers and looks correct, which is exactly
the shape a Release build would never mention.

`canUseSysTray` was removed as dead and put back — `main.cpp` injects it through
`setInitialProperties()`, which fails silently in Release on a key the root
object does not declare.

**Verified** against pink noise at -8, -20, -35 and -50 dBFS RMS: four different
pictures, where the old code would have made them indistinguishable. Columns
following a live text-size change from 12 to 20, with the unguarded bindings
reverted and repeated to confirm the bug was real.

---

## 2026-08-30 (late, third pass) — The theme was arriving, but not in the spectrum

**Commit:** `0fccd97`

`spectrumLow`/`spectrumHigh` mapped to `dark_foreground` and `bright_foreground`,
which are near-neutral by design. Measured across 22 themes: mean saturation 0.18
at the floor and 0.14 at the peak against 0.43 for the accent. The largest
surface in the application was rendering at a third of the chroma available.
`matte-black` is black plus `#e68e0d` at 0.94 saturation, drawn in greys.

The fix keeps the foreground levels' lightness — which already encodes how far
from the background each end sits, correctly for light themes too — and decides
only the colour. Two wrong versions, both caught by gruvbox: taking the accent's
hue outright made it teal, when gruvbox is *more* colourful than its own accent;
and deciding the hue per end ramped teal to cream, two colours rather than one
signal getting louder. So a hue that exists is kept, saturation only rises, and
the peak chooses the hue once for the whole ramp. Floor and peak carry 0.55 and
0.85 of the accent's chroma — a floor at full chroma makes the resting spectrum a
block of solid colour.

`spike/theme-preview.sh` renders 42Hz under any theme with a fake `HOME`
containing only the two files the adapter reads, so light-theme and contrast
verification became repeatable without touching the desktop.

**Verified** across twelve rendered and all 22 measured: no theme ends with a peak
below 7:1, a floor below 1.8:1, or a lightness span under 0.21.

The harness lied a third way: a nested compositor on an **unmapped workspace**
receives no frame callbacks, so screencopy never completes. There is no fix from
inside the nested session.

---

## 2026-08-30 (late, second pass) — Fixing what the sweep found

**Commit:** `f635691`

**The keymap is data now.** The legend defect and the keymap-drift problem were
one thing seen twice: the legend could not shorten because it was a string
literal, and could not stay honest because the bindings lived elsewhere. `Main`
holds `windowBindings`/`mixerBindings` — keys, label, priority, advertised,
action — and `Frame` drops the lowest-priority entries until what remains fits.
`action` receives the key that matched, so a direction pair stays one row.
`advertised` gates the legend and nothing else: a key that silently stops working
is worse than one that stops being mentioned.

**The mixer row shrinks twice.** Columns are measured with `advanceWidth` rather
than guessed in ems, which fixed a latent clip — `processWidth` was 4.6 em against
a word needing 4.9. Reserving the widest flags always left the name 31 px at
240 px, which elided to a bare ellipsis; dropping the reservation would have let a
state disappear. So below that width the words contract to `M` and `B`. Then the
fix broke monotonicity: contracting handed back enough room to reintroduce a
column, so widening 280 → 340 px took the volume meter away. Every decision about
which columns exist is now made against the space left if the flags never
contract.

**Too small is a state, and the floor belongs to the chrome.** Bare asks for
127x48, framed for 179x108, both from font metrics. A single window-level
threshold would have taken a working bare window away to fix a framed problem.
The floor oscillated at first: `minimumHeight` was computed from `Frame`'s label
items, and hiding the shell set those labels invisible — QML propagates
visibility — which collapsed the insets and made the window large enough again.
The window latched, reporting `needs 179 × 78` while sitting at 200x100.

**The dispatch contradiction resolved.** A Lua-configured Hyprland parses
`hyprctl dispatch …` as a Lua expression, so every dispatcher fails on its
arguments; the nested session is started with `-c` on a generated `.conf` and
takes native dispatchers. The config format decides, not the version.

Two more harness traps: a static nested output starves screencopy with VFR on
(`debug:vfr = false`, no longer under `misc:`), and a new instance draws timed
warning banners into its own output for about fifteen seconds.

Found on the way: the core aborts when PipeWire is unreachable at startup, in
`pw::Manager`'s constructor before the QML engine loads. And `pkill -f streams.sh`
matched the shell running it and killed the session's own bash — twice is a
pattern.

**Verified** with the full 21-case sweep re-run against the fixed build, three
live streams, no QML errors, and column appearance monotonic across
240/280/340/400/480/640.

---

## 2026-08-30 (late) — A nested compositor, and the responsive test finally run

**Commit:** `f3f37ec`

Three sessions had ended with "the responsive test is still not done". It cannot
be done on a desktop in use, so this session built `spike/nested-session.sh` and
`spike/geometry-sweep.sh`. Headless would have been better and is not available:
aquamarine has no backend-selection variable and Hyprland no `--headless`.

**Sizing the nested output does not work; sizing the window does.** The output is
a surface in the parent session, so `start 1280x720` produced 1226x688, 1788x688
and 1223x688 across three runs depending only on what else was on the parent's
workspace. Floating the window and using `resizewindowpixel exact` landed on the
requested pixel in all 21 cases. Labelling every capture with the size *granted*
is the only reason that drift was noticed rather than silently mislabelled.

Three things that quietly corrupt evidence, all properties of the observation:
a Hyprland config error is drawn into the output *and* reserves 26 px of the
monitor, silently shrinking every tiled window; `grim` captures the nested
pointer; and `dispatch fullscreen 0` enters fullscreen rather than leaving it, so
the tiled and fullscreen captures came out holding each other's contents.

**Result: the density is right, the chrome is not.** Bar density follows window
width across the whole range, bare mode is correct down to 160x60, everything at
480 px and wider is sound. Below 480 px framed chrome fails in four places with
one cause — every piece of chrome is authored at one size: the legend is a fixed
string that overruns and takes the bottom border with it; the state report's
detail collides with the title; mixer rows lay out at fixed proportions; and at
160x60 the spectrum is not drawn at all, because title row, legend row and insets
consume the window. That last is the forbidden empty window from a direction the
requirement did not anticipate — chrome took the room and the signal yielded
first.

---

## 2026-08-30 (afternoon) — The blocklist key, global bypass, and how to see anything

**Commit:** `b837fc4`

**The crash was not a crash.** `coredumpctl` had nothing and the process was
alive in state `T`, backgrounded on its pts. A suspended Qt client is
indistinguishable from a hung one by looking at it — check the process state
before reading anything into a frozen window.

**The blocklist fix was a deletion.** The planned facade command was the wrong
shape: `Nodes::setData` on `Roles::IsBlocklisted` already picks the key, honours
`blocklistUsesMediaName` and writes the setting, and `onOutputBlocklistChanged`
already reconciles every row and relinks. `toggleProcessing()` writes one model
role and holds no policy. Patch inventory unchanged — the best available core
change was no core change.

**Verified** with two silent `pw-play` streams and a live Chromium: the core
cleared the target metadata, the settings file flushed to **one** `blocklist`
entry under the node name, a fresh start with that blocklist gave both nodes no
target, and pressing `p` again removed the key entirely. The accident that proved
it: a second `pw-play` started while the first was blocklisted was refused
capture, because the key *is* the node name. A stream pinning its own target did
not move when bypassed, the link change being metadata-only.

**Global bypass** was already wired to `DbMain.bypass`; it needed a key and a
place to say so. Bypass looks exactly like working processing, so framed mode's
title reads `42Hz · bypassed` and bare mode reports through the toast.

Three things about seeing what the program is doing: the core silences itself
after Qt has read `QT_LOGGING_RULES`, so `--debug` is the only switch; the log
then lands somewhere other than where you sent it, so check `journalctl` and
never trust an empty redirect; and this Hyprland's dispatchers are reachable
through `hyprctl eval` with `hl.dispatch`, where `focus` takes the window
**object** — passing an address string returns `ok` and does nothing. Do not
probe those dispatchers with junk arguments: they act on whatever has focus.

Driving a GUI on a desktop in use needs a wrapper that focuses 42Hz, re-reads
`activewindow`, and **refuses to send the key** unless 42Hz really has it. It
refused several times.

---

## 2026-08-30 (night) — Cleanup pass over the milestone-2/3 frontend

**Commit:** `9d3f0df`

A quality review on four angles at once — reuse, simplification, efficiency,
altitude. Findings that arrived from more than one direction were the ones worth
acting on.

`stateReport` was a `var` holding a JS object with a branch reading
`points.length`, so it re-ran at 60 Hz, and a `var` has no value equality, so it
notified downstream every time having produced an identical report. Four scalars
now; a `bool` suppresses its own change signal. The wording moved with it:
`StateReport` takes capability booleans and owns the mapping to title, detail and
severity, which is the whole job of a component with that name.

The 60 Hz `requestSpectrumData()` timer ran unconditionally, sixty round trips a
second into the core while nothing played. Gated now.

`Theme` gained `lineThickness`; `Surface` states its gutter once. The theme's
`[controls]` alphas, read since the theme adapter landed and unused, now drive the
divider and the meter track. *Rejected:* expressing the remaining literals as
arithmetic on those tokens — an arbitrary offset applied to a themeable value
looks derived and is not.

`ShellBare` forwarded four properties to `Surface` and added nothing; bare mode
*is* the surface, so the loader points at `Surface.qml`.

**Found and not fixed, and the most important thing here:** the blocklist key is
chosen in the wrong place and too narrowly. `toggleProcessing()` pushes
`row.name`, but the core matches against `application_id` *or*
`app_process_binary` *or* `name`, plus `name:media_name`. A stream blocklisted
under one key reads "bypassed" and toggling appends a second entry.

---

## 2026-08-30 (evening) — The application mixer

**Commit:** `609bac7`

Milestone 3's core: `s` reveals live playback streams with volume, mute and
processing inclusion, driven entirely from the keyboard. Both chrome modes share
a single `Surface.qml`, so a change to how the mixer shares space with the
spectrum cannot land in one mode and not the other.

**Processing inclusion is two operations.** `disconnectStream()` only clears
`target.node`/`target.object`, and `pw_manager.cpp:395` re-links every output
stream unless the node is blocklisted, so a bare disconnect is undone the moment
the stream is noticed again — and for a client pinning its own target it is a
no-op from the start, which looked exactly like a dead keybinding.

`muted` and `bypassed` shared one right-aligned column, so a muted bypassed
stream showed only `muted`. Independent facts, independent columns.

**Testing a mixer without making noise:** a 10-minute silent WAV through
`pw-play`, one instance per stream. Real clients, real sink-inputs, real links,
inaudible, and verifiable from `pactl` rather than by ear. Anything written to
the settings database has to come back out; the blocklist round-tripped to empty.

`build-debug/42hz -q` is safe only when an instance is already running — with
none it starts one in the foreground and blocks, which cost a two-minute timeout
and killed the test it was setting up.

---

## 2026-08-30 (later) — Saying something when there is nothing to show

**Commit:** `5af3a57`

With no audio the window rendered nothing, which is indistinguishable from a dead
PipeWire, a stopped pipeline or a crash.

Nothing here needed a core change, only knowing which existing QML surfaces are
honest. Probed idle and with a stream routed through `42hz_sink`:
`PwManager.runtimeVersion` is empty only without a server connection;
`getPipeLineRate()` is non-zero only while the pipeline runs; and
`ModelNodes.outputStreams` counts what the core is processing. Four states, four
sentences. `getOutputLevelLeft()` stays at `0.0` unless
`setUpdateLevelMeters(true)` is called, so signal presence is read from the
spectrum.

**A model's row count reaches QML through an `Instantiator`, and an `Instantiator`
counts what it has built.** With no delegate it builds nothing and reports `0`
for ever. The first probe read `streams=0` with audio plainly playing, and the
wrong conclusion survived two rounds before an empty `QtObject {}` delegate fixed
it.

The framed legend advertised `[s]treams [e]q [b]ypass`, none of which was bound —
the same class of dishonesty as an empty window meaning four things.

Worth recording: a newly mapped window takes focus, so `wtype` reaches it without
any dispatcher call. A quarter of an hour went into dispatch before noticing the
app was already focused.

---

## 2026-08-30 — Picking a layout by looking at it

**Commit:** `993e96a`

The product goal said "ultra minimal", the layout section said "responds to
available space", and nothing decided which milestone 2 was building. Answered by
building three shells and switching between them on live audio.

**Decision: bare and framed, both permanent.** Framed won on presentation and bare
survives as the thing framed is measured against. **Hover** was cut — revealing
controls on pointer proximity answers a question nobody asked. A fourth,
**corners**, dropped the box and kept only pinned labels on short rules; it read
as unanchored, and the box earns its keep.

The two goals were never in opposition, which is the other thing this settled.
"Ultra minimal" is how much is drawn; "responds to available space" is what
happens when the window changes size. Bar density is the first case of the
second, and it was already working.

Two frame bugs, both from labels straddling a line. A label centred on its edge
puts half its glyph box outside the border, so the frame now pulls its border in
by half a label height. And the gaps in the border are computed from
`TextMetrics.width` with nothing repainting the `Canvas` when those metrics
resolved, so first paint could run at width `0` and draw the line through the
text. Same root cause a third time: the content margin cleared only the stroke,
but a label's upper half sits inside the border.

---

## 2026-08-29 (evening) — Separating the design from its history

**Commits:** `cefe17b`, `ca12ff7`

No code. `project.md` had accumulated four sessions of narrative and stopped
being readable as a statement of the design. Renamed `docs/devlog.md` →
`docs/dev-diary.md`: the file existed, was well maintained, and was not being
reached for, because "devlog" reads like build output. A second chronological
file was rejected outright — two places to record what happened is the ambiguity,
not the fix.

Auditing the narrative, nearly all of it was **already here in more detail**, so
the operation was deletion rather than migration. Milestone entries lost their
"Done / Remaining" tails: a milestone definition is a commitment, its completion
state is a fact about last Tuesday.

Two details existed only in `project.md` and are carried across:

**The KConfig rename was 38 file paths, not one.** Each `kcfgc`-generated settings
class carries its own `<kcfgfile name="...">`, and those decide where settings
land — reassigning the directory without them produces an application that looks
renamed and still writes to upstream's files.

**Verifying "no write occurred" is meaningless unless a write is provoked first.**
The first isolation check confirmed `~/.config/easyeffects` untouched after a run,
which proved nothing: KConfig only persists on change. Generalises past KConfig —
a negative result from a system that no-ops by default is not a negative result.

---

## 2026-08-29 (afternoon) — The Omarchy theme adapter

**Commit:** `b9fea38`

`frontend/theme.hpp`/`theme.cpp` resolve the active theme into semantic tokens and
keep them live; `Main.qml` no longer contains a hard-coded colour.

Three sources in increasing precedence: `current/theme/colors.toml`,
`current/theme/shell.toml`, `~/.config/omarchy/shell.toml`. The third was nearly
missed — it is where `omarchy display text size` writes `[font] base-size` and it
**survives theme switches**, so it must win rather than being a same-rank source.
Two corrections from reading Omarchy's own resolver: the font family is the
fontconfig alias `monospace`, and themes may omit named keys, falling back to the
terminal palette.

**Decision: watch the parent directory.** `omarchy-theme-set` does
`rm -rf current/theme` then `mv`, so a watcher on `theme/` or on `colors.toml` is
dropped by the swap and never recovers — "live reload works, except when it
matters". `current/` outlives the swap. Finer watches are kept as low-latency
extras and re-established after every load, with a 100 ms coalescer.

**Verified** on a running binary: resolution against `osaka-jade` matching every
source key; a live `base-size` change 12 → 17 without restart; a live theme switch
across the destructive swap; and a fallback run with `HOME` empty. That last found
a real gap — with no `dark_foreground` or `bright_foreground` both ends of the
ramp collapsed to the same colour and amplitude became unreadable.

**An hour went into a bug that did not exist.** The window appeared transparent
with no spectrum, and a probe binding that should have been impossible to break
returned nothing. The cause: 42Hz is single-instance, and a process from an
earlier build was still running, so every `build/42hz` became a secondary
instance that asked the old one to present its window and exited. The giveaway
was hardcoding `color: "#ff0000"` and getting a green window. Two habits follow —
`42hz -q` before every run, and never trust a launch whose PID exits immediately.

---

## 2026-08-29 — Where 42Hz's own source lives

**Commit:** `ec9d5dd`

Milestone 1 left the frontend as a 65-line QML string literal inside
`reduce-deps.py`.

**Decision: the repository is the build root.** A tracked top-level
`CMakeLists.txt` adds the patched core and then `frontend/`, so 42Hz's source
sits outside the disposable tree, tracked, compiled from its real path.
*Rejected:* copying `frontend/` in at patch time — it works and recreates the
exact trap the disposable-tree rule exists to prevent, aimed at your own code.
*Rejected for now:* splitting the core into a library, which means rewriting
~30 target references in a file upstream changes freely.

**The obvious way builds cleanly and fails at runtime.** Contributing 42Hz's QML
to the core's module via `qt_target_qml_sources` configured, built 207/207, and
embedded `Main.qml` in the binary — then threw `Failed to load QML UI`, because
the generated `qmldir` had no `Main` entry. **Qt finalizes a QML module at the end
of the directory scope that declared it.** Nothing warned. Fixed by giving the
frontend its own module, `hz.ui`, which turns out better than what it replaced:
every `import ee.ui` in 42Hz QML is a greppable reach across the facade boundary.

Two scope traps, both because CMake does not propagate sideways: `frontend/` needs
its own `CMAKE_AUTOMOC` and its own `qt_policy` calls.

**A silent frontend, and why logs could not have caught it.** Changing `Main.qml`'s
import from `ee.ui` to `hz.ui` was wrong — `Main.qml` *is* `hz.ui`. The
application started, mapped its window, created its nodes and looked healthy with
`StreamOutputEffects` undefined and no signal at all. Every run produced a
zero-byte log, read as "clean" when it only ever meant "muted". What worked was
making state externally observable: the probe put `typeof StreamOutputEffects` and
the point count into the window title and read them back with `hyprctl clients -j`.

---

## 2026-08-28 — Identity reassignment, and closing milestone 1

**Commit:** `b43a017`

Sixteen distinct surfaces carried EasyEffects' identity, all now derived from
constants at the top of `reduce-deps.py`. The patch inventory grew from 5 files to
17, 162 lines to 513.

**Decision: the CMake target keeps its upstream name**, only `OUTPUT_NAME`
changes. Identity is what the system sees, not what CMake calls things.
**Decision: extend the copyright line, do not replace it** — dropping it from a
GPL derivative is a licence violation, and the plugin vendor label
`"Easy Effects"` was deliberately left alone because it labels DSP that really is
upstream's work. **Decision: the application ID is `io.github.chizzler.42Hz`** —
a reverse-DNS ID should name a domain its author controls, and `io.github.<handle>`
is a verifiable ownership claim.

**Renaming the virtual sink to `42hz_sink` silently broke stream enumeration.**
`target.object` is documented as "a name or serial number", and the core decides
by trying a numeric parse first via `util::str_to_num`, which checks only `ec` —
but `std::from_chars` reports success on a **partial** parse. `"42hz_sink"`
parsed as serial `42`, matched nothing, and the stream was dropped from the mixer
while staying audible. `ffplay` does exactly this and vanished; `mpv` and
`paplay`, which set no target, were fine, so a casual test would have passed. The
control mattered: stock EasyEffects on the same host accepted `easyeffects_sink`.
**We introduced this**, purely by choosing a name beginning with a digit. Fixed by
treating `target.object` as a serial only when entirely digits, and deliberately
*not* in `str_to_num` — 18 call sites, several parsing APO values where a trailing
unit may rely on the lenient parse.

**Milestone 1 closed.** Config isolation verified unfenced across a *forced*
write; `mpv`, `ffplay` and `paplay` concurrently enumerated; the EQ LV2 URI
validated both ways, absent forced with `bwrap --tmpfs` since the core only
*appends* `LV2_PATH` — it reports `is not installed`, passes audio through, and
emits ~580 `port symbol not found` warnings, so the frontend must surface
`packageInstalled`; teardown with the virtual sink as default under both `SIGTERM`
and `SIGKILL`; and coexistence with stock EasyEffects, where the socket rename was
load-bearing.

Speaker tuning stood in as PipeWire's own `sink-eq6.conf` filter chain. It pins no
target on its playback stream, so making a DSP virtual sink the default closes a
feedback loop through it. Stock EasyEffects forms the identical loop — inherited,
but a real failure mode, and it argues that 42Hz should detect a cycle through its
own sink.

**A history rewrite** removed a private address from all five commits, free only
because no remote existed. The self-inflicted cost: this diary records commit
hashes, so rewriting from the root orphaned four references and two commit
subjects naming a hash. `filter-branch` exposes a `map` function, so the subjects
were remapped in the same pass. Note for whoever pushes first: **GitHub links
commits to an account by email, not by name.**

---

## 2026-08-27 (afternoon) — Reproducible build, and first light

**Commit:** `b07e7b4`

`reduce-deps.py` hard-coded a scratchpad path from the session that produced it,
and that directory no longer existed — the morning's verification was a claim in
a document rather than a repeatable fact.

**Decision: patch-on-tarball, confirmed.** Nothing about the reproducibility
defect argued for vendoring; it was an unpinned base and a hard-coded path.

**Decision: the extracted tree is disposable.** `fetch.sh` deletes and re-extracts
`upstream/` on every run, build directory included. This converts an aspiration
into a mechanism: the small-patch-inventory obligation was a promise to be
disciplined, and under a disposable tree it is enforced by construction — an edit
not in `reduce-deps.py` does not survive the next fetch.

**Two-tier checksum.** Pinned by commit, by archive checksum, *and* by a digest of
the extracted 709-file tree, because GitHub generates tag archives on demand and
has changed their compression before. Pinning only the archive pins the artifact,
not the content.

**Guards on the patch script.** It refuses a path that is not an EasyEffects tree
and refuses an already-patched one — the second matters more than expected, since
its CMake edits are regex line deletions and a second run would no-op them and
then fail mid-splice, leaving a half-patched tree that looks fine.

**First light.** A 440 Hz sine into `easyeffects_sink` rendered as a single narrow
peak, closing the derivation's central assumption: PipeWire → FFTW → spline →
`newSpectrumData` → plain QtQuick works with no Kirigami, no QtGraphs, no KDE
style. The run was fenced with `XDG_CONFIG_HOME` and needed to be — unisolated,
the first launch would have written over a populated `equalizerrc`.

**The finding that changes something.** `omarchy-audio-output-sink` cannot see the
EasyEffects output leg: `ee_soe_output_level` is a filter node with no
`media.class`, linked port to port, never a sink-input. Asked directly with the
graph live, the resolver hands back its own argument. This overturned an
assumption raised in review — that 42Hz could satisfy the resolver by naming its
downstream stream after its virtual sink. That branch is unreachable regardless.
**Node naming was never the lever.**

---

## 2026-08-27 — Reduced-dependency build verified

**Commit:** `4f04024`

The reduced tree configures, compiles and links against Qt 6.11.2 / KF6 6.29.0
into a 13M binary. Linked KF6 libraries drop 10 → 5; total shared libraries
129 → 123. Both risks pre-registered in spike 01 resolved favourably: `KF6::I18nQml`
does not transitively pull in KDE UI components, and `Qt::Graphs` was QML-only.

**The informative failure.** The first build failed on exactly one target,
`main.cpp`, with `fatal error: kicontheme.h: No such file or directory`. 208 of
209 targets had compiled and the sole casualty was the entry point 42Hz replaces
anyway — a stronger result than a clean first build, because it exercised the
core/frontend boundary and the boundary held. Cause: `main.cpp` includes KDE
headers in both the CamelCase forwarding form and the lowercase real form, and the
patch matched only the former. **Grep both casings in KDE-adjacent code.**

Not done: the binary has never been executed. Running it starts a PipeWire graph
that creates virtual nodes and may alter default routing.

---

## 2026-08-26 — Feasibility spike, and the repository

**Commit:** `3b90e6c`

**Decision: QML frontend, not a TUI.** A TUI *could* carry a spectrum analyser —
`cava` does, braille cells give 2×4 addressable dots — so resolution was never the
obstacle. Rejected because it would mean writing a frontend against a C++ core
reachable only over IPC, contradicting three of this project's commitments:
backend stability over reinvention, single-process design, and a small patch
inventory. Two findings settled it the other way: upstream EasyEffects 8.x is
already Qt6/QML, and Omarchy 4's shell is Quickshell, also QML/Qt6. What survives
from the TUI idea is btop's *economy*. The door is not shut — the core delivers a
plain `QList<QPointF>`.

**Coupling mapped.** KDE coupling confined to 3 files; 62 of 66 QML files import
Kirigami, so no frontend is inheritable; the spectrum facade already exists
upstream. Full evidence in
[`spike-01-frontend-coupling.md`](spike-01-frontend-coupling.md).

**Decision: GPL-3.0-or-later from commit one.** The destination regardless;
licensing at commit one is free, and relicensing later requires agreement from
every contributor by that point.

**Decision: repo-local git identity**, so a project session does not silently set
authorship for every other repository on the machine.
