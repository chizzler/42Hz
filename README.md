# 42Hz

An ultra-minimal, Omarchy-native control surface for PipeWire audio, derived
from [EasyEffects](https://github.com/wwmm/easyeffects).

42Hz preserves EasyEffects' PipeWire integration, stream routing, and DSP
hosting, and replaces its Kirigami frontend with a responsive, spectrum-first
QML interface that tracks the active Omarchy theme.

See [`project.md`](project.md) for design goals and milestones.

**Status:** early design and architecture. Not yet buildable as 42Hz.

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
applied by [`spike/reduce-deps.py`](spike/reduce-deps.py).

42Hz is not affiliated with or endorsed by the EasyEffects project, nor by
Omarchy.

## License

GPL-3.0-or-later, inherited from EasyEffects. See [`LICENSE`](LICENSE).
