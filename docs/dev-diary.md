# 42Hz dev diary

Chronological record of work, decisions, and dead ends.

**Convention.** Newest entry first — the common case is "what was I doing last
time". One entry per working session, dated. Each entry carries what changed,
what was *decided* (with the reasoning, so it can be revisited rather than
re-litigated), what was verified, and what remains open. Commit hashes are
recorded; because a commit cannot contain its own hash, entries are backfilled
in a follow-up commit.

**This diary records what happened.** [`../project.md`](../project.md) records
what is *true* about the design — commitments, constraints and requirements, in
the present tense, with no dates and no progress. Everything narrative belongs
here: how a thing was found, what it cost, what was tried and rejected, what is
verified and what merely looks verified, and what is still open.

Findings graduate from here into `project.md` once they are durable, and are
stripped of their narrative on the way. Nothing is deleted here when that
happens — this remains the account of record. Detailed evidence lives in
`docs/spike-*.md`.

---

## 2026-08-30 (night, fifth pass) — Refusing the loop

**Commit:** `0bd4ec2`

The defect the mixer sweep found, fixed. `pactl load-module module-loopback
source=42hz_sink.monitor` no longer closes a loop through the processing sink.

### The link graph could never have found it

The first instinct — walk backwards from the stream's input ports and refuse if
the path reaches our own monitor — cannot work. The two halves of a loopback are
joined *inside the module*; there is no PipeWire link between them to walk.

PipeWire already names the relationship. Both halves carry the same
`PW_KEY_NODE_LINK_GROUP`, and the capture half carries `target.object =
42hz_sink`. So the playback half is judged by what its sibling is pointed at,
which is the only relationship that actually exists.

### Two ways to write it that look right and do nothing

**Reading the properties where nodes are registered.** `registerNode` gets the
registry's *global* props, which carry neither key. The test compiled, ran, and
logged `link_group=[] target=[]` on every node. They arrive only in the node's
own info props, which is where upstream reads `app_process_binary` for the same
reason.

**Looking the sibling up in the node model.** It is not there. The core removes
it first:

```
The input stream input.loopback-458292-13 does not have as target the same mic
used as EE input: alsa_input...  The user wants it to record from device
42hz_sink. We will ignore this stream.
Stream/Input/Audio 116 input.loopback-458292-13 has been removed
```

A capture stream recording from 42Hz's sink is not recording from the mic, so
the input pipeline ignores it and drops it from the model. **The half that
proves the loop is discarded one step before the half that would close it is
judged.** So the relationship is recorded ahead of those tests — a set of
link-groups known to read from our sink — rather than looked up after them.

### Refusing is not enough; it has to let go

With the set in place the refusal fired, twelve times, and the loopback was
still in `42hz_sink`. `onNodeInfo` fires repeatedly and the halves register in
no fixed order, so an earlier callback had already pointed the stream at us
before the capture half existed to prove it was a loop. Skipping later
callbacks changes nothing once the metadata is set.

So the refusal clears `target.node` and `target.object`, the way
`disconnectStream` does. The stream then follows the default sink — which for a
monitor loopback is what was wanted anyway.

### Verified

From a clean cycle: `fetch.sh` re-extracted, `reduce-deps.py` re-applied the
whole inventory (`pw_objects.hpp` 3309 -> 3807, `pw_node_manager.cpp` 27511 ->
30799, `pw_node_manager.hpp` 4479 -> 5007), both trees rebuilt, and the
**Release** binary tested — the prototype under `upstream/` was never relied on.

With the loopback and two ordinary streams live at once:

| stream | landed in |
|---|---|
| `output.loopback-…` | sink 69, the headset — refused |
| `mpv` | `42hz_sink` — captured |
| `alsa_playback.nolo_client` | `42hz_sink` — captured |

Only the ordinary streams feed `42hz_sink:playback`. That pairing matters more
than the refusal on its own: a guard that also stopped normal capture would pass
the cycle test and break the product.

Headset muted throughout and restored to unmuted at 100%; default sink never
moved.

### Still open

Milestone 3's remaining coverage: browser and game streams, a hand-built
filter-chain sink for speaker-tuning coexistence, and the mixer's on-screen
display. No voice-chat client exists on this machine.

The filter-chain case is the one to run next, because it is the same mechanism —
a filter-chain sink's two halves share a link-group exactly as a loopback's do,
so this fix should already cover the Omarchy speaker-tuning hazard `project.md`
describes. Should, having not been tested.

---

## 2026-08-30 (night, fourth pass) — The mixer sweep, and a cycle it let through

**Commit:** `849e7bb`

Milestone 3's verification, run at graph level against the real desktop rather
than through captures. `pactl` and `pw-link` are better evidence than a
screenshot here anyway: the claims are about link topology, and the topology is
directly readable.

Recovery is no longer part of what this milestone asks — the PipeWire connection
gaps are recorded as inherited upstream limitations and are not being fixed.

### What passed

**A music stream is captured and named.** `mpv` appeared in `42hz_sink` within
seconds of starting, carrying `application.name = "mpv"` and
`media.name = "pink20.wav - mpv"` — the two columns the mixer draws.

**Device churn.** Switching the default sink from the headset to HDMI moved
42Hz's output leg with it: `hz_soe_output_level:output_FL` relinked from
`alsa_output.…Razer…:playback_FL` to `alsa_output.…hdmi-stereo:playback_FL`. The
captured stream stayed captured and the process stayed up.

**A virtual sink is not an application stream.** A `module-null-sink` appeared as
a sink and never as a sink-input, and 42Hz's routing did not react to it.

**42Hz as the default sink does not link to itself.** With `42hz_sink` set
default, the output leg stayed on the physical headset and nothing fed
`42hz_sink:playback`. The guard is real and upstream's:
`stream_output_effects.cpp:202` returns early from `on_link_changed` when
`defaultOutputDeviceName == ee_sink_node.name`.

The full chain, confirmed and matching what `project.md` describes:

```
mpv -> 42hz_sink:playback
42hz_sink:monitor -> hz_soe_spectrum -> hz_soe_output_level -> alsa_output.<device>:playback
```

That also re-confirms spike-02 from the other direction: the output leg is a
filter node linked **port to port**, never a sink-input, which is exactly why
`omarchy-audio-output-sink` cannot resolve it.

### What failed

**A stream whose path returns to 42Hz's own sink is linked, not refused.**

`project.md` states the requirement outright — "refuse to link a stream whose
path returns to 42Hz's own sink" — and marks it as 42Hz's own, not upstream's:
"Stock EasyEffects behaves identically, but 42Hz must detect a cycle through its
own sink rather than link it."

Reproduced in one command. A loopback whose source is 42Hz's own monitor and
which pins no target:

```
pactl load-module module-loopback source=42hz_sink.monitor
```

It was captured straight into the processing sink:

```
Sink Input #635
	Sink: 90                      <- 42hz_sink
	node.name = "output.loopback-458292-13"

42hz_sink:playback_FL
  |<- output.loopback-458292-13:output_FL
```

So `42hz_sink.monitor -> loopback -> 42hz_sink:playback -> 42hz_sink.monitor`,
a closed feedback loop through the processing sink, made by 42Hz itself under
`processAllOutputs`. The sink went to RUNNING with nothing playing.

The existing guard does not cover this. It compares the default output device
against 42Hz's sink *by name* — one specific arrangement — and this cycle does
not go through the default device at all. Nothing walks the stream's own path.

Tested with the headset muted first, since a self-loop can oscillate. Torn down
immediately; the headset was restored to unmuted at 100% and the default sink to
the headset.

### Not covered

Browser (`chromium`) and game (`steam`) streams are installed and untested; no
voice-chat client exists on this machine. The only Omarchy tuning shipped is
`dell-xps-2026`, which does not match this hardware, so speaker-tuning
coexistence still has to be tested against a filter-chain sink built by hand.
And the mixer's *display* of all of the above — names, percentages, flags — is a
capture job, not a `pw-link` one.

### Still open

**The cycle defect is milestone 3's, and it is ours.** It is a stated 42Hz
requirement that upstream does not meet by design, which puts it in the same
category as the `target.object` fix already in the patch inventory rather than
in the inherited-limitation category the connection gaps went into.

---

## 2026-08-30 (night, third pass) — 42Hz was dying every time PipeWire restarted

**Commit:** `76fe070`

Planning milestone 4 turned up two things worth more than the milestone did.

### The per-stream EQ goal was never possible

`project.md` said, under *Mixing is central*, that a goal was to let EQ presets
apply to each stream. The derived core cannot do that and never could:
`DbStreamOutputs::plugins` is one list for one output pipeline, and every stream
that is not blocklisted passes through the same effects in the same order. There
are no per-stream chains. Adding them means per-stream pipelines and node
graphs — a rewrite of exactly the layer this project exists not to rewrite.

The milestones had it right all along; both the initial scope and milestone 4
say *output* equalizer, singular. Only the principle was aspirational, and
nothing had needed it to be true until the EQ was about to be built on it.

Decided: one output EQ, and the per-stream control is inclusion. Include a
stream and it is equalised, exclude it and it is untouched — which the mixer
already does and which the previous session had already made durable through
the blocklist. `project.md` now says so, and says the interface must not imply
per-stream presets.

Also worth recording for milestone 4: the EQ itself is *already built*. The
derived core carries `equalizer.cpp` with 32 bands per channel — gain,
frequency, Q, width, type, mode, slope, solo, mute — plus `flatResponse()`,
`sortBands()`, `calculateFrequencies()` and APO import/export, all reachable
through KConfig singletons. Milestone 4 is a frontend job. And
`DbStreamOutputs::plugins` currently defaults to empty, so 42Hz's output
pipeline is a live passthrough with no effects in it at all; step one is putting
`equalizer` in that list.

### A capability that could never change

`runtimeVersionChanged` is declared in `pw_manager.hpp` and emitted nowhere in
the codebase. `audioServiceReady` binds to `runtimeVersion`, so it was evaluated
once at load and frozen for the life of the process. The previous entry in
`project.md` claimed it "can only ever go false for a service that drops
afterwards"; in fact it could not go false at all. The whole capability was
decorative, and had been since the theme adapter session first wrote it.

### And the process was dying anyway

Chasing that led to `on_core_error`, which called `util::fatal` on
`"connection error"`. `util::fatal` is `qCFatal`, which aborts. So a PipeWire
restart did not degrade 42Hz — it killed it, against the stated requirement that
it recover from PipeWire restarts without a UI restart. Nobody had noticed
because nobody had restarted PipeWire under it.

Both halves are one patch: emit the signal, and clear the version instead of
aborting. Both writes moved onto the object's own thread with
`QMetaObject::invokeMethod`, because `on_core_info` and `on_core_error` run on
the PipeWire thread and the value is now read by a GUI-thread binding — the
unguarded assignment upstream ships was harmless only while nothing read it.

### What this does not do

It does not reconnect. After a restart 42Hz stays up and honestly reports no
audio service, but `42hz_sink` is gone and nothing rebuilds it. Surviving the
loss is not recovering from it, and the difference is now written down rather
than blurred.

It also does not fix startup. An unreachable PipeWire at *launch* still aborts
in `pw::Manager`'s constructor, before the QML engine loads. That looked small
and is not: `pw_filter_new()` and `pw_filter_add_port()` both dereference the
core, so every plugin would have to be constructible without one, and three spin
loops — the virtual-device wait in the constructor, and `connect_to_pw`'s wait
on `can_get_node_id` — have no exit when nothing will ever arrive. Scoping it
honestly and stopping was the right call; doing half of it silently would not
have been.

### Verified

A genuine before and after, from one log. `build/42hz` was still the unpatched
Release binary, so both were run through the same nested session and the same
`systemctl --user restart pipewire`:

```
20:03:44  pw_manager.cpp:152  No connection to PipeWire. Aborting!
          #6 ... on_core_error (42hz + 0x727d9d)        <- stack trace, process gone
20:04:16  pw_manager.cpp:157  No connection to PipeWire.
                                                        <- no abort, process alive
```

Then the whole cycle from clean: `fetch.sh` re-extracted the tree,
`reduce-deps.py` re-applied the inventory and reported
`src/pw_manager.cpp (17381 -> 17958 bytes)`, both trees rebuilt, and the
*Release* binary was run through another PipeWire restart and stayed up with no
abort logged. The prototype under `upstream/` was never relied on.

