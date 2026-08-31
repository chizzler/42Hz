# 42Hz

An ultra-minimal, Omarchy-native control surface for PipeWire audio, derived
from [EasyEffects](https://github.com/wwmm/easyeffects).

42Hz preserves EasyEffects' PipeWire integration, stream routing, and DSP
hosting, and replaces its Kirigami frontend with a responsive, spectrum-first
QML interface that tracks the active Omarchy theme.

See [`project.md`](project.md) for design goals and milestones, and
[`docs/dev-diary.md`](docs/dev-diary.md) for the running development diary.

**Status:** milestones 1 and 3 complete; milestone 2 in progress. The
EasyEffects-derived core builds and runs under its own identity against the
pinned upstream base, and is verified against real application streams, the EQ
LV2 provider and its failure path, default-sink routing, forced termination, and
a speaker-tuning filter-chain. Milestone 2's responsive behaviour has been swept
across tiled, floating, narrow, wide and fullscreen geometries and the defects
it found are fixed; the theme is verified against every shipped Omarchy theme
and follows a live text-size change, leaving a whole-theme switch under load as
the last open item. Milestone 3 is verified: browser, game, music and
ALSA-compatibility streams are captured, named and controlled by volume, mute
and processing inclusion; device churn, virtual sinks, stream capture and a
speaker-tuning filter chain all behave. Voice chat is covered only by analogy —
its clients are Electron, and so the browser case — with no live call made. Five defects were found and fixed along
the way — a feedback loop 42Hz would build through its own sink, its overriding
of a filter-chain stream's routing pin, a volume reading nothing else on the
desktop agreed with, a mixer clipped by the window edge in bare chrome, and a
stream list that hid rows without saying so.

42Hz's own frontend lives in [`frontend/`](frontend) and renders the live spectrum
on the active Omarchy theme — palette, typography and spectrum ramp all resolved
from Omarchy state and updated without a restart when the theme changes.

The spectrum shows **absolute level**: a bar's height is the magnitude the core
reported, placed in a fixed dB window, so quiet audio draws a quiet spectrum
rather than a rescaled copy of a loud one. It has two appearances — filled pixel
bars, and a character grid built from block elements the way cava and btop draw
one — and both read the same window, so switching cannot look like the signal
changed. Density and style are adjusted from btop-style controls drawn into the
frame's top edge, and dropped when the window is too narrow to hold them beside
the title.

Signal and capability state is reported in the centre of the window, and silence
is one of those states: a stream that is open and playing nothing is named
rather than left as an empty window. An application mixer lists live playback
streams with volume, mute, and processing-inclusion controls. Its volume reading
is the one `pactl`, `wpctl` and Omarchy's own volume OSD show, so a stream reads
the same here as anywhere else on the desktop and the arrow keys step by the
same 5%. When the window is too short to draw every stream, the count it cannot
show is marked on the divider rather than left to be discovered. Two chrome modes
are switchable from the keyboard, every action is reachable by key at every
size, and key hints are drawn in the theme's accent wherever they appear.

## Alongside Omarchy's speaker tuning

Omarchy ships speaker tunings as native PipeWire filter-chain sinks, not as
EasyEffects presets, so nothing is lost by conflicting with the EasyEffects
package. The question is ordering, and 42Hz chains in front:

```
application → 42hz_sink → 42Hz processing → tuning sink → device
```

Select the tuning as your default output and that forms on its own — 42Hz's
output leg follows the default onto the tuning, and the tuning reaches the
device on its own leg.

42Hz honours `node.dont-move`. A filter chain's output leg belongs to the device
it was fitted for, and Omarchy's tunings pin theirs precisely so that nothing
rerouting "all streams" drags the processing onto the wrong device or back into
the tuning's own sink. 42Hz treats that pin as binding rather than relying on
the session manager to enforce it.

It also refuses to capture any stream whose path returns to its own sink, so a
monitor loopback cannot be turned into a feedback loop through the processing
graph.

## Known limitations

Both are inherited from EasyEffects, present in the same code upstream, and not
fixed here — closing either would take a large rewrite of the derived core's
connection handling, which is the reinvention this project exists to avoid.

- **42Hz does not reconnect after a PipeWire restart.** It stays running and
  reports that the audio service is gone, but its virtual sink does not come
  back; restart 42Hz to recover. It no longer exits when this happens, which it
  used to.
- **An audio service that is unreachable at startup aborts the process.** If
  PipeWire is not running when 42Hz launches, it cannot start and cannot report
  why.

## Derivation and attribution

42Hz is a derivative work of EasyEffects.

| | |
|---|---|
| Upstream | https://github.com/wwmm/easyeffects |
| Base revision | `v8.2.8` |
| Upstream copyright | © 2017-2026 Wellington Wallace |
| Upstream license | GPL-3.0-or-later |

Derived components: PipeWire session integration, stream discovery and routing,
input/output pipelines, DSP/LV2 hosting, preset and state handling, and spectrum
production (FFTW analysis with GSL spline interpolation).

Replaced components: the entire QML frontend, application entry point, and the
KDE colour-scheme adapter (`kcolor_manager`).

Reassigned identity: application ID, executable name, configuration and presets
directories, single-instance lock and socket, logging category, PipeWire virtual
node names, DSP filter node prefix, node groups, desktop entry, metainfo, and
icons. 42Hz reads none of EasyEffects' settings and runs alongside it without
collision.

Modifications against the upstream base are applied by
[`spike/reduce-deps.py`](spike/reduce-deps.py), which is the complete patch
inventory. It contains no 42Hz frontend source: 42Hz's QML is its own Qt module
(`hz.ui`) built from `frontend/` and linked into the derived core's target, so
the patch inventory stays a record of what was changed in upstream's tree. Dependency reduction is recorded in
[`docs/spike-01-frontend-coupling.md`](docs/spike-01-frontend-coupling.md),
first execution in
[`docs/spike-02-first-run.md`](docs/spike-02-first-run.md), and identity
reassignment plus milestone-1 verification in
[`docs/spike-03-identity.md`](docs/spike-03-identity.md).

## Building the derived core

Upstream source is fetched and verified, never tracked:

```sh
./spike/fetch.sh
./spike/reduce-deps.py upstream/easyeffects-8.2.8
cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build
```

The binary is `build/42hz`, and it installs under the application ID
`io.github.chizzler.42Hz`.

The build root is this repository. `upstream/` holds the patched derived core
and is disposable — re-running `fetch.sh` replaces it wholesale. Never
hand-edit it; changes to the derived core belong in `spike/reduce-deps.py`.
42Hz's own source lives in `frontend/` and is tracked here. See *Upstream
working copy* in [`project.md`](project.md).

Requires Qt 6, KF6 (Config, CoreAddons, I18n), CMake, and Ninja.

42Hz is not affiliated with or endorsed by the EasyEffects project, nor by
Omarchy.

## License

GPL-3.0-or-later, inherited from EasyEffects. See [`LICENSE`](LICENSE).
