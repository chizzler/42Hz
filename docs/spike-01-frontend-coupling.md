# Spike 01 — EasyEffects frontend/backend coupling

**2026-08-26**, build-verified 2026-08-27. Milestone 1.

Base: EasyEffects `v8.2.8` (`6d9b1220d3dcebb154ba759a05600662bc0af549`),
GPL-3.0-or-later, © 2017-2026 Wellington Wallace. Attribution and
source-availability obligations begin at this revision.

## Headline

EasyEffects 8.x is **already a Qt6/QML application**, so the derivation is a
frontend swap within one toolkit, not a port. Omarchy 4's shell is Quickshell,
also QML/Qt6 — QML is simultaneously the upstream toolkit and the desktop's.

## Layer separation

The split is clean along directory lines: 110 of 124 C++ files under `src/`, all
66 QML files under `src/contents/ui/`, registered through a single
`qt_add_qml_module(easyeffects URI ee.ui …)` in `src/CMakeLists.txt:21`.

## The spectrum seam

`EffectsBase` already exposes a QML-ready, pull-based API:

```cpp
Q_INVOKABLE void requestSpectrumData();          // effects_base.hpp:82
void newSpectrumData(QList<QPointF> newData);    // effects_base.hpp:90  (signal)
Q_INVOKABLE void setSpectrumBypass(bool state);  // effects_base.hpp:86
```

`requestSpectrumData()` (`effects_base.cpp:463`) dispatches to `baseWorker` off
the QML thread, runs a GSL Steffen spline across the FFTW bins, and emits points
**already resampled to `nPoints`** (`effects_base.cpp:504`). `Spectrum`
(`src/spectrum.hpp`) is a `PluginBase` subclass — FFTW, 8192 bands, lock-free
double-buffered, no QML or KDE coupling. Reachable from QML because
`StreamOutputEffects` is `QML_ELEMENT` + `QML_SINGLETON`
(`stream_output_effects.hpp:29`).

Its display parameters are KConfig keys
(`src/contents/kcfg/easyeffects_db_spectrum.kcfg`), not hardcoded: `nPoints`,
`logarithmicHorizontalAxis`, `minimumFrequency`, `maximumFrequency`,
`spectrumFpsCap`, `dynamicYScale`, `spectrumShape`, `bars`, `lines`, `dots`,
`area`. Binding `nPoints` to width makes the core re-interpolate to fit, so a
responsive spectrum is a settings write rather than new DSP.

## KDE coupling is confined to 3 files

The main risk was Kirigami contaminating the core. It does not. Files
referencing `Kirigami` / `KColorScheme` / `KIconTheme` / `QQC2Desktop`:

```
src/main.cpp             KAboutData, KColorSchemeManager, KIconTheme
src/kcolor_manager.cpp   the KDE theme adapter — direct analogue of the
src/kcolor_manager.hpp   Omarchy adapter that replaces it
```

Across the remaining ~230 core files the only KDE headers are
`KLocalizedString` (9×) and `kconfigskeleton.h` (5×), both headless. **The
PipeWire, DSP, routing, preset and state layers have zero dependency on
Kirigami** — this is the finding the derivation rests on.

## No reusable frontend

62 of 66 QML files import `org.kde.kirigami`; 27 use `kirigamiaddons.formcard`.
There is nothing to inherit, so 42Hz writes its entire frontend and that
dominates milestones 2–4. Upstream renders the spectrum with QtGraphs, used only
from QML, so it drops out with the frontend.

## Patch inventory, phase 1

| File | Change |
|---|---|
| `CMakeLists.txt` | drop `Kirigami`, `KirigamiAddons`, `QQC2DesktopStyle`, `IconThemes`, `ColorScheme` from `find_package(KF6)`; drop `Graphs` from Qt; drop `ecm_find_qmlmodule(org.kde.kirigami)` |
| `src/CMakeLists.txt` | replace the `QML_FILES` list; drop `kcolor_manager.cpp`; unlink `KF6::ColorScheme`, `KF6::IconThemes`, `Qt::Graphs` |
| `src/main.cpp` | remove `KColorSchemeManager`, `KIconTheme`, `KColorManager`, the breeze style block, `QQuickStyle::setStyle("org.kde.desktop")` |
| `src/kcolor_manager.{cpp,hpp}` | deleted |
| `src/contents/ui/` | all 66 Kirigami QML files removed |

The single frontend attachment point is `src/main.cpp:285`,
`engine.loadFromModule("ee.ui", "Main")`.

## Build result

Qt 6.11.2 / KF6 6.29.0, CMake 4.4.2 + Ninja: configures, compiles and links to a
13M binary. Linked KF6 libraries drop from ten (`Archive`, `BreezeIcons`,
`ColorScheme`, `ConfigCore`, `ConfigGui`, `CoreAddons`, `GuiAddons`, `I18n`,
`I18nQml`, `IconThemes`) to five (`ConfigCore`, `ConfigGui`, `CoreAddons`,
`I18n`, `I18nQml`). Total shared libraries 129 → 123. No Kirigami, QtGraphs or
QQC2-desktop-style objects in the binary.

Both pre-registered risks resolved favourably: `KF6::I18nQml` does not pull KDE
UI in transitively, and `Qt::Graphs` was QML-only.

**One correction to the patch.** The first build failed on exactly one target,
`main.cpp`, with `fatal error: kicontheme.h: No such file or directory` — 208 of
209 targets had already compiled and the sole casualty was the entry point 42Hz
replaces anyway. `main.cpp` includes KDE headers in both the CamelCase
forwarding form and the lowercase real form, and the patch matched only the
former. **Grep both casings in KDE-adjacent code.**