Default sink never left the headset across four PipeWire restarts, and 42Hz was
restarted afterwards so its virtual sink came back.

### The reconnection design, and why it stopped at a design

Reconnection was the chosen next step, and it turned out to be on milestone 3's
critical path rather than beside it: "safe recovery after graph failure" is part
of that milestone's definition of done, so M3 cannot close until this exists.

The design is in [`spike-05-reconnection.md`](spike-05-reconnection.md). The
constraint that shapes all of it is that the audio stack cannot be thrown away
and rebuilt: `StreamOutputEffects` hands QML a static `singletonInstance` with
C++ ownership, and upstream's own comment says "We cannot replace it". Every
object must keep its identity and rebuild its PipeWire state in place, which is
what makes this large. One thing helps — the sub-managers hold `pw_core*&` by
reference, so they follow a reassignment for free.

The seam is `pw_manager.cpp:335`, and the constructor's three parts separate
cleanly: Qt wiring (once), thread loop (once), connection (reconnectable). One
`connect(db::Manager…)` sits inside the reconnectable range and has to be
hoisted first or every reconnection doubles a handler.

Stopped there deliberately. It is 200+ lines across four files, in the least
forgiving part of the core — tearing down a connection the server already
dropped, where the failure mode is a use-after-free that presents as the process
disappearing, which is precisely the symptom this session just removed. And a
partial result is worse than none: a manager that reconnects while the plugin
filters stay stale gives silently broken audio instead of an honest report.
Better to execute it from a written design than to half-land it at the end of a
long session.

One thing to decide before writing it: **upstream has the identical bug**, from
the identical code. This is the clearest upstream-contribution candidate the
project has produced, and the alternative is carrying the riskiest patch in the
inventory across every version bump. Carry or contribute is a choice worth
making deliberately.

### Still open

The two gaps above — reconnection, and startup with no service — are now written
into `project.md` as open rather than as one vague sentence, and reconnection
has a design.

A capture of the post-restart window could not be taken: the nested session had
left the parent's active workspace and screencopy does not run there, which the
harness said in exactly those words. The log evidence is stronger anyway.

Everything from the previous entry stands.

---

## 2026-08-30 (night, second pass) — A spectrum that tells the truth about level

**Commit:** `d1cf525`

A code and status review turned up five things. The first was the interesting
one, and it was not a layout bug or a theme bug: the spectrum had never been
showing how loud anything was.

### Every frame was rescaled to itself

`Spectrum.qml` computed the minimum and maximum of each frame and normalised
against them. The display therefore spanned full height at all times, whatever
was playing. A whisper and a peak were pixel-identical; the tallest bar was
always the tallest bar. For an application whose first principle is that the
live signal is the resting surface, the resting surface never rested.

It is a flattering bug, which is why it survived four sessions of looking
directly at it. The picture is lively, it fills the window, and it moves
convincingly with the music — it just is not a measurement of anything.

Decided in favour of truth at a known cost: with absolute levels, the top of
the colour ramp only appears when something is actually loud, so the palette
work from the previous entry shows less of itself on quiet material. That was
the explicit trade, and it is the right way round. A spectrum is an instrument
before it is a decoration.

### Where the window sits, and why those two numbers

The core hands over dB referenced to full scale, clamped at -100 by
`util::linear_to_db`. Rather than guess a range, the core's own arithmetic was
reproduced offline — Hann window, `|X|/n_bands`, the compensating factor of two,
the single-sided correction at the ends — and run over synthetic signals at
known levels.

Two findings set the anchors:

- **A 0 dBFS signal reads -6 dB, not 0.** The core mixes to mono as
  `0.5 * (L + R)` and the ×2 compensates the Hann window's coherent gain of
  0.5, which leaves a half. So the ceiling is -6: a full-scale signal fills the
  window exactly and nothing ever clips.
- **-90 for the floor**, above the core's own -100 clamp so the clamp lands at
  the bottom of the window rather than somewhere below it. Pink noise at
  -60 dBFS RMS — quiet but real — still peaks near -87 per point and stays
  visible.

Between them, loud broadband material peaks around three-quarters height and
sits around a third at the median, which is what a spectrum should look like.

### The empty window from the fifth direction, closed

The known open item — a live but silent stream drawing nothing and saying
nothing — stopped being a separate problem and became the same one. With
truthful levels a silent stream draws literally nothing, so it had to be named.
`signalPresent` watches the frame *peak* against the renderer's own floor, so
the report appears exactly when there would be nothing left to draw, which is
the only threshold that cannot disagree with the picture.

Held for 1500 ms rather than reported instantly. Music has rests and tracks have
gaps, and a message that blinks on every one of them is noise. And it is not an
error: a stream that is open and quiet is a normal thing for a stream to be, so
it reads `silent`, not red.

The floor is now a singleton (`SpectrumScale`) rather than a constant in the
renderer, because two components with no parent/child relationship have to agree
on it. Restating it in both was how they would come to disagree.

### advanceWidth() was never following the font

`Frame.qml` already carried a comment about this — "advanceWidth() is a call,
not a property, and would not be tracked" — and the rest of the frontend did
not. `StreamPanel`'s six measured column widths and `ShellFramed`'s floor called
`advanceWidth()` with nothing else in the binding, so they captured no
dependency and never re-ran. `omarchy display text size` moved the type and left
the columns and the framed floor where they were, which is precisely the
requirement `project.md` states they meet.

The fix is the existing idiom, generalised, plus one correction to it: name
`metrics.font` rather than `Theme.fontBaseSize`. Both are bindings on the same
signal and their order is undefined, so reading the theme's key can measure
against the font that has not been updated yet; reading the metrics object's own
font reads what the change actually delivered. `Frame.qml` was changed to match.

### Secondary text was outside the contrast guard

`legibleOn()` was applied to three foreground levels and not to `muted` or
`foregroundDim`, on the reasoning that it covered "text-bearing tokens". Between
them those two carry the legend, the state report's qualifier, the media-name
column and every unselected stream name.

They could not simply be added, though: `legibleOn` replaces a failing colour
with pure white or black, and doing that to `muted` would take the theme's hue
out of exactly the places it is most visible. So a second tier — 3:1, the
large-text ratio, reached by *lifting* the colour toward white or black and
stopping at the first step that clears it.

Measured across all 22 shipped themes: 31 of 44 role/theme pairs were below 3:1
and are lifted, most by 5–25%, none replaced. `matte-black`'s muted was the worst
at 1.48:1 (`#333333` on black, effectively unreadable) and becomes `#666666` at
3.26:1. `retro-82` keeps its teal (`#2a6b78` → `#35727f`), `tokyo-night` its blue
(`#565f89` → `#5e678f`). Thirteen pairs were already fine and are untouched.

### One object was worse than six statements

The six column widths were first gathered into a single `columns` object, on the
reasoning that the dependency should be declared once rather than six times. It
loaded, and the log said `Cannot read property 'marker' of undefined` four times.

An object property is `undefined` until its own binding has run, and the widths
reading it are not guaranteed to run second. The bindings do re-run once
`columns` is assigned, so the window recovers and looks correct — which is
exactly the shape of thing a Release build would never have mentioned. Six
statements of the same guard, in the form the two contracting flags already
used, have no first pass to get wrong.

This is the third time this project has been caught by "it looks right, so it is
right". It was found in the first thirty seconds of running the thing.

### The rest

`processingReady` now names `audioServiceReady` as well. The pipeline rate is
polled and the poll stops when the service goes away, so the last reading
outlived the pipeline it measured and `[b]ypass` stayed advertised against
something that was no longer there.

The spectrum request timer reads `DbSpectrum.spectrumFpsCap` instead of a
hardcoded 60. `SpectrumCells.qml` is gone — built and referenced by nothing
since the pixel renderer replaced it, and recoverable from history.

**`canUseSysTray` was removed and put back.** The review called it dead: declared
in `Main.qml`, read by nothing. It is not dead. `main.cpp` injects it through
`setInitialProperties()`, which fails on a key the root object does not declare
— and fails *silently* in a Release build, for the reason recorded under
*Upstream baseline*. Removing it is a change to the patch inventory, not to a
QML file. It carries a comment saying so now.

### Verified

Release build and `qmllint` clean, with no new warnings of any kind; the
singleton resolves; the debug run logs nothing at all.

**The level scale, against signals of known level.** Pink noise was generated at
-8, -20, -35 and -50 dBFS RMS and played through the nested session
(`.sweep/level/`). The four captures are four different pictures, which is the
whole point — under the old code they would have been indistinguishable. -8
fills roughly four fifths of the window and tapers with the pink tilt; -20 sits
a little under that; -35 reaches about a third with the top octaves already at
the floor; -50 is a low ridge across the bottom with gaps above 10 kHz. The
measured prediction was three quarters at the peak for loud broadband material,
and that is what came back.

**`silent`, with a stream open.** Digital silence through `pw-play` produces the
report, centred, in the theme's foreground rather than its error colour, and it
does not blink. It also confirmed something the previous session could only
infer: this machine's persistent `nolo_client` stream contributes no signal, so
`silent` — not `no audio` — is the correct report here even with nothing else
playing. `no audio` still cannot be reached on this machine.

**The columns following the text size, before and after.** Run under a fake HOME
carrying nothing but the theme files and a `[font] base-size`, with the mixer
open at 640x320, and the size changed from 12 to 20 underneath the running
process (`.sweep/font/`). Fixed: the media-name column is dropped, the meter
keeps its gap from the reading, the marker keeps its space. Reverted to the
unguarded bindings and repeated: the volume meter runs straight into `100%`, the
marker is jammed against the name, and the media-name column is wrongly kept
because the decision was made against 12 px metrics. The bug was real, not
theoretical, and the desktop's own theme was never touched.

**The contrast guard**, measured across all 22 shipped themes as above.

Desktop left as found: the user's instance killed for the duration and restarted
on the new build, default sink never moved off the headset, nested session
stopped, nothing left running.

### Still open

**Live theme *switching* under load is still untested.** Text size was changed
under a running process and picked up; a whole-theme swap while audio is flowing
was not.

Everything from the previous entry stands: the frame line and legend are still
neutral greys, live theme switching under load is still untested, `spike/` is
still misnamed, and the repo is still on `master`.

---

## 2026-08-30 (late, third pass) — The theme was arriving, but not in the spectrum

**Commit:** `0fccd97`

The question was whether 42Hz really consumes the active Omarchy theme. It does
— backgrounds, foregrounds, borders, accent and control alphas all track the
live theme, and a theme switch is picked up without a restart. But the place a
theme is most visible was the place it was least present.

### The spectrum was running at a third of the palette's chroma

`spectrumLow`/`spectrumHigh` mapped to `dark_foreground` and
`bright_foreground`. Both are *foreground* levels, and foreground levels are
near-neutral by design. Measured across all 22 shipped themes:

| | mean saturation |
|---|---|
| spectrum floor | 0.18 |
| spectrum peak | 0.14 |
| accent | 0.43 |

So the largest surface in the application, and the one it rests in, was rendering
at roughly a third of the chroma the theme had available. Several themes put
their entire identity in an accent the spectrum never showed: `matte-black` is
black plus `#e68e0d` orange at 0.94 saturation, and 42Hz drew it in greys with
the orange confined to a four-character title. `lupine`, `flexoki-light` and
`ristretto` are the same story.

### Keeping the lightness and replacing only the colour

The fix is deliberately narrow. The foreground levels already encode the thing
that is genuinely hard: how far from the background each end of the ramp should
sit, *in the correct direction for a light theme as well as a dark one*. That
is worth keeping exactly. Only the colour is decided fresh.

Two wrong versions on the way, and both were caught by the same theme:

**Version one took the accent's hue outright** and made gruvbox teal. Gruvbox's
accent is a pale `#7daea3` at 0.16 saturation; its bright foreground is a warm
`#d4be98` at 0.59. The theme is *more* colourful than its own accent, and
deferring to the accent threw that away — the before/after was strictly worse.
So: a hue that already exists is kept, saturation only ever rises, and only a
level with no hue of its own borrows the accent's.

