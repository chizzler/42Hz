# Spike 02 — first execution of the derived binary

**2026-08-27.** Milestone 1. Spike 01 verified the reduced tree by build only;
this spike ran it.

## Method

Running the derived core starts a PipeWire graph, creates virtual nodes and can
alter default routing, so the run was fenced: `XDG_{CONFIG,DATA,STATE,CACHE}_HOME`
redirected to scratch (the binary still identified as `easyeffects` and would
otherwise have written the user's populated `equalizerrc`), default sink and sink
list recorded first, launched under `timeout`, and fed a generated 25 s 440 Hz
stereo sine through `PULSE_SINK`. Host: Razer USB headset as default sink, no
speaker-tuning filter chain, upstream EasyEffects installed but not running.

## Findings

**1. It runs, and the spectrum is live.** The placeholder `Main.qml` canvas drew
a single narrow peak with two adjacent bins from spline interpolation. That
demonstrates the whole path — PipeWire capture → Spectrum (FFTW, 8192 bands) →
GSL Steffen spline → resample to `nPoints` → `newSpectrumData(QList<QPointF>)` →
QML Canvas — from a plain-QtQuick frontend with no Kirigami, no QtGraphs and no
KDE style.

**2. Routing is not hijacked on startup.** Virtual nodes are created; the default
sink was unchanged throughout, and streams are not force-moved on launch.

**3. Teardown is clean under both `SIGTERM` and `SIGKILL`** — nodes reaped,
default sink untouched, no leftover process. But the virtual sink was never made
default in this run, so the case the requirement exists for is untested.

**4. The output leg is a filter node, not a sink-input.** With the tone playing:

```
paplay → easyeffects_sink → ee_soe_spectrum → ee_soe_output_level → alsa_output.<physical>
```

`easyeffects_sink` carries `media.class = Audio/Sink`; `ee_soe_spectrum` and
`ee_soe_output_level` carry **none**. The node feeding the device is a raw
PipeWire filter node linked port to port, and throughout the run
`pactl list sink-inputs` reported exactly one entry — `paplay` — and never the
output leg.

**5. Consequence: Omarchy's DSP-sink resolution cannot resolve EasyEffects.**
`/usr/bin/omarchy-audio-output-sink` walks `pactl list sink-inputs` looking for a
sink-input whose `node.name` is prefixed by the virtual sink's name, or one with
`application.name = "EasyEffects"`. Measured with the graph live:

```
$ omarchy-audio-output-sink easyeffects_sink
easyeffects_sink
```

It returns its own argument — the "idle and unlinked" fallback. Both branches
fail because **there is no sink-input to match**. This corrects an assumption
raised in review, that 42Hz could satisfy the generic prefix branch by naming its
downstream stream after its virtual sink: that branch is unreachable regardless.
Node naming is not the lever. The three options, none free — present a real
sink-input (a core modification), extend the resolver to walk PipeWire links (an
Omarchy contribution that also fixes EasyEffects and tuning chains), or accept a
fallback that produces exactly the failure the resolver exists to prevent.

**6. Identity collision with installed EasyEffects is total.** The derived binary
shared the Wayland app id, window title, config path, virtual node names and
filter node prefixes. Unisolated, the first run would have written to the user's
real settings — so the fence was mandatory until identity was reassigned, and the
rename was larger than the application ID.

## Not done here

Never run with the virtual sink as default, so stream-moving, routing
reconciliation and kill-while-default were unobserved. The LV2 equalizer was
never instantiated. Stream enumeration used one synthetic `paplay` stream. No
speaker-tuning filter chain was present. All are closed in spike 03.
