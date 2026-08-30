# 42Hz

An ultra-minimal, Omarchy-native control surface for PipeWire audio, derived
from [EasyEffects](https://github.com/wwmm/easyeffects).

42Hz preserves EasyEffects' PipeWire integration, stream routing, and DSP
hosting, and replaces its Kirigami frontend with a responsive, spectrum-first
QML interface that tracks the active Omarchy theme.

See [`project.md`](project.md) for design goals and milestones, and
[`docs/dev-diary.md`](docs/dev-diary.md) for the running development diary.

**Status:** milestone 1 complete; milestones 2 and 3 in progress. The
EasyEffects-derived core builds and runs under its own identity against the
pinned upstream base, and is verified against real application streams, the EQ
LV2 provider and its failure path, default-sink routing, forced termination, and
a speaker-tuning filter-chain. Milestone 2's responsive behaviour has been swept
across tiled, floating, narrow, wide and fullscreen geometries and the defects
it found are fixed; the theme is verified against every shipped Omarchy theme
and follows a live text-size change, leaving a whole-theme switch under load as
the last open item. Milestone 3 has been swept at graph level — device churn,
virtual sinks and stream capture all behave, and the one defect it found, a
feedback loop 42Hz would build through its own sink, is fixed. Browser and game
streams, speaker-tuning coexistence and the mixer's on-screen display remain.

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
streams with volume, mute, and processing-inclusion controls. Two chrome modes
are switchable from the keyboard, every action is reachable by key at every
size, and key hints are drawn in the theme's accent wherever they appear.

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