**Version two decided the hue per end**, and gruvbox came out ramping teal at the
floor to cream at the peak — its dark foreground sits at 0.11 saturation, below
the "has a hue" threshold, while its bright foreground is well above it. Two
hues in one ramp reads as two colours rather than as one signal getting louder.
So the peak chooses the hue, once, for the whole ramp.

Floor and peak carry different amounts of chroma — 0.55 and 0.85 of the
accent's. Most bars are quiet most of the time, and a floor at full chroma turns
the resting spectrum into a block of solid colour, which is loud rather than
punchy and leaves the peaks nothing to be.

### Checked against every theme, not the two that were in front of me

`spike/theme-preview.sh` renders 42Hz under any theme by handing it a fake
`HOME` containing only the two files the adapter reads. The desktop is never
switched. That is the same isolation spike-02 built by hand for a different
reason, and it makes light-theme and contrast verification repeatable — which
milestone 5 asks for and which had been sitting untouched behind "changing the
theme means changing the user's desktop".

Twelve themes rendered and all 22 measured. No theme ends with a peak below 7:1
against its background, a floor below 1.8:1, or a lightness span under 0.21, so
nothing was traded away for colour. The cases worth naming:

- **matte-black** goes from grey to orange, which is the whole point.
- **gruvbox** ends up where it started, warm and slightly richer, which is also
  the point — a rule that "improves" a theme that was already right is a bug.
- **vantablack** and **white** stay monochrome. Their accents are greys, and a
  grey accent lends nothing.
- **lupine** ramps blue to black, because its `bright_foreground` *is* black.
  Odd on paper, correct on screen: maximum contrast at the peak, hue below it.
- **solitude** is unchanged; its accent sits at 0.10 saturation and has nothing
  to lend.

### The harness lied in a third way

Captures blocked again, and the previous fix — `debug:vfr = false`, for static
content — was already in place. The cause this time was the user switching
workspaces: **a nested compositor on an unmapped workspace receives no frame
callbacks at all**, so screencopy never completes. There is no fix from inside
the nested session; it has to be visible on the parent's active workspace for
the whole of a sweep. The harness now says so instead of naming occlusion.

### Verified

Twelve themes rendered from the built binary and compared against their
`colors.toml`; all 22 measured for peak contrast, floor contrast and lightness
span. Desktop unchanged throughout — still `tokyo-night`, default sink
untouched, nothing left running.

### Still open

The frame line and legend are drawn in neutral foreground greys. That is a
restrained choice and it reads well, but if more of the theme should come
through in the chrome as well as the signal, that is the next place to put it.

Everything from the previous entry stands: the live-but-silent stream still
draws an empty window (explicitly deferred), light-theme *switching* is now
verifiable but live switching under load is not yet tested,
`SpectrumCells.qml` is still referenced by nothing, `spike/` is still misnamed,
and the repo is still on `master`.

---

## 2026-08-30 (late, second pass) — Fixing what the sweep found

**Commit:** `f635691`

The four defects from the sweep, all fixed and re-verified, plus a size floor
the window reports for itself. And a correction: the dispatch finding from this
morning was right after all, for a reason neither session had.

### The keymap is data now, and that is what makes the legend shrink

The legend defect and the keymap-drift problem were one thing seen twice. The
legend could not shorten itself because it was a string literal, and it could
not stay honest because the bindings lived somewhere else.

`Main.qml` now holds `windowBindings` and `mixerBindings`: `keys`, `label`,
`priority`, `advertised`, `action`. The key handler dispatches from the table
and the framed legend is rendered from it, so a binding cannot change without
the legend changing with it. `Frame` takes `legendItems` and drops the
lowest-priority entries until what remains fits the width it actually has.

Three decisions inside that are worth keeping:

- **`action` receives the key that matched.** Otherwise a direction pair
  becomes two rows that each advertise half a label, and `[-/+] density` has
  nowhere to live.
- **`advertised` gates the legend and nothing else.** `project.md` asks that
  only bindings backed by a live capability be *advertised*, and separately
  that every action stay reachable by key at every size. Gating the action too
  would have been easy and wrong: a key that silently stops working is worse
  than one that stops being mentioned.
- **An entry may carry no label.** That is how `Ctrl+W` lives beside `q` and
  `↑`/`↓` beside the mixer without either appearing twice.

Verified by driving the keys rather than reading the table: `-` and `+` move bar
density in the right directions, `b` puts `42Hz  ·  bypassed` in the title, and
plain `w` does not quit while `Ctrl+W` does.

### The mixer row, and a column that has to shrink twice

Columns are measured with `FontMetrics.advanceWidth` rather than guessed at in
ems, which incidentally fixed a latent clip: `processWidth` was 4.6 em against a
word needing nearer 4.9, so "bypassed" was cut off in any font at any size.

The media name is dropped rather than elided — at 480 px it had been rendering
as `S…`, which spends the width of a word to say nothing — and the meter goes
next, since it restates the percentage beside it. The flags size to their
content, so an inactive state costs no width at all.

Two attempts, and the first one was worse than what it replaced:

**Reserving the widest flags always** kept a muted stream from reflowing its own
row, and at 240 px left the name 31 px, which elided to a bare ellipsis. Names
are the whole point of the list. **But dropping the reservation** would have let
the state words disappear, and a state that stops being reported is the failure
the two-column split exists to prevent. So neither gives way: below the width
where the words fit beside a readable name they contract to `M` and `B`, and
both states stay on screen.

**Then the fix broke monotonicity.** Contracting the flags hands back enough
room to reintroduce a column, so widening the window from 280 to 340 px turned
the flags back into words and *took the volume meter away again*. A wider window
must never show less. Every decision about which columns exist is now made
against the space that would be left if the flags never contracted, and only the
name gets the benefit of the contraction.

### Too small is a state, and the floor belongs to the chrome

Below its floor the window says so, on the darkest background level, with the
size it needs and — when another mode would do better — `[1] for bare chrome`.
Every binding still works there, that one included.

**The floor is the loaded chrome's, not the window's.** Bare mode at 160x60 is a
working display and the sweep had confirmed it; a single window-level threshold
would have taken that away to fix a framed-mode problem. Bare asks for 127x48,
framed for 179x108, both derived from font metrics so they follow
`omarchy display text size`.

*On the black background:* `Theme.backgroundDarker` rather than a literal black.
On a dark Omarchy theme it is black to the eye; on a light one a black panel
would be the single surface in the application that ignores the theme. One line
to change if the intent was literal.

**The floor oscillated at first, and the cause is worth remembering.**
`minimumHeight` was computed from `Frame`'s own label items, and hiding the
shell because the window was too small set those labels invisible — QML
propagates visibility to children — which collapsed the insets, lowered the
floor, and made the window large enough again. The window latched between the
two and reported `needs 179 × 78` while sitting at 200x100, a pair that cannot
both be true. Measuring the same quantity from `FontMetrics` decouples it from
what is on screen. **A minimum size must not be derived from anything that
depends on visibility.**

### The dispatch finding was right, and so was the correction

This morning's entry recorded that this Hyprland's dispatchers are a Lua API and
`hyprctl dispatch` cannot reach them. The harness entry a few hours later
contradicted it, having driven six dispatchers through plain `hyprctl dispatch`.
Both are correct, and the difference is the config format:

`~/.config/hypr/` holds `hyprland.lua`, not `hyprland.conf`. **A Lua-configured
Hyprland parses `hyprctl dispatch ...` as a Lua expression**, so
`dispatch focuswindow class:aquamarine` returns `')' expected near 'class'`.
Every dispatcher fails that way; none is missing. The nested session is started
with `-c` on a generated `.conf`, runs the classic parser, and takes native
dispatchers.

So the harness uses plain dispatch for the nested session and `hyprctl eval`
with Lua for the one thing it asks of the parent. A Hyprland version number does
not tell you which form to use. Worth noting that Hyprland warns `.conf` support
is removed in 0.57, at which point the harness's config becomes Lua and every
dispatch in it becomes an `eval`.

### The core aborts when PipeWire is unreachable

Found while trying to force the `no audio service` report by pointing an
instance at a nonexistent socket. It does not report it — it dumps core.
`pw::Manager`'s constructor calls `util::fatal` at `pw_manager.cpp:339` after
"Context connection failed", from `CoreServices` in `main()`, before the QML
engine loads.

So `audioServiceReady` can only ever be false if PipeWire drops *after* startup;
at startup there is no window to report it in. `project.md` stages the window
first and PipeWire third precisely so that this is reportable, and the derived
core does the opposite. That is a milestone-5 item, recorded there.

### Two more ways the harness lied

Both cost real time and neither is about 42Hz.

**A static nested output starves screencopy.** With VFR on, a compositor showing
unchanging content stops producing frames, so `grim` waits forever for one. A
capture of a silent, still window hung; the identical capture of a live spectrum
returned in milliseconds. It looks exactly like a wedged application, and I went
looking for occlusion in the parent before finding it. `debug:vfr = false` fixes
it — the option moved out of `misc:`, where the old name is now an unknown key
and therefore raises the banner that started this whole class of problem. `grim`
also runs under a timeout now, so the harness fails with a reason.

**A new instance greets you with timed warning banners** and draws them into its
own output, where `grim` collects them across the top of the picture. They
expire in about fifteen seconds, so `start` now waits them out rather than
leaving every caller to distrust its first captures.

Also: `pkill -f streams.sh` matched the shell running it and killed the
session's own bash. Twice is a pattern; a literal that can match your own
command line is not a safe argument to `pkill`.

### Verified

Full 21-case sweep re-run against the fixed build with three live streams and no
QML errors. The four defects are gone: framed 160x60 reports its floor instead
of drawing nothing; the legend fits and the border closes at 200, 240 and
320 px; mixer rows are clean and named from 240 px up; column appearance is
monotonic across 240/280/340/400/480/640. Keys driven individually as above.

### Still open

**The state report's narrow form was not observed directly.** The detail line is
dropped rather than elided when it does not fit, and the identical predicate was
watched working in the too-small notice — the hint drops at 160 px and shows at
320. But `StateReport`'s own detail could not be photographed, because reaching
"no audio" needs zero application streams and this machine has a persistent one
(`alsa_playback.nolo_client`, from the Nolo app). Forcing the other long-detail
state, "no audio service", is what turned up the abort above.

**A live but silent stream still draws an empty window.** `spectrumFlowing`
tests `points.length > 0`, not whether any point is non-zero, so a stream that
exists and is silent produces a flat spectrum and no report at all. That is the
forbidden empty window from a fifth direction. Not fixed here: it is a change to
what the runtime states *are*, not to how they are laid out.

Light themes and live theme switching remain unlooked-at, and the harness does
not help — theme state is machine-global, so verifying it means changing the
theme on the user's actual desktop.

Unchanged: `ShellFramed.qml` still draws its legend bottom left where
`project.md` says bottom right; `SpectrumCells.qml` is still built and
referenced by nothing; `spike/` is still misnamed; the repo is still on
`master`.

---

## 2026-08-30 (late) — A nested compositor, and the responsive test finally run

**Commit:** `f3f37ec`

Three sessions had ended with "the responsive test is still not done". The last
one worked out why: it cannot be done on a desktop that is in use. This session
built the thing that makes it possible and then ran it, and the answer is that
milestone 2's headline behaviour is right and its chrome is not.

Evidence and measured thresholds are in
[`spike-04-responsive.md`](spike-04-responsive.md); this is what it cost and
what it means.

### The harness

`spike/nested-session.sh` starts a second Hyprland on its own Wayland socket
with a generated config, and `spike/geometry-sweep.sh` drives 21 captures
through it. Both are new. The nested session reads no user configuration and
writes none — everything it has lives in `$XDG_RUNTIME_DIR` and is deleted on
`stop`.

Headless would have been better and is not available: aquamarine here has no
backend-selection variable and Hyprland has no `--headless`, so the nested
session is a window on the user's screen whether or not that is wanted.

**Sizing the nested output does not work, and sizing the window does.** The
first design set the output size and let one tiled window fill it. The output
is a surface in the *parent* session, so the parent's layout decides how big it
is: the same `start 1280x720` produced 1226x688, 1788x688 and 1223x688 across
three runs, depending only on what else was on the parent's workspace. Floating
the window inside the nested session and using `resizewindowpixel exact` landed
on the requested pixel in all 21 cases. So the output is a ceiling, geometries
are clamped to it, and every capture is labelled with the size actually granted
rather than the size asked for — which is the only reason the drift above was
noticed rather than silently mislabelled.

