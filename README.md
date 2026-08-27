# 42Hz

An ultra-minimal, Omarchy-native control surface for PipeWire audio, derived
from [EasyEffects](https://github.com/wwmm/easyeffects).

42Hz preserves EasyEffects' PipeWire integration, stream routing, and DSP
hosting, and replaces its Kirigami frontend with a responsive, spectrum-first
QML interface that tracks the active Omarchy theme.

See [`project.md`](project.md) for design goals and milestones, and
[`docs/devlog.md`](docs/devlog.md) for the running development log.

**Status:** early design and architecture. The EasyEffects-derived core builds
and runs against the pinned upstream base; the 42Hz frontend does not exist yet.

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

Modifications against the upstream base are recorded in
[`docs/spike-01-frontend-coupling.md`](docs/spike-01-frontend-coupling.md) and
applied by [`spike/reduce-deps.py`](spike/reduce-deps.py). Runtime behaviour of
the derived core is recorded in
[`docs/spike-02-first-run.md`](docs/spike-02-first-run.md).

## Building the derived core

Upstream source is fetched and verified, never tracked:

```sh
./spike/fetch.sh
./spike/reduce-deps.py upstream/easyeffects-8.2.8
cmake -B upstream/easyeffects-8.2.8/build -S upstream/easyeffects-8.2.8 \
      -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C upstream/easyeffects-8.2.8/build
```

`upstream/` is disposable — re-running `fetch.sh` replaces it wholesale,
build directory included. Never hand-edit it; changes to the derived core
belong in `spike/reduce-deps.py`. See *Upstream working copy* in
[`project.md`](project.md).

Requires Qt 6, KF6 (Config, CoreAddons, I18n), CMake, and Ninja.

42Hz is not affiliated with or endorsed by the EasyEffects project, nor by
Omarchy.

## License

GPL-3.0-or-later, inherited from EasyEffects. See [`LICENSE`](LICENSE).
