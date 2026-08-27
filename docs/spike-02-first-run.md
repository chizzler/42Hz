# Spike 02 — first execution of the derived binary

**Date:** 2026-08-27
**Milestone:** 1 (repository and feasibility spike)
**Status:** complete
**Binary:** `upstream/easyeffects-8.2.8/build/src/easyeffects`, built from the
pinned base via `spike/fetch.sh` + `spike/reduce-deps.py`

Spike 01 verified the reduced tree by build only. This spike executes it.

## Method

Running the derived core starts a PipeWire graph, creates virtual nodes, and can
alter default routing, so the run was fenced:

- **Config isolated.** `XDG_{CONFIG,DATA,STATE,CACHE}_HOME` redirected to a
  scratch directory. The binary still identifies as `easyeffects` and would
  otherwise have read and written the user's real `~/.config/easyeffects/db/`,
  including a populated `equalizerrc`.
- **Rollback captured.** Default sink and sink list recorded before launch.
- **Bounded.** Launched under `timeout`, never left running unattended.
- **Signal source.** A generated 25 s 440 Hz stereo sine, played into
  `easyeffects_sink` with `PULSE_SINK`.

Host state at launch: default sink a Razer USB headset, no speaker-tuning
filter-chain active, upstream EasyEffects installed but **not running**.

## Findings

### 1. It runs, and the frontend renders

A Wayland toplevel appeared and Hyprland tiled it. With the tone playing, the
placeholder `Main.qml` canvas drew a single narrow peak — the expected signature
of a pure 440 Hz sine, with two adjacent bins from spline interpolation.

This is the first end-to-end confirmation of the whole path:

```
PipeWire capture -> Spectrum (FFTW, 8192 bands) -> GSL Steffen spline
  -> resample to nPoints -> newSpectrumData(QList<QPointF>) -> QML Canvas
```

The spectrum seam identified in spike 01 works from a plain-QtQuick frontend
with no Kirigami, no QtGraphs, and no KDE style. **The core assumption of the
derivation is now demonstrated, not merely inferred.**

### 2. Routing is not hijacked on startup

Virtual nodes `easyeffects_sink` (`Audio/Sink`) and `easyeffects_source` are
created, but the default sink was unchanged throughout. Streams are not
force-moved on launch.

### 3. Teardown is clean under both signals

| | default sink | virtual nodes | leftover process |
|---|---|---|---|
| `SIGTERM` (graceful) | unchanged | removed | none |
| `SIGKILL` (forced) | unchanged | removed | none |

PipeWire reaps the nodes on process death, so the "never leave the default route
pointing at a dead 42Hz node" requirement is not endangered by abrupt exit *in
this configuration* — where the virtual sink was never made default. The
dangerous case, killing the process while its sink **is** the default, remains
untested and is the one that matters.

### 4. The output leg is a filter node, not a sink-input

Observed graph with the tone playing:

```
paplay -> easyeffects_sink -> ee_soe_spectrum -> ee_soe_output_level -> alsa_output.<physical>
```

The node feeding the physical device is `ee_soe_output_level`. Its properties:

| node.name | media.class |
|---|---|
| `easyeffects_sink` | `Audio/Sink` |
| `ee_soe_spectrum` | *(none)* |
| `ee_soe_output_level` | *(none)* |

It carries **no `media.class`**. It is a raw PipeWire filter node linked port to
port, not a PulseAudio-style playback stream. Throughout the run,
`pactl list sink-inputs` reported exactly one entry — `paplay` — and never the
EasyEffects output leg.

### 5. Consequence: Omarchy's DSP-sink resolution does not resolve EasyEffects

`/usr/bin/omarchy-audio-output-sink` exists to answer "this DSP sink is selected,
but which physical sink does its volume really belong to?" It walks
`pactl list sink-inputs` looking for either

- a sink-input whose `node.name` is prefixed by the virtual sink's name, or
- a sink-input with `application.name = "EasyEffects"` when the sink is
  `easyeffects_sink`.

Measured, with the graph live:

```
$ omarchy-audio-output-sink easyeffects_sink
easyeffects_sink
```

It returns its own argument — the documented "idle and unlinked" fallback. Both
branches fail for the same reason: **there is no sink-input to match**, because
EasyEffects 8.x connects downstream through PipeWire filter links that the
PulseAudio compatibility API does not enumerate as sink-inputs.

This corrects an earlier assumption recorded in review, which held that 42Hz
could satisfy the generic prefix branch simply by naming its downstream stream
after its virtual sink. That branch is unreachable regardless of naming. Node
naming is not the lever.

Options for 42Hz, none free:

1. **Present a real sink-input for the output leg.** Would satisfy the generic
   branch, but means changing how the derived core connects downstream — a core
   modification, against the small-patch-inventory goal.
2. **Extend the resolver to walk PipeWire links** (`pw-link` / `pw-dump`) rather
   than `pactl sink-inputs`. Fixes EasyEffects and speaker-tuning chains as well
   as 42Hz, and is an upstream Omarchy contribution rather than a 42Hz change.
3. **Accept the fallback.** Volume then applies to the DSP sink itself, which is
   precisely the failure the resolver was written to prevent: the slider moves,
   the speakers do not, and a limiter in the chain changes tone as well.

Option 2 is the only one that is both correct and cheap for 42Hz, and it is not
a 42Hz change. This should be settled before the packaging decision, not after.

### 6. Identity collision with installed EasyEffects is total

The derived binary currently shares **every** identifier with upstream:

| | value |
|---|---|
| Wayland app id | `com.github.wwmm.easyeffects` |
| Window title | `Easy Effects` |
| Config path | `~/.config/easyeffects/db/` |
| Virtual nodes | `easyeffects_sink`, `easyeffects_source` |
| Filter nodes | `ee_soe_*`, `ee_sie_*` |

Unisolated, the first run would have written to the user's real EasyEffects
settings. This is expected — renaming is 42Hz's work, not upstream's — but it
means **every** development run needs the isolation fence until identity is
reassigned, and it enlarges the rename beyond the application ID in `project.md`
to cover config paths and PipeWire node names.

## Amendments recommended to `project.md`

1. Record that spectrum delivery to a non-Kirigami QML frontend is verified.
2. Replace the open question about Omarchy recognising a distinct 42Hz identity
   with finding 5: the resolver cannot see filter-node output legs at all, so
   this is a resolver limitation, not an identity-negotiation problem.
3. Broaden the identity rename to config paths and PipeWire node names.
4. Note that "never leave the default route pointing at a dead node" is still
   untested in the case that actually risks it.

## Not done

- Never run with `easyeffects_sink` as the default sink, so stream-moving,
  routing reconciliation, and kill-while-default are all unobserved.
- The LV2 equalizer was never instantiated; the EQ capability path in milestone 1
  remains unvalidated.
- Application-stream enumeration was exercised with one synthetic `paplay`
  stream, not with real game, browser, or voice-chat clients.
- No speaker-tuning filter-chain was present on the host, so 42Hz has never been
  observed chained behind one.