**`hyprctl dispatch` works.** The afternoon entry recorded that this Hyprland's
dispatchers are a Lua API and `hyprctl dispatch` cannot reach them. Six
dispatchers were driven through plain `hyprctl dispatch` here against a nested
instance of the same binary. Whatever went wrong that afternoon, that is not
the explanation, and the `hl.dsp` Lua route is not required. The earlier finding
should not be relied on.

### Three things that quietly corrupt evidence

Each of these produced a plausible, wrong picture before it was caught, and all
three are properties of the *observation*, not of 42Hz — the same category as
the Release-build and logging traps already in `project.md`.

**A Hyprland config error is drawn into the output.** One invalid key
(`misc:vfr`, removed upstream) put an error banner across the top of every
full-height capture *and* reserved 26 px of the monitor, which had been silently
shrinking every tiled window since the session started — that unexplained
`reserved: [0, 26, 0, 0]` was this, not a layer surface.
`Hyprland --verify-config -c` is the check, and the harness now generates a
config that passes it.

**`grim` captures the nested pointer**, because the nested compositor draws its
own cursor into its own output. `cursor:inactive_timeout = 1` removes it.

**`dispatch fullscreen 0` enters fullscreen rather than leaving it**, so the
tiled and fullscreen captures came out holding each other's contents under each
other's labels. `fullscreenstate` names the state instead of toggling toward it.

Two smaller ones: `pkill -f streams.sh` matched the shell running it and killed
the session's own bash; and `nest status | head -1` exits the sweep under
`set -o pipefail`, because `head` closes the pipe and the harness takes SIGPIPE.

### The result: the density is right, the chrome is not

**Bar density follows window width correctly across the entire range**, which
is the responsive behaviour the milestone was mainly asking about. 1200x120 is
a dense wide spectrum and 240x600 a sparse narrow one, and neither is a
stretched copy of the other. Bare mode is correct at every size tested down to
160x60. Tiled and fullscreen are clean. Everything at 480 px and wider is
sound.

Below 480 px the framed chrome fails, in four separate places, and they share
one cause: **every piece of chrome is authored at one size.**

- The **legend** is a fixed string. It overruns the frame below ~460 px, is
  clipped mid-word, and takes the bottom border with it.
- The **state report**'s detail line overflows at 200 px and collides with the
  frame's own title at 160x60.
- **Mixer rows** lay out at fixed proportions, so the meter is drawn through the
  stream name below ~320 px — and at 1223 px the same proportions leave the four
  columns stranded at 2%, 33%, 64% and 87%.
- At 160x60 framed, **the spectrum is not drawn at all**: title row, legend row
  and insets consume the whole window.

That last one is `project.md`'s "an empty window is not an acceptable report of
anything", reached from a direction the requirement did not anticipate. The
window is not empty because a capability is missing. It is empty because the
chrome took the room and the signal yielded first. Whatever the fix is, the
priority has to invert: chrome drops, signal stays.

The legend defect is also the keymap-drift problem already on the list, seen
from the layout side. The legend cannot shorten itself because it is a literal
rather than a list of bindings with priorities. Publishing the binding table as
data that the handler and the legend both read fixes the drift and gives the
legend something to drop. That is now the highest-value single change in the
frontend, and it is the same change either way.

### Verified

21 captures across framed and bare, mixer open and closed, 160x60 to 1223x688,
plus tiled and fullscreen, with two live broadband streams. Thresholds bracketed
at 360/400/440/480 for the legend and 260/300/340/380 for the mixer row.
Empty-state behaviour captured separately at five widths with no audio playing.

### Still open

**Milestone 2 does not close.** Its verification is now done rather than
outstanding, which is the change; what it found is four defects, all in framed
chrome below 480 px, none fixed. The milestone closes when they are.

**Light themes and live theme switching are still unlooked-at**, and milestone 2
asks for continuous theme adaptation. The harness does not help here: theme
state is machine-global, so verifying it means changing the theme on the user's
actual desktop.

Unchanged: `ShellFramed.qml` draws its legend bottom left where `project.md`
says bottom right; `SpectrumCells.qml` is still built and referenced by
nothing; `spike/` is still misnamed, and now holds two more things that are not
spikes; the repo is still on `master`.

---

## 2026-08-30 (afternoon) — The blocklist key, global bypass, and how to see anything

**Commit:** `b837fc4`

Two of the three things the last session left at the top of the list. The third
— the responsive test milestone 2 actually asks for — is still not done, and
this session found out why it keeps not getting done.

### The crash was not a crash

Reported as a crash in the test window. `coredumpctl` had nothing from today,
and the process was still alive in state `T`, `WCHAN do_signal_stop`, its
process group backgrounded on its pts while bash held the foreground. `tostop`
was off, so SIGTTOU is ruled out; that leaves Ctrl+Z. `at-spi2-registryd`
logged "Disabling unresponsive app" for the same pid, which is the same fact
from outside. A suspended Qt client is indistinguishable from a hung one by
looking at it — **check the process state before reading anything into a frozen
window.**

The one real 42hz core on record is from the day before: SIGABRT, uncaught C++
exception out of `initQml` in the Release build. That is the
already-documented Release-build trap, not a new fault.

### The blocklist fix was smaller than planned, because the core already had it

The plan was a `setStreamProcessed(id, bool)` facade command added through
`reduce-deps.py`. That turned out to be the wrong shape: `Nodes::setData` on
`Roles::IsBlocklisted` already picks the blocklist key, already honours
`blocklistUsesMediaName`, and already writes the setting — and
`onOutputBlocklistChanged` already reconciles every row's `is_blocklisted` and
links or unlinks the stream. The whole policy is upstream's, reachable from QML
by writing one model role.

So the fix is a deletion. `toggleProcessing()` no longer composes a blocklist
entry, no longer writes `DbStreamOutputs.blocklist`, and no longer calls
`connectStreamOutput`/`disconnectStream`. It writes
`row.model.isBlocklisted = !row.isBlocklisted` and holds no policy at all. The
delegate gained `required property var model` to write back through, and
`required property bool isBlocklisted` to read the choice — the displayed
"bypassed" flag still reads `connected`, which is the graph's answer rather
than ours.

`required property int id` went with it — its only readers were the two removed
`PwManager` calls, and a required property nothing reads still obliges the model
to supply the role.

**Patch inventory unchanged.** Worth stating plainly, because the session
started out intending to add to it. The best available core change was no core
change.

### What was actually verified, and the accident that proved it

Two silent `pw-play` streams and a live Chromium. Pressing `p` on `pw-play`:

- the core cleared `target.node`/`target.object` on that node — so `setData`
  reached the core and the handler ran;
- `~/.config/42hz/db/42hzrc` flushed to `blocklist=pw-play` on exit: **one**
  entry, under the node name, which is the key the core matches. The old code's
  failure was writing a key the core might not match and then appending a
  second one on the next toggle;
- on a fresh start with that blocklist in place, *both* `pw-play` nodes were
  added and neither was given a target — they linked straight to the physical
  device;
- pressing `p` again moved one back onto `42hz_sink` and the `blocklist` key
  vanished from the settings file entirely.

The accident: a second `pw-play` started while the first was blocklisted was
refused capture at node-add time. Both are named `pw-play`, and the blocklist
key *is* the node name, so blocklisting one blocklists every stream with that
name. That is upstream's semantics, and it was the clearest evidence available
that the setting had really been written.

The stream that pinned its own target with `--target=42hz_sink` did **not**
move when bypassed, because the link change is metadata-only. It is still
refused capture next time it appears. Recorded in `project.md` as a limitation
of the mechanism rather than a bug in the control.

*Found and deliberately not fixed:* `pw_node_manager.cpp:237-243` clobbers its
own result — the `application_id` match is overwritten by the
`app_process_binary` line instead of being OR-ed with it. It changes nothing
for 42Hz: at node-add time both those fields are still empty, and 42Hz only
ever writes the node name. It is an upstream bug worth reporting and not worth
an entry in the patch inventory.

### Global bypass was already wired; it needed a key and a place to say so

`DbMain.bypass` drives a coalescer in `main.cpp` that calls `set_bypass()` on
both pipelines. `b` toggles it, verified by the core logging "Enabling global
bypass" and "Disabling global bypass".

Saying so is the part that needed a decision. Bypass looks *exactly* like
working processing: the spectrum is produced either way, so nothing in the
window would report it. Framed mode's top-left is "identity and state" by
`project.md`, so the title reads `42Hz · bypassed` while it is on, and the
frame's line breaks around the longer label without any help. Bare mode draws
nothing, which is that mode's whole commitment — there the toast on the
keypress is the report. Legend gained `[b]ypass`.

### Three things about seeing what the program is doing

Half this session went into observation rather than change, and all three are
worth never rediscovering:

**The core silences itself.** `main()` calls
`QLoggingCategory::setFilterRules("42hz.debug=false")` *after* Qt has read
`QT_LOGGING_RULES`, so neither the environment variable nor a Debug build can
turn it back on. `--debug` is the only switch. Nearly patched `main.cpp` for
this before finding the flag already exists.

**And then logs somewhere other than where you sent it.** A detached launch
redirecting stderr to a file produced an empty file and a full journal at the
same time — so reading only the file makes a working build look mute, the same
trap as the Release build by a different route. But a later detached run with
`--debug` produced *neither*, including no startup lines, and that was not
chased down. So: check `journalctl` first, never trust an empty redirect, and
when the log actually matters run the binary from a terminal rather than
detached. The re-verification after the `id` removal was done that way round —
by quitting and reading `blocklist=pw-play` out of the settings file, which
needs no logging at all and is the more direct evidence anyway.

**This Hyprland's dispatchers are a Lua API, and `hyprctl dispatch` cannot
reach them.** The previous session lost a quarter of an hour to this and
recorded that the documented forms do not work. They do not, but `hyprctl eval`
does, and the working form is:

```lua
local w
for _,x in ipairs(hl.get_windows()) do if x.class=="io.github.chizzler.42Hz" then w=x end end
hl.dispatch(hl.dsp.focus({ window = w }))
```

`focus` takes the window **object**. Passing `"address:0x…"` as a string
returns `ok` and does nothing, which is worse than an error. `hl.dsp` can be
enumerated with `error(table.concat(keys, ", "))`, because `eval` returns only
`ok` and error text is the only channel out.

**Do not probe these dispatchers by calling them with junk arguments.**
`hl.dsp.window.float({bogus=1})` and `.fullscreen({bogus=1})` do not reject the
table — they return `ok` and act on whatever window currently has focus, which
during this session was not always 42Hz.

### Driving a GUI on a desktop someone is using

The keystroke tests kept landing in the user's applications: focus-follows-mouse
returned focus to whatever was under the cursor between the focus call and
`wtype`, and 42Hz had joined an existing tab group, so it was frequently behind
another window at identical geometry. The fix is a wrapper that focuses 42Hz,
re-reads `activewindow`, and **refuses to send the key** unless 42Hz really has
it. It refused several times; each refusal is a keystroke that did not go into
somebody's file manager.

### Still open

**The responsive test is still not done, and now the reason is clear.** It
needs the window at a series of geometries, and every attempt to resize it was
undone by the tiling layout within a second. It cannot be done reliably on a
desktop that is in use. The options are a quiet screen, or a nested Hyprland
with its own `WAYLAND_DISPLAY` — the latter is worth building once, because it
makes the whole milestone-2 geometry sweep repeatable and independent of
whatever else is on screen. No other compositor is installed to nest.

Light themes still unlooked-at.

Unchanged from before: the keymap is a string literal in `ShellFramed`'s legend
while the bindings live in `Main`, and this session added `b` to both by hand,
which is exactly the drift that arrangement invites. Publishing the binding
table as data both read is still the fix. `ShellFramed.qml` still draws its
legend bottom left where `project.md` says bottom right. `SpectrumCells.qml` is
still built and referenced by nothing. `spike/` is still misnamed and the repo
is still on `master`.

