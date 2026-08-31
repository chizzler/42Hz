# 42Hz

An ultra-minimal, Omarchy-native control surface for PipeWire audio, derived
from [EasyEffects](https://github.com/wwmm/easyeffects).

42Hz keeps EasyEffects' PipeWire integration, stream routing and DSP hosting, and
replaces its Kirigami frontend with a responsive, spectrum-first QML interface
that tracks the active Omarchy theme.

Design and constraints are in [`project.md`](project.md); the development record
is in [`docs/dev-diary.md`](docs/dev-diary.md).

**Status:** milestones 1, 3 and 4 complete; milestone 2 all but a whole-theme
switch under load.

## What it does

The window is a live spectrum showing **absolute level** — a bar's height is the
magnitude the core reported, placed in a fixed dB window, so quiet audio draws a
quiet spectrum rather than a rescaled copy of a loud one. Two appearances, filled
pixel bars and a character grid of block elements, both reading the same window.
Density and style are adjusted from btop-style controls in the frame's top edge,
and dropped when the window is too narrow to hold them beside the title.

Signal and capability state is reported in the centre of the window, silence
included: a stream that is open and playing nothing is named rather than left as
an empty window.

An application mixer lists live playback streams with volume, mute and
processing-inclusion controls. Its volume reading is the one `pactl`, `wpctl` and
Omarchy's volume OSD show, so a stream reads the same here as anywhere else on
the desktop and the arrow keys step by the same 5%. When the window is too short
to draw every stream, the count it cannot show is marked on the divider.

A ten-band graphic equalizer sits in front of the spectrum, so a boost lifts the
part of the picture it applies to. Its bands are spread logarithmically across
20 Hz–20 kHz — the spectrum's own axis — so each control sits directly under the
frequencies it moves. It is in the chain from startup and stays there: showing,
hiding or resizing the editor leaves the audio graph untouched, and `b` bypasses
the equalizer itself rather than rebuilding the pipeline around it.

Two chrome modes switch from the keyboard, every action is reachable by key at
every size, and key hints are drawn in the theme's accent. Palette, typography
and spectrum ramp are all resolved from Omarchy state and follow a theme change
without a restart.

## Alongside Omarchy's speaker tuning

Omarchy ships speaker tunings as native PipeWire filter-chain sinks, not as
EasyEffects presets, so nothing is lost by conflicting with the EasyEffects
package. The question is ordering, and 42Hz chains in front:

```
application → 42hz_sink → 42Hz processing → tuning sink → device
```

Select the tuning as your default output and that forms on its own — 42Hz's
output leg follows the default onto the tuning, and the tuning reaches the device
on its own leg.

42Hz honours `node.dont-move`. A filter chain's output leg belongs to the device
it was fitted for, and Omarchy's tunings pin theirs precisely so that nothing
rerouting "all streams" drags the processing onto the wrong device or back into
the tuning's own sink. 42Hz treats that pin as binding rather than relying on the
session manager to enforce it. It also refuses to capture any stream whose path
returns to its own sink, so a monitor loopback cannot become a feedback loop
through the processing graph.

## Known limitations

Both are inherited from EasyEffects, present in the same code upstream, and not
fixed here — closing either would take a large rewrite of the derived core's
connection handling, which is the reinvention this project exists to avoid.

- **42Hz does not reconnect after a PipeWire restart.** It stays running and
  reports that the audio service is gone, but its virtual sink does not come
  back; restart 42Hz to recover.
- **An audio service that is unreachable at startup aborts the process.** If
  PipeWire is not running when 42Hz launches, it cannot start and cannot report
  why.

## Building

Upstream source is fetched and verified, never tracked:

```sh
./spike/fetch.sh
./spike/reduce-deps.py upstream/easyeffects-8.2.8
cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build
```

The binary is `build/42hz`, installed under the application ID
`io.github.chizzler.42Hz`. Requires Qt 6, KF6 (Config, CoreAddons, I18n), CMake
and Ninja.

The build root is this repository. `upstream/` holds the patched derived core and
is disposable — re-running `fetch.sh` replaces it wholesale. Never hand-edit it;
changes to the derived core belong in `spike/reduce-deps.py`. 42Hz's own source
is `frontend/`. See *Upstream working copy* in [`project.md`](project.md).

## Derivation and attribution

42Hz is a derivative work of EasyEffects.

| | |
|---|---|
| Upstream | https://github.com/wwmm/easyeffects |
| Base revision | `v8.2.8` |
| Upstream copyright | © 2017-2026 Wellington Wallace |
| Upstream license | GPL-3.0-or-later |

**Derived:** PipeWire session integration, stream discovery and routing,
input/output pipelines, DSP/LV2 hosting, preset and state handling, and spectrum
production (FFTW analysis with GSL spline interpolation).

**Replaced:** the entire QML frontend, the application entry point, and the KDE
colour-scheme adapter (`kcolor_manager`).

**Reassigned:** application ID, executable name, configuration and presets
directories, single-instance lock and socket, logging category, PipeWire virtual
node names, DSP filter node prefix, node groups, desktop entry, metainfo and
icons. 42Hz reads none of EasyEffects' settings and runs alongside it without
collision.

Modifications against the upstream base are applied by
[`spike/reduce-deps.py`](spike/reduce-deps.py), which is the complete patch
inventory. It contains no 42Hz frontend source: 42Hz's QML is its own Qt module
(`hz.ui`) built from `frontend/` and linked into the derived core's target, so the
inventory stays a record of what changed in upstream's tree.

Evidence: dependency reduction in
[`docs/spike-01-frontend-coupling.md`](docs/spike-01-frontend-coupling.md), first
execution in [`docs/spike-02-first-run.md`](docs/spike-02-first-run.md), identity
reassignment and milestone-1 verification in
[`docs/spike-03-identity.md`](docs/spike-03-identity.md), responsive behaviour in
[`docs/spike-04-responsive.md`](docs/spike-04-responsive.md), and the unimplemented
reconnection design in
[`docs/spike-05-reconnection.md`](docs/spike-05-reconnection.md).

42Hz is not affiliated with or endorsed by the EasyEffects project, nor by
Omarchy.

## License

GPL-3.0-or-later, inherited from EasyEffects. See [`LICENSE`](LICENSE).
