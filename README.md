# 42Hz

An ultra-minimal, Omarchy-native control surface for PipeWire audio, derived
from [EasyEffects](https://github.com/wwmm/easyeffects).

42Hz preserves EasyEffects' PipeWire integration, stream routing, and DSP
hosting, and replaces its Kirigami frontend with a responsive, spectrum-first
QML interface that tracks the active Omarchy theme.

See [`project.md`](project.md) for design goals and milestones, and
[`docs/dev-diary.md`](docs/dev-diary.md) for the running development diary.

**Status:** milestone 1 complete; milestone 2 in progress. The EasyEffects-derived
core builds and runs under its own identity against the pinned upstream base, and
is verified against real application streams, the EQ LV2 provider and its failure
path, default-sink routing, forced termination, and a speaker-tuning filter-chain.

42Hz's own frontend lives in [`frontend/`](frontend) and renders the live spectrum
on the active Omarchy theme — palette, typography and spectrum ramp all resolved
from Omarchy state and updated without a restart when the theme changes. Bar density
follows window width. It has no keyboard navigation and does not yet report
capability-specific state.

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