---

## 2026-08-30 (night) — Cleanup pass over the milestone-2/3 frontend

**Commit:** `9d3f0df`

A quality review of the QML added over the day, on four angles at once: reuse,
simplification, efficiency, altitude. Findings that reached the same conclusion
from more than one direction were the ones worth acting on.

### The report was being rebuilt sixty times a second

`stateReport` was a `var` holding a JS object, and one of its branches read
`points.length`. `points` is replaced on every frame, so the binding re-ran at
60 Hz — and a `var` has no value equality, so it notified downstream every time
having produced an identical report, through two shells into three text
bindings.

Now four scalars — `audioServiceReady`, `processingReady`, `spectrumFlowing`,
`streamCount`. A `bool` suppresses its own change signal when the value has not
moved, so the chain goes quiet.

The wording moved with it. The window was authoring user-facing copy
("PipeWire is not reachable") and shipping it through an untyped dict with
`?? ""` guards at the far end; `StateReport` was a two-line text box. It now
takes capability booleans and owns the mapping to title, detail and severity —
which is the whole job of a component called StateReport. The empty mixer uses
it too, instead of its own hand-styled centred label.

### Asking for frames that cannot exist

The 60 Hz `requestSpectrumData()` timer ran unconditionally: sixty round trips
per second into the core while nothing was playing, each returning an empty
list that still churned every binding behind it. It is now gated on the state
the same session had just added the means to detect, and clears the last frame
when it stops.

### One line weight, one gutter

`Theme` gained `lineThickness`, derived from the type scale. `Frame` and the
mixer divider were computing the identical expression independently, which is
two definitions of 42Hz's single line weight and a frame that could thicken
while a divider did not. `Surface` similarly stated its gutter three times and
then subtracted it back off in a fourth place; it is one `readonly property`
now.

The theme's `[controls]` alphas — read since the theme adapter landed, and
noted then as "the mixer in milestone 3 needs them" — were still unused, with
the mixer inventing 0.12 and 0.2 instead. The divider and the meter track now
read `controlBorderAlpha` and `controlFillAlpha`, so `shell.toml`'s control
section is finally live.

*Rejected on the way:* expressing the remaining literals as arithmetic on those
tokens (`controlFillAlpha + 0.5`). An arbitrary offset applied to a themeable
value is less honest than the plain number it replaced — it looks derived and
is not. The dim row name is `foregroundDim`, which actually means that.

### ShellBare was a wrapper around nothing

It declared four properties, forwarded each verbatim to `Surface`, re-exported
one alias, and added nothing. Bare mode *is* the surface, so the loader points
at `Surface.qml` and the file is gone — one fewer copy of the property list to
keep in sync, and one fewer hop in the alias chain.

### Not fixed, and the most important thing found

**The blocklist key is chosen in the wrong place, and chosen too narrowly.**
`toggleProcessing()` pushes `row.name`, but the core matches a blocklist entry
against `application_id` *or* `app_process_binary` *or* `name`
(`pw_node_manager.cpp:234-243`), plus `name:media_name` when
`blocklistUsesMediaName()`. So a stream blocklisted under one key reads
"bypassed" in the mixer, and toggling it appends a second entry under a
different key rather than clearing the first.

The shallow fix is to widen the match in QML, which would put a second copy of
the core's policy in the frontend. The right fix is a facade command —
`setStreamProcessed(id, bool)` on the core, added through `reduce-deps.py` so
it stays in the patch inventory — with the panel holding no policy at all. That
is a change to the derived core and wants its own session.

Also left alone: the keymap is a string literal in `ShellFramed`'s legend while
the bindings live in `Main`, so a key change can leave the legend lying; and
`project.md`'s "only bindings backed by a live capability are advertised" is
unimplementable there, because the shell cannot see capability state. The fix
is to publish the binding table as data that both the handler and the legend
read. Noted, not done.

`SpectrumCells.qml` is still built and still referenced by nothing. It was kept
deliberately when the harness was dismantled, so it stays until it is wanted or
declared dead.

### Verified

Debug build, screenshots: framed and bare both load; the mixer opens in both;
divider, meter track and selected row render on the new tokens; the empty
mixer reports through `StateReport`; a live stream renders its row unchanged.

---

## 2026-08-30 (evening) — The application mixer

**Commit:** `609bac7`

Milestone 3's core: `s` reveals a list of live playback streams with volume,
mute, and processing inclusion, driven entirely from the keyboard.

Both chrome modes now share a single `Surface.qml` holding spectrum, state
report and mixer. Keeping the composition in one place means a change to how
the mixer shares space with the spectrum cannot land in one mode and not the
other; the shells are down to a border and a legend.

### Decision: processing inclusion is two operations, not one

`PwManager.connectStreamOutput()` / `disconnectStream()` look like the whole
control and are not. Disconnect only clears the stream's `target.node` and
`target.object` metadata, and `pw_manager.cpp:395` re-links every output stream
it sees unless the node is blocklisted. So a bare disconnect is undone the
moment the stream is noticed again.

Worse, it can be a no-op from the start: a client that pins its own target —
`pw-play --target=…` does — is unaffected by a metadata change, so the first
attempt moved nothing at all and looked exactly like a dead keybinding.

`p` now writes `DbStreamOutputs.blocklist` *and* changes the link. The
blocklist makes the choice durable, the link change makes it happen now.
Verified from outside the application: the test stream moved from
`42hz_sink` to sink `59`, the physical device, and came back on the second
press.

### Two states, two columns

`muted` and `bypassed` were sharing one right-aligned column, and a muted
bypassed stream showed only `muted` — the second state silently lost to the
first for want of width. They are independent facts and now have independent
columns. Same failure mode as an empty window meaning four things, at a smaller
scale.

### Testing a mixer without making noise

A 10-minute silent WAV through `pw-play`, one instance per stream. Real
clients, real sink-inputs, real links, and inaudible — and the volume and mute
writes are verifiable from `pactl` rather than by ear. Note that `pw-play`
reports volume cubically where the model and the UI are linear, so `85%` in
42Hz and `95%` in `pactl` are the same number.

Anything written during a test that lands in the settings database has to come
back out. `~/.config/42hz/db/42hzrc` was checked after the run: the blocklist
round-tripped to empty.

### The stale-instance trap, second variant

`build-debug/42hz -q` is safe only when an instance is already running. With
none, it starts one in the foreground and blocks — which cost a two-minute
timeout and killed the test it was setting up. Guard it: `pgrep -x 42hz &&
42hz -q`.

### Verified

On a running Debug build, keys driven with `wtype`, every claim checked against
`pactl` rather than the interface reporting on itself: the stream list; `↑`/`↓`
selection across two concurrent streams; `←`/`→` moving volume 100% → 85%; `m`
muting and unmuting; `p` moving the stream out of the processing graph and back;
`s` and `Escape` showing and hiding without touching the graph; the empty state
when the last stream ends.

### Still open

`[EffectsPipelines] bypass` exists in the settings database — global bypass is
a setting already there, not new work, and it is in the first release scope.
That is the obvious next thing.

Not yet touched, and still the honest gap in milestone 2: the responsive test
the milestone actually asks for, across tiled, floating, narrow, wide and
fullscreen geometries, and light themes. The mixer has only been seen at one
window size.

`ShellFramed.qml` still draws its legend bottom left where `project.md` says
bottom right. `spike/` is still misnamed and the repo is still on `master`.

---

## 2026-08-30 (later) — Saying something when there is nothing to show

**Commit:** `5af3a57`

With no audio the window rendered nothing at all, which is indistinguishable
from a dead PipeWire, a stopped pipeline, or a crash. That is the failure
`project.md` has always asked to prevent, so this session made the causes
distinct and gave the frontend a keyboard.

### What the core will tell a frontend

Nothing here needed a core change; it needed knowing which of the existing
QML surfaces are honest. Probed on a running Debug build, once idle and once
with a stream routed through `42hz_sink`:

| | idle | stream present |
|---|---|---|
| `PwManager.runtimeVersion` | `"1.6.8"` | `"1.6.8"` |
| `StreamOutputEffects.getPipeLineRate()` | `0` | `48` |
| `ModelNodes.outputStreams` rows | `0` | `1` |
| spectrum points | `0` | `111` |

So: `runtimeVersion` is empty only without a server connection, the pipeline
rate is non-zero only while the pipeline runs, and the stream model counts
what the core is actually processing. Four states, four different sentences,
all centred in the space the signal would otherwise occupy.

`getOutputLevelLeft()` stays at `0.0` — level meters are off unless
`setUpdateLevelMeters(true)` is called — so signal presence is read from the
spectrum rather than from the meters.

**A model's row count reaches QML through an `Instantiator`, and an
`Instantiator` counts what it has built.** With no delegate it builds nothing
and reports `0` for ever. The first probe read `streams=0` with audio plainly
playing, and the wrong conclusion — that the model only lists streams routed
through our own sink — survived two rounds before an empty `QtObject {}`
delegate fixed it. It does list them; it was never asked to make any.

### The test stream is silence

Verifying "stream present" without making noise on someone's desk: a 60-second
silent WAV played with `pw-play --target=42hz_sink`. It is a real client, a
real sink-input, a real link through the processing graph, and inaudible. It
also happens to exercise the case worth getting right — a stream that is
playing and silent is *not* a fault, and the interface correctly says nothing.

`pw-cat` fed from `/dev/zero` was tried first and exits immediately; it wants a
file it can parse, not a stream of bytes.

### Keyboard

`f` cycles chrome, `1`/`2` select it directly, `-`/`+` (and `[`/`]`) change bar
density, `q` and `Ctrl+W` quit. `Escape` is bound to nothing on purpose: it is
reserved for dismissing transient controls, and must never fall through to
something that stops audio.

The framed legend advertised `[s]treams [e]q [b]ypass`, none of which was
bound to anything. It now reads `[f]rame [-/+] density [q]uit`. Advertising a
control that does not exist is the same class of dishonesty as an empty window
that means four different things.

### Verified

By screenshot on a running Debug build, keys driven with `wtype`: `no audio`
centred with its qualifier; the report clearing the moment the silent stream
appears; `f` flipping bare and framed; the new legend; `q` ending the process.

Worth recording for next time: **a newly mapped window takes focus, so `wtype`
reaches it without any dispatcher call.** This Hyprland build exposes dispatch
as a Lua API and none of the documented `hyprctl dispatch focuswindow` forms
work against it; a quarter of an hour went into that before noticing the app
was already focused.

### Still open

Unchanged: `ShellFramed.qml` still draws its legend bottom left where
`project.md` says bottom right. `spike/` is still misnamed and the repo is
still on `master` while the docs say `main`.

Milestone 2's stated work is now done. What it has not had is the *responsive*
test the milestone actually asks for — tiled, floating, narrow, wide and
fullscreen geometries, and light themes, which have still never been looked at.

---

## 2026-08-30 — Picking a layout by looking at it

**Commit:** `993e96a`

The last session ended with a question it could not answer on paper: the product
goal said "ultra minimal", the layout section said "responds to available
space", and nothing decided which one milestone 2 was building. This session
answered it by building three shells and switching between them on live audio.

### The harness

`Main.qml` became a variant switcher — 1/2/3 to pick a shell, space to cycle,
`[` and `]` to change bar width by eye. Three candidates: **bare** (spectrum
only, ever), **hover** (controls fade in on pointer, never on size), **framed**
(a drawn border with pinned labels).

Deciding this by argument was going nowhere. Deciding it by looking took an
afternoon.

### Decision: bare and framed, both permanent

Framed won on presentation and bare survives as the thing framed is measured
against, so both ship. Hover was cut: revealing controls on pointer proximity
answers a question nobody asked, and it fought the resting state rather than
serving it.

A fourth was tried and rejected the same day — **corners**, which dropped the
box entirely and kept only pinned labels wearing a rule as wide as their own
text. The argument was that the window and Hyprland's own border already state
the boundary, so drawing it again costs two line-heights of signal for nothing.
It read as unanchored. The box earns its keep.

The two goals were never in opposition, which is the other thing this settled.
"Ultra minimal" is about how much is drawn; "responds to available space" is
about what happens when the window changes size. Bar density is the first case
of the second: the spectrum resamples to however many bars fit, so a wider
window shows more signal rather than a stretched copy. That was already working
— `Spectrum.applyPointCount()` binds `DbSpectrum.nPoints` to `width /
barWidth` — so one of milestone 2's three remaining items was quietly done.

### Two frame bugs, both from labels straddling a line

The legend at the bottom of the frame was clipped by the window edge, and
sometimes appeared with the border line drawn straight through it.

**Clipped:** a label centred on its edge puts half its glyph box outside the
border. The frame relied on its parent leaving room; 6 px was not enough, and
the title got away with the identical geometry only because a text box has slack
above the cap height and none below the descender. The frame now pulls its
border in by half a label height, so a straddling label can never leave the
item's bounds at any font size.

**Line through the text:** the gaps in the border are computed from
`TextMetrics.width`, but nothing repainted the `Canvas` when those metrics
resolved. First paint could run with width `0`. Both metrics now request a
repaint on `onWidthChanged`.

Related, and the same root cause a third time: the content margin cleared only
the border stroke, but the label's upper half sits *inside* the border, so the
spectrum ran into the legend. Content now clears the whole label height.

Vertical borders went to a 16 px inset against 6 px top and bottom. The
asymmetry is deliberate — horizontal air is what makes a frame read as a frame,
vertical air just eats signal.

### Verified

By screenshot, on a running Debug build, against `osaka-jade`: title on the top
line and legend on the bottom line, both fully inside the window, both edges
broken around their label, spectrum clear of both.

### Still open

`project.md` now says actions are pinned bottom right; `ShellFramed.qml` still
draws the legend bottom left. The document records the intent, the code has not
caught up.

Next: capability and signal state reported in the centre of the window — with
no audio the window currently renders nothing at all, which is indistinguishable
from a crash — then keyboard navigation. `spike/` is still misnamed and the repo
is still on `master` while the docs say `main`.

---

## 2026-08-29 (evening) — Separating the design from its history

**Commits:** `cefe17b`, `ca12ff7`

No code. `project.md` had accumulated four sessions of narrative — verification
notes, decision rationale, per-milestone progress — and had stopped being
readable as a statement of the design. This session separated the two documents
properly and gave this one the name it should have had.

### Decision: this file is the dev diary, and there is only one of it

Renamed `docs/devlog.md` → `docs/dev-diary.md`. The rename is the whole point:
the file existed, was well maintained, and was not being reached for, because
"devlog" reads like build output rather than a document you consult. A second
chronological file was considered and rejected outright — two places to record
"what happened" is the ambiguity, not the fix.

The division is now stated from both sides, in both files:

| | |
|---|---|
| `project.md` | what is **true**: commitments, constraints, requirements. Present tense, no dates, no progress. |
| `docs/dev-diary.md` | what **happened**: dated, narrative, decisions with reasoning, verification, open threads. |
| `docs/spike-*.md` | the evidence a claim rests on. |

### What actually moved

Almost nothing, which was the surprise. Auditing `project.md`'s narrative
against this diary, nearly every piece of it was **already recorded here, in
more detail** — the `str_to_num` digit bug, the `QT_NO_DEBUG_OUTPUT` silence,
the theme-watcher swap, the `omarchy-audio-output-sink` gap, the QML module
finalization trap. `project.md` had been carrying summaries of diary entries and
presenting them as design.

So the operation was mostly deletion, not migration. `project.md` lost its
verification narrative, its status tracking, and its decision rationale, and
kept the rules those things produced. Two examples of the compression:

- *Was:* a paragraph on how identity reassignment was verified unfenced after a forced settings write. *Now:* "42Hz reads none of EasyEffects' settings and runs alongside it without collision, so development runs need no `XDG_CONFIG_HOME` fence."
- *Was:* the story of the `42hz_sink` enumeration bug and its control against stock EasyEffects. *Now:* "A node name may not begin with a digit", with the mechanism and the generalisation, under a heading for constraints on the base.

Milestone entries lost their "Done: … Remaining: …" tails entirely. Those were
the clearest case of the wrong document: a milestone definition is a commitment,
its completion state is a fact about last Tuesday.

### The two details that only existed in project.md

Both are carried across here rather than lost:

**The KConfig rename was 38 file paths, not one.** The 2026-08-28 entry lists
"KConfig database path" as one of sixteen identity surfaces, which undercounts
the work considerably. The `kcfgc`-generated settings classes each carry their
own `<kcfgfile name="...">`, and *those* are what decide where settings land —
reassigning the directory without them would have produced an application that
looked renamed and still wrote to upstream's files.

**Verifying "no write occurred" is meaningless unless a write is provoked
first.** This is the "took two attempts" the 2026-08-28 entry promised to
explain and then didn't. The first isolation check confirmed
`~/.config/easyeffects` was untouched after a run — which proved nothing,
because KConfig only persists on change, so an idle run writes nothing no matter
whose identity it is using. The check only became evidence once a settings write
was forced first. Generalises past KConfig: **a negative result from a system
that no-ops by default is not a negative result.**

### Still open

Unchanged by this session, and inherited: `spike/` is still misnamed — those two
files are the build system, not a spike — and the repo is still on `master`
while both documents say `main`. Light themes resolve correctly but have never
been looked at.

Next real work is milestone 2's remaining three: layout that responds to
geometry, keyboard navigation, and capability-specific empty states. The
spectrum's `nPoints` is a writable QML singleton property (`DbSpectrum`,
range 2-2048), so binding bar count to window width is a binding rather than
DSP work — `project.md`'s claim on that point checks out against the generated
header.

One thing to settle before writing layout code: the product goal was edited this
session to "ultra minimal UI allowing the user control on placement", dropping
the progressive-disclosure sentence, while the Minimal/Compact/Expanded tiers
further down still describe the richer reading. Milestone 2 is the work that has
to pick one.

---

## 2026-08-29 (afternoon) — The Omarchy theme adapter

**Commit:** `b9fea38`

First real milestone-2 code. `frontend/theme.hpp` / `theme.cpp` resolve the
active Omarchy theme into semantic tokens and keep them live; `Main.qml` no
longer contains a single hard-coded colour, and its `// Omarchy: theme accent`
comments have stopped being lies.

### What the sources actually are

Three files, in increasing precedence:

```
~/.local/state/omarchy/current/theme/colors.toml   foundational palette
~/.local/state/omarchy/current/theme/shell.toml    per-surface roles
~/.config/omarchy/shell.toml                       machine-level override
```

The third was nearly missed. It exists on this host, is where `omarchy display
text size` writes `[font] base-size`, and **survives theme switches** — so it
has to win over the theme's own file rather than being a same-rank source.

Two more corrections came out of reading Omarchy's own resolver
(`/usr/share/omarchy/shell/Commons/Color.qml`, read for reference only; nothing
was copied):

- **The font family is the fontconfig alias `monospace`**, not a concrete
  family. Omarchy manages the alias system-wide through `omarchy font set`;
  naming `JetBrainsMono Nerd Font` — as the placeholder did — pins the font and
  defeats the CLI.
- Themes may omit named keys, in which case the terminal palette (`color0`,
  `color4`, `color7`, `color8`) is the fallback. Implemented the same way.

### Decision: watch the parent directory

**`omarchy-theme-set` does `rm -rf current/theme` then `mv next-theme
current/theme`** (lines 292-293). A `QFileSystemWatcher` on `theme/` or on
`colors.toml` is therefore dropped by the swap and never recovers, even though
a file reappears at the same path a moment later. This is the classic watcher
failure and it would have looked like "live reload works, except when it
matters".

`~/.local/state/omarchy/current/` outlives the swap and is the only durable
signal. The finer-grained watches are kept as low-latency extras for in-place
edits and re-established after every load, and a 100 ms coalescer absorbs the
burst a single switch produces.

Worth noting Omarchy's shell doesn't have this problem because it doesn't have
this constraint: `Color.qml` sets `watchChanges: false` on both theme files and
is pushed new payloads over Quickshell IPC. 42Hz cannot receive that, so file
monitoring is not the fallback here — it is the only route. `project.md`
already said so; now it says why.

### Verified

All four paths, on a running binary:

- **Resolution.** Against `osaka-jade`: `bg=#111c18 fg=#c1c497 acc=#509475
  muted=#53685b sel=#32473b err=#ff5345 specLo=#81b8a8 specHi=#f7e8b2
  font=monospace@12 fill=0.04 sel%=0.18` — every one matching its source key.
- **Live user override.** `base-size` 12 → 17 in `~/.config/omarchy/shell.toml`
  reached the running app without a restart; restored to 12 the same way. (The
  user's file was backed up and restored; it is byte-identical to before.)
- **Live theme switch**, across the destructive swap: `catppuccin-latte` flipped
  `dark` true → false and re-resolved the whole palette (`bg #111c18 →
  #eff1f5`, `acc #509475 → #1e66f5`). Switched back to `osaka-jade`.
- **Fallback.** With `HOME` pointed at an empty directory: `ready=false`,
  built-in neutral palette, no crash. Those built-ins are Omarchy's own neutral
  defaults rather than a 42Hz invention, so an unthemed run still looks like it
  belongs on the desktop.

The fallback run found a real gap: with no `dark_foreground` or
`bright_foreground`, both ends of the spectrum ramp collapsed to the same
colour and amplitude became unreadable. Now derived from the background when
the two coincide, which is exactly the "contrast-safe fallback" `project.md`
asks for — it just took running the degraded case to notice.

A 440 Hz tone renders as expected: peak bin in `#f7e8b2`, neighbours in
`#81b8a8`, ramp interpolated by amplitude. Screenshot rather than inference.

### The afternoon's real lesson: a stale instance absorbs every launch

An hour went into a bug that did not exist. After the theme work the window
appeared **transparent**, with no spectrum and no "no signal" text — and a
probe binding that should have been impossible to break returned nothing. The
suspects were plausible and all wrong: a static `Q_INVOKABLE`, `Qt.tint`,
a compositor opacity rule (`active_opacity` was 1.0, and no window rule
matched).

The actual cause: **42Hz is single-instance.** A process from an earlier build
was still running, so every subsequent `build/42hz` became a secondary instance
that asked the old one to present its window and exited. Rebuild, run, observe
— observing the previous binary, indefinitely, with no error anywhere. The
giveaway was hardcoding `color: "#ff0000"` and getting a green window.

Two habits follow. **`build/42hz -q` before every run**, and never trust a
launch whose PID exits immediately. And the reason it stayed invisible for so
long is the same reason as this morning's: `QT_NO_DEBUG_OUTPUT` means a Release
build cannot report anything, so "nothing in the logs" carries no information
at all. Both findings are now in `project.md` under the upstream baseline,
because they will outlive this session.

Also cleared up: `Theme.withAlpha` works fine as a static `Q_INVOKABLE`
(`wa=function call=#80ffffff`). It was removed from the paint loop anyway — the
ramp is interpolated in JS now, since that loop runs 100 bars at 60 Hz and has
no business crossing into C++ per bar.

### Still open

The adapter exposes `[controls]` state alphas that nothing consumes yet; they
are there because the mixer in milestone 3 needs them, and reading them now was
free. Light themes are resolved correctly but have never been *looked* at — the
contrast guard has not been exercised against a theme that actually produces an
illegible pairing, only against ones that do not. `spike/` is still misnamed,
and the repo is still on `master` while the docs say `main`.

---

## 2026-08-29 — Where 42Hz's own source lives

**Commit:** `ec9d5dd`

Milestone 1 left the frontend as a 65-line QML string literal inside
`reduce-deps.py`. That was right for a placeholder and is wrong for anything
milestone 2 needs, so this session settled where 42Hz's own code lives and
proved the arrangement by building it.

### Decision: the repository is the build root

A tracked top-level `CMakeLists.txt` adds the patched core and then `frontend/`:

```cmake
add_subdirectory(upstream/easyeffects-8.2.8)   # derived core, disposable
add_subdirectory(frontend)                     # 42Hz's own, tracked
```

`upstream/` stays wholly regenerable, so the disposable-tree guarantee is
untouched — but 42Hz's source now sits outside it, tracked, and is compiled
from its real path rather than a copy. That last part is the whole point.

**Rejected: copying `frontend/` into the tree at patch time.** It works, and it
recreates the exact trap the disposable-tree rule exists to prevent, aimed at
your own code instead of upstream's. Compile errors, QML traces,
`compile_commands.json` and qmlls would all point at the copy under
`upstream/`; editing the copy is the natural motion and the next `fetch.sh`
eats it. A safeguard that misfires daily on the code you actually write is
worse than none.

**Rejected for now: splitting the core into a library** and giving 42Hz the
executable. That is the shape `project.md`'s architecture section describes, and
it makes the facade a link boundary instead of a directory convention. It also
means rewriting `src/CMakeLists.txt` — ~30 target references — and
re-verifying that rewrite on every upstream bump, against a file upstream
changes freely. Straight conflict with the small-patch-inventory obligation.
Revisit when the facade is under real pressure, around milestone 3-4.

### The finding that justifies prototyping

**The obvious way to do this builds cleanly and fails at runtime.**

The first attempt kept one QML module and contributed 42Hz's files to it from
outside, via `qt_target_qml_sources(easyeffects QML_FILES Main.qml)` in
`frontend/`. CMake configured. 207/207 targets built. The generated
`.qrc` pointed at the tracked file, and `Main.qml` was demonstrably embedded in
the binary. Then:

```
terminate called after throwing an instance of 'std::runtime_error'
  what():  Failed to load QML UI
```

The generated `qmldir` had no `Main` entry. **Qt finalizes a QML module at the
end of the directory scope that declared it**, so by the time `frontend/` was
processed the core's module was already written. The call added the resource
and could not amend the module. Nothing warned — not CMake, not the build, not
Qt at startup beyond the failure itself.

Fixed by giving the frontend its **own** module: `qt_add_qml_module(hz_frontend
STATIC URI hz.ui QML_FILES Main.qml)`, linked in as `hz_frontendplugin`. The
core keeps its upstream URI `ee.ui` and, after patching, registers C++ types
and ships no QML at all.

The split turns out to be better than the thing it replaced. `ee.ui` is the
derived core's type registry; `hz.ui` is 42Hz's interface. **Every `import
ee.ui` in 42Hz QML is a reach across the facade boundary, and is greppable as
such** — which is the first mechanical check `project.md`'s "UI code must not
depend directly on upstream" has ever had.

Two scope traps found on the way, both because CMake does not propagate
sideways: `frontend/` needs its own `set(CMAKE_AUTOMOC ON)` and its own
`qt_policy(SET QTP0001/QTP0004 NEW)`. Upstream sets both, in its own directory.

### What this did to the patch inventory

It shrank: 551 → 514 lines, and the frontend heredoc is gone. `reduce-deps.py`
now deletes 66 upstream QML files and writes none. Two edits replaced it —
dropping `QML_FILES` from the core's module, and pointing `main.cpp` at
`qrc:/qt/qml/hz/ui/Main.qml` / `loadFromModule("hz.ui", "Main")`.

That second one deserves a note: the literal in `main.cpp` gates
`window->show()`. Get it wrong and the process runs happily with a live audio
graph and no window, no error, no log line. It cost a confused minute here; it
would cost more later. Also dropped the now-dead
`set_source_files_properties(...Common.qml Validators.qml...)` block, which
named QML singletons this script deletes.

### Verified

Full cycle from scratch — `fetch.sh` re-extracting over the hand-edited tree,
which is exactly what it is for, then patch, then build from the repo root:

- **229/229 targets**, 13M binary, 123 shared libraries, the same five KF6
  (`ConfigCore`, `ConfigGui`, `CoreAddons`, `I18n`, `I18nQml`). Identical to the
  milestone-1 baseline, so the layout change cost nothing.
- No Kirigami, QtGraphs or QQC2-desktop-style linked. No stale `ee.ui` resource
  paths in the binary.
- `qmldir` declares `Main 1.0 Main.qml`.
- Runs: window maps under Hyprland with class `io.github.chizzler.42Hz`, title
  `42Hz`. Virtual nodes correct (`42hz_sink`, `42hz_source`, `hz_soe_*`,
  `hz_sie_*`), all reaped on `SIGTERM`.
- Spectrum delivery re-confirmed across the new module boundary: with a 440 Hz
  tone playing into `42hz_sink`, `Main.qml` receives 100 points per frame.

The binary is now `build/42hz` — `RUNTIME_OUTPUT_DIRECTORY` set at the root, so
the path no longer moves with the upstream version.

### A silent frontend, and why logs could not have caught it

Creating `frontend/Main.qml` I changed its import from `ee.ui` to `hz.ui`,
reasoning that the file now belongs to the frontend module. Wrong: `Main.qml`
*is* `hz.ui` and does not import itself, while `StreamOutputEffects` and every
other core type is registered in `ee.ui`. The correct import is unchanged from
upstream.

The application started, mapped its window, created its PipeWire nodes and
looked entirely healthy. `StreamOutputEffects` was `undefined`, the
`Connections` block bound to nothing, and a 60 Hz timer called a method on
undefined — a frontend with no signal at all.

**Nothing in the logs said so, and nothing could have.** Upstream includes KDE's
`KDECompilerSettings`, which defines `QT_NO_DEBUG_OUTPUT` for Release builds, so
`console.log` and QML's diagnostics are compiled out entirely. Every run this
session produced a **zero-byte** log, which was read as "clean" when it only
ever meant "muted". An earlier draft of this entry cited "zero QML warnings" as
evidence; that claim was worth nothing.

What worked was making the program state externally observable: the probe put
`typeof StreamOutputEffects` and the live point count into the window title and
read them back with `hyprctl clients -j`. `soe=undefined pts=0` before the fix,
`soe=object pts=100` after, with a tone playing.

Two things follow, and both outlast this bug. **A Release build cannot be
verified from its own logs** — either build Debug for diagnosis, or observe from
outside the process. And **a QML frontend fails silently by construction**:
undefined identifiers are a runtime warning, not a build error, so "it launched
and drew a window" is not evidence that anything is connected. Milestone 2 needs
a way to assert the spectrum is live that does not depend on someone looking at
it.

### Still open

The theme adapter is the next real work, and it is the honest starting point for
milestone 2: the placeholder's colours carry `// Omarchy: theme accent` comments
that are currently lies. `/usr/share/omarchy/shell/Commons/Color.qml` is the
reference implementation and is on this host.

Two pieces of tidying not done: `spike/` is no longer a spike directory — those
two files are the build system — and the repo is on `master` while `project.md`
and the README both say `main`. Free to fix before a first push, annoying after.

---

## 2026-08-28 — Identity reassignment, and closing milestone 1

**Commit:** `b43a017`

The rename spike 02 called for, then the milestone-1 checks that were still
open. Evidence in `docs/spike-03-identity.md`.

### The rename was larger than an application ID, and one constant wide

Sixteen distinct surfaces carried Easy Effects' identity: application ID,
executable name, KConfig database path, presets directory, single-instance lock
*and socket*, logging category, virtual sink and source names and descriptions,
DSP filter node prefix, node groups, test-tone node, internal media classes,
desktop entry, metainfo, icons, and the portal autostart token. All of them now
derive from constants at the top of `reduce-deps.py`. The patch inventory grew
from 5 files to 17, and from 162 lines to 513.

**Decision: the CMake target keeps its upstream name.** Only `OUTPUT_NAME`
changes, so the binary is `42hz` while the target stays `easyeffects`. Renaming
the target would have touched roughly thirty lines in `src/CMakeLists.txt` plus
`qt_add_qml_module`, for no effect visible outside the build directory. Identity
is what the system sees, not what CMake calls things internally.

**Decision: extend the copyright line, do not replace it.** The about box now
reads `© 2017-2026 Wellington Wallace (Easy Effects) · 42Hz frontend © 2026 42Hz
contributors`. Dropping the original notice from a GPL derivative would be a
licence violation, not merely impolite. For the same reason the plugin vendor
label `"Easy Effects"` in `tags_plugin_name.hpp` was deliberately left alone: it
labels DSP that really is upstream's work, and relabelling it "42Hz" would
misattribute someone else's code. Upstream's 65K metainfo — entirely Easy
Effects release notes — was replaced with a short stub rather than shipped under
the 42Hz application ID.

**Decision: the application ID is `io.github.chizzler.42Hz`.** `project.md`
suggested `io.omarchy.42hz`, but the README disclaims Omarchy affiliation and a
reverse-DNS ID should name a domain its author controls. Settled and verified
live on all four surfaces it reaches — binary, installed asset names, the
Wayland class Hyprland reports, and the PipeWire `application.id` on every node.

Its final component begins with a digit, which Flatpak application IDs and
D-Bus bus names both forbid. Neither binds 42Hz — no D-Bus name is registered
and the target is an Arch package — but a Flatpak would need a different ID.
Worth noting only because it is the *second* digit-leading-name hazard today,
after `42hz_sink`; the shape of this project's name keeps mattering.

### The finding that justifies running things

**Renaming the virtual sink to `42hz_sink` silently broke stream enumeration.**

`target.object` is how a client pins its output, and PipeWire documents the value
as "a name or serial number". The core decides which by trying a numeric parse
first — via `util::str_to_num`, which wraps `std::from_chars` and checks only
`ec`. But `from_chars` reports success on a **partial** parse. `"42hz_sink"`
therefore parsed as serial `42`, matched nothing, and the stream was dropped
from the mixer while staying perfectly audible.

`ffplay` does exactly this. It vanished from the model. `mpv` and `paplay`,
which set no target, were fine — so a casual test would have passed.

The control mattered: stock Easy Effects v8.2.8, same host, same `ffplay`,
targeting `easyeffects_sink`, accepted it. **We introduced this**, purely by
choosing a name that begins with a digit. `42hz_source` had the same defect on
the capture side.

Fixed by treating `target.object` as a serial only when it is entirely digits —
one replacement covering both blocks. **Deliberately not** fixed in `str_to_num`
itself: 18 call sites, several parsing Equalizer-APO values where a trailing
unit may rely on the lenient parse. Tightening the shared helper is the better
long-term fix and is worth reporting upstream, but not blind.

The lesson generalises past this bug. A rename is not a cosmetic operation when
the new name has a different *shape* from the old one — leading digits, length,
character class. Nothing in the coupling map predicted this; only execution did.

### Milestone 1, closed

Same build figures as spike 02 — 209/209 targets, 13M, 123 libraries, five KF6
— so identity cost no dependencies.

- **Config isolation, unfenced.** Settings land in `~/.config/42hz/db/42hzrc`;
  `~/.config/easyeffects` unchanged across a *forced* write. `XDG_CONFIG_HOME`
  fencing is no longer required, which was the whole point. This took two
  attempts; why, is recorded in the 2026-08-29 (evening) entry, which is where
  the explanation promised here finally landed.
- **Real application streams.** `mpv`, `ffplay` and `paplay` concurrently, all
  enumerated, none ignored, full chain confirmed to the physical device.
- **EQ LV2 URI validated both ways.** `para_equalizer_x32_lr` instantiates and
  links. Absent — forced with `bwrap --tmpfs` over `/usr/lib/lv2`, since the core
  only *appends* `LV2_PATH` and cannot be starved by environment alone — it
  reports `is not installed`, does not crash, and passes audio through. It also
  emits ~580 `port symbol not found` warnings, so the frontend must surface
  `packageInstalled` rather than expect anyone to read logs. A second LV2
  dependency surfaced: the spectrum wants `comp_delay_x2_stereo` for A/V sync and
  degrades gracefully without it.
- **Teardown with the virtual sink as default** — the case spike 02 explicitly
  refused to count as passing. Both `SIGTERM` and `SIGKILL`: nodes reaped,
  default fell back to the physical sink on its own, every stream migrated and
  kept playing. Restart over a stale lock and socket works.
- **Coexistence.** 42Hz and stock Easy Effects run simultaneously with disjoint
  node sets, and `42hz -q` quits only 42Hz. The socket rename was load-bearing:
  sharing `EasyEffectsServer` would have meant 42Hz's command line driving Easy
  Effects.

### Speaker tuning, and a loop worth knowing about

No Omarchy tuning exists on this host, so PipeWire's own `sink-eq6.conf`
filter-chain sink stood in, run as a client via `pipewire -c` — non-persistent,
no user config touched. Representative, since Omarchy's tuning is itself a
native filter-chain. 42Hz chains in front of it cleanly and the spectrum keeps
running.

**But** the stock example pins no target on its playback stream, so that stream
follows the default sink. Make a DSP virtual sink the default in that situation
and the graph closes a feedback loop through it. Stock Easy Effects forms the
identical loop, so this is inherited rather than ours — but it is a real failure
mode for any user whose tuning chain does not pin its output, and it argues that
42Hz should detect a cycle through its own sink instead of linking it.

Re-confirmed while there: `omarchy-audio-output-sink` still returns its own
argument, now with two filter layers it cannot walk instead of one.

### Authorship, and a history rewrite

**Decision: the application ID is settled as `io.github.chizzler.42Hz`**, after a
typo'd first pass. The `io.github.<handle>` form is a verifiable ownership claim
rather than decoration — AppStream uses it for uniqueness and Flathub enforces
that you control the corresponding repo — so it should name the account that
will actually host the project.

**Decision: commits are authored under a real name with a dedicated public
alias.** Real-name authorship is the dominant convention in the corner of FOSS
42Hz occupies: the kernel mandates it through the DCO, GPL and system-tooling
projects cluster near that norm, and EasyEffects itself is authored under a real
name and address. Using a handle for 42Hz's half would also sit oddly beside the
deliberate decision, made hours earlier, to *extend* rather than replace
upstream's copyright line. The alias keeps a private address out of an archive
that never forgets, without giving up attribution.

Note for whoever pushes first: **GitHub links commits to an account by email,
not by name.** The alias must be added and verified on the account, or these
commits appear unlinked — no avatar, no contribution graph — and correcting that
afterwards means another rewrite.

**The rewrite itself.** The private address was in all five existing commits.
Caught before any remote existed, which is the only point at which this is free;
after a push it means force-rewriting published history while forks and mirrors
keep the old values anyway.

The interesting cost was self-inflicted. This log records commit hashes, and
rewriting from the root changed all of them — orphaning four `**Commit:**`
references here *and* two commit subjects that name a hash. Both were
recoverable: `filter-branch` exposes a `map` function, so the subjects were
remapped inside the same pass, and the log itself took a follow-up commit,
which is the same backfill this project already does because a commit cannot
contain its own hash.

Worth keeping the convention — the hashes earn their place — but it now carries
a standing cost: **a history rewrite is never a single command in this repo.**

### Still open

Per-stream volume, mute and processing-inclusion *control* is milestone 3 —
enumeration is verified, acting on streams is not. Device churn was never
exercised; the headset stayed plugged in. 42Hz still credits only Wellington
Wallace in `KAboutData` and carries no AppStream `<developer>` element of its
own; both go with the attribution work in milestone 6.

---

## 2026-08-27 (afternoon) — Reproducible build, and first light

**Commit:** `b07e7b4`

Two threads: making this morning's build reproducible, and executing the derived
binary for the first time. Evidence in `docs/spike-02-first-run.md`.

### The build could not be re-run

`spike/reduce-deps.py` hard-coded a scratchpad path from the session that
produced it, and that directory no longer existed. This morning's verification
was a claim in a document rather than a repeatable fact. Fixed.

**Decision: patch-on-tarball, confirmed.** The vendoring question left open
yesterday is settled in favour of the option `.gitignore` already leaned
towards. Nothing about the reproducibility defect argued for vendoring — it was
an unpinned base and a hard-coded path, both fixable without importing 700 files
of someone else's source and inheriting a manual merge on every upstream release.

**Decision: the extracted tree is disposable.** `fetch.sh` deletes and
re-extracts `upstream/` on every run, build directory included, with no prompt.
Alternatives considered: refusing when a tree exists, and clobbering only an
unpatched one.

The reasoning is worth keeping, because it converts an aspiration into a
mechanism. The small-patch-inventory obligation in `project.md` was until now a
promise to be disciplined. Under a disposable tree it is enforced by
construction — an edit not in `reduce-deps.py` does not survive the next fetch,
so it cannot quietly become load-bearing, and the patch script cannot drift out
of step with what is actually built. Discarding the build directory first looked
like the cost of the policy; it is better read as part of it, since a build
reflecting a source state that no longer exists is the same class of
inconsistency.

**Two-tier checksum.** The base is pinned by commit, by archive checksum, *and*
by a digest of the extracted 709-file tree. GitHub generates tag archives on
demand and has changed their compression before, invalidating pinned checksums
ecosystem-wide without a line of source changing. The tree digest distinguishes
"same source, recompressed" (warn, continue) from "source changed" (refuse).
Pinning only the archive pins the artifact, not the content.

**Guards on the patch script.** It now refuses a path that is not an EasyEffects
tree, and refuses an already-patched one. The second matters more than expected:
the script is destructive and in-place, and its CMake edits are regex line
deletions, so a second run would not error — it would no-op those deletions and
then fail mid-splice, leaving a half-patched tree that looks fine.

Verified end to end from a clean checkout: 209/209 targets, 13M binary, 123
shared libraries, KF6 down to ConfigCore, ConfigGui, CoreAddons, I18n, I18nQml —
identical to this morning's figures, now reproducible rather than merely
recorded. The re-fetch path was exercised against an 89M patched-and-built tree.

### First light

**The binary ran, and the spectrum is live.** A 440 Hz sine played into
`easyeffects_sink` rendered as a single narrow peak in the placeholder
`Main.qml` canvas. That closes the derivation's central assumption: PipeWire →
FFTW → spline → `newSpectrumData` → plain QtQuick works with no Kirigami, no
QtGraphs, no KDE style. Spike 01 inferred this from source; it is now
demonstrated.

**The run was fenced, and needed to be.** `XDG_CONFIG_HOME` was redirected to
scratch. Unisolated, the first launch would have written to the real
`~/.config/easyeffects/db/`, over a populated `equalizerrc`. The derived binary
still shares *every* identifier with upstream — app id, window title, config
path, virtual node names, filter node prefixes. Two consequences: the isolation
fence is mandatory on every development run until identity is reassigned, and
the rename is larger than the application ID `project.md` described.

**Startup does not hijack routing**, and teardown is clean under both `SIGTERM`
and `SIGKILL` — nodes reaped, default sink untouched. But the virtual sink was
never made default in this run, so the case the requirement exists for — killing
the process while the default route points at it — is still untested. Recorded
as such rather than counted as passing.

### The finding that changes something

Omarchy resolves a DSP sink to the physical sink whose volume it really
controls, so volume keys act on the endpoint rather than on the level going into
processing. `omarchy-audio-output-sink` does this by walking
`pactl list sink-inputs`.

It cannot see the EasyEffects output leg. The node feeding the physical device is
`ee_soe_output_level` — a PipeWire filter node with no `media.class`, linked port
to port, never enumerated as a sink-input. Asked directly with the graph live,
the resolver hands back its own argument.

This overturns an assumption raised in review: that 42Hz could satisfy the
resolver's generic branch by naming its downstream stream after its virtual sink.
That branch is unreachable regardless of naming, because there is no sink-input
to name. **Node naming was never the lever.** The honest options are to present a
real sink-input (a core modification), to extend the resolver to walk PipeWire
links (an upstream Omarchy change that also fixes EasyEffects and tuning chains),
or to accept a fallback producing exactly the failure the resolver exists to
prevent. The second is preferred and is not 42Hz's code to change.

Not a 42Hz regression — the same gap applies to stock EasyEffects on Omarchy
today. Inheriting a bug is one of the quieter costs of derivation.

### Corrections folded into project.md

Omarchy's speaker tuning is a native PipeWire filter-chain fitted by measurement
from an EasyEffects profile, not an EasyEffects preset. `conflicts=easyeffects`
costs the tuning nothing; the coexistence question was mis-stated.

`project.md` now also distinguishes commitments from sketches. Much of it was
written before anything ran, and the command surface and layout tiers in
particular were being read with more authority than they had earned.

### Milestone 1 status

Done: base pinned, licensing preserved, coupling mapped, reproducible build,
executable owning its derived core, live spectrum, PipeWire endpoints.

Open: application-stream enumeration against real clients (only a synthetic
`paplay` stream so far), the EQ LV2 URI and its failure path (never
instantiated), routing with the virtual sink as default, and behaviour chained
behind a speaker-tuning filter-chain (none present on this host).

---

## 2026-08-27 — Reduced-dependency build verified

**Commit:** `4f04024`

The reduced tree configures, compiles, and links against Qt 6.11.2 / KF6 6.29.0,
producing a 13M binary. Linked KF6 libraries drop from 10 to 5 — `Archive`,
`BreezeIcons`, `ColorScheme`, `GuiAddons`, and `IconThemes` are gone — with no
Kirigami, QtGraphs, or QQC2-desktop-style objects remaining. Total shared
libraries fall 129 → 123.

Both risks pre-registered in spike 01 resolved favourably:

- `KF6::I18nQml` does **not** transitively pull in KDE UI components.
- `Qt::Graphs` was QML-only; removing it broke no C++ compilation.

**The informative failure.** The first build failed on exactly one target,
`main.cpp`, with `fatal error: kicontheme.h: No such file or directory`. 208 of
209 targets had already compiled, and the sole casualty was the entry point 42Hz
replaces regardless. No core file needed modification — a stronger result than a
clean first build, because it exercised the core/frontend boundary and the
boundary held.

Cause was a defect in `spike/reduce-deps.py`: `main.cpp` includes KDE headers in
both the CamelCase forwarding form (`<KIconTheme>`) and the lowercase real form
(`<kicontheme.h>`), and the patch matched only the former. Fixed. **Lesson for
future audits of KDE-adjacent code: grep both casings.**

**Not done:** the binary has never been executed. Running it starts a PipeWire
graph that creates virtual nodes and may alter default routing, so it needs a
deliberate first run rather than a build-check afterthought.

**Open:** vendoring strategy still undecided (see 2026-08-26). `.gitignore`
currently assumes patch-on-tarball.

---

## 2026-08-26 — Feasibility spike, and the repository

**Commits:** `3b90e6c`

**Decision: QML frontend, not a TUI.** The question raised was whether a TUI
could carry a spectrum analyser, on the strength of BTOP's feel. It can —
`cava` does exactly this, braille cells give 2×4 addressable dots, and `foot`
additionally supports sixel. Resolution and framerate were never the obstacle.

Rejected anyway, because a TUI would mean writing a frontend against a C++ core
reachable only over IPC, contradicting three of this project's own commitments:
backend stability over reinvention, single-process design, and a small patch
inventory. Two findings settled it in the other direction — upstream EasyEffects
8.x is *already* Qt6/QML, and Omarchy 4's shell is Quickshell, also QML/Qt6. QML
is simultaneously the upstream toolkit and the desktop's own.

What survives from the TUI idea is BTOP's *economy* — density, progressive
disclosure, no chrome — which `project.md` already framed correctly as something
to emulate rather than imitate. Worth noting the door isn't shut: the core
delivers a plain `QList<QPointF>`, which would feed a terminal renderer just as
easily.

**Coupling mapped.** Full evidence in `docs/spike-01-frontend-coupling.md`.
Headline: KDE coupling confined to 3 files; 62 of 66 QML files import Kirigami,
so no frontend is inheritable; the spectrum facade
(`requestSpectrumData` / `newSpectrumData`, resampled to a configurable
`nPoints`) already exists upstream.

**Decision: GPL-3.0-or-later from commit one.** 42Hz is a derivative of
GPL-3.0-or-later EasyEffects, so that is the destination regardless. Licensing at
commit one is free; relicensing later requires agreement from every contributor
by that point. The contributor set is currently one person — the cheapest it will
ever be.

**Decision: repo-local git identity**, not `--global`, so a project session does
not silently set authorship for every other repository on the machine.

**Open: vendoring strategy.** Does the repo vendor EasyEffects source, or stay
patch-on-tarball? Vendoring gives a buildable checkout at the cost of a
diff-noisy import and manual upstream merges. Patch-on-tarball keeps the repo
small and makes the modifications legible as *the whole repo* — closer to the
"small patch inventory" goal — but needs a fetch step and patches rot as upstream
moves. Deferred; it does not block current work, though `.gitignore` currently
leans patch-on-tarball.
