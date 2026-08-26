# Spike 01 — EasyEffects frontend/backend coupling

**Date:** 2026-08-26
**Milestone:** 1 (repository and feasibility spike)
**Status:** static analysis complete; build verification pending

## Upstream base

| | |
|---|---|
| Project | EasyEffects — https://github.com/wwmm/easyeffects |
| Pinned revision | `v8.2.8` |
| Installed reference | `easyeffects 8.2.8-1` (Arch `extra`) |
| License | GPL-3.0-or-later |
| Copyright | © 2017-2026 Wellington Wallace |

Attribution and source-availability obligations begin at this revision.

## Headline finding

EasyEffects 8.x is **already a Qt6/QML application**. `project.md` specifies a
Qt/QML frontend without recording that upstream shares that toolkit — the
derivation is a frontend swap within one toolkit, not a port.

Independently: Omarchy 4.0's shell is **Quickshell**, which is also QML/Qt6
(`quickshell-git 0.3.0`, 95 `.qml` files under `/usr/share/omarchy/shell`).
QML is simultaneously the upstream toolkit and the Omarchy desktop toolkit.

## Layer separation

| Layer | Location | Size |
|---|---|---|
| C++ core | `src/*.cpp`, `src/*.hpp` | 110 / 124 files |
| QML frontend | `src/contents/ui/` | 66 files |

The split is clean along directory lines. All QML lives in one directory and is
registered through a single `qt_add_qml_module(easyeffects URI ee.ui ...)` block
in `src/CMakeLists.txt:21`.

## The spectrum seam

`EffectsBase` already exposes a QML-ready, pull-based spectrum API:

```cpp
Q_INVOKABLE void requestSpectrumData();          // effects_base.hpp:82
void newSpectrumData(QList<QPointF> newData);    // effects_base.hpp:90  (signal)
Q_INVOKABLE void setSpectrumBypass(bool state);  // effects_base.hpp:86
```

`requestSpectrumData()` (`effects_base.cpp:463`) dispatches to `baseWorker` off
the QML thread, runs a GSL Steffen spline across the FFTW bins, and emits points
**already resampled to `nPoints`** (`effects_base.cpp:504`).

`Spectrum` (`src/spectrum.hpp`) is a `PluginBase` subclass: FFTW-based, 8192
bands, lock-free double-buffered, with **no QML or KDE coupling**.

Reachable from QML as a singleton — `StreamOutputEffects` is `QML_ELEMENT` +
`QML_SINGLETON` (`stream_output_effects.hpp:29`):

```qml
import ee.ui
Connections {
    target: StreamOutputEffects
    function onNewSpectrumData(newData) { /* QList<QPointF> */ }
}
```

### Responsiveness comes free

The spectrum's display parameters are KConfig keys
(`src/contents/kcfg/easyeffects_db_spectrum.kcfg`), not hardcoded:

`nPoints`, `logarithmicHorizontalAxis`, `minimumFrequency`, `maximumFrequency`,
`spectrumFpsCap`, `dynamicYScale`, `spectrumShape`, `bars`, `lines`, `dots`, `area`

Binding `nPoints` to widget width on resize makes the core re-interpolate to fit.
The responsive spectrum in `project.md` is a settings write, not new DSP code.

## KDE coupling is confined to 3 files

The main risk was Kirigami contaminating the core. It does not.

Files referencing `Kirigami` / `KColorScheme` / `KIconTheme` / `QQC2Desktop`:

```
src/main.cpp             KAboutData, KColorSchemeManager, KIconTheme
src/kcolor_manager.cpp   \_ the KDE theme adapter — the direct analogue of
src/kcolor_manager.hpp      the Omarchy theme adapter that replaces it
```

Across the remaining ~230 core files, the only KDE headers used are
`KLocalizedString` (9×) and `kconfigskeleton.h` (5×) — both headless.

**The PipeWire, DSP, routing, preset, and state layers have zero dependency on
Kirigami.** This is the finding the derivation strategy rests on.

## No reusable frontend

62 of 66 QML files import `org.kde.kirigami`; 27 use `kirigamiaddons.formcard`.
There is effectively **nothing to inherit** — 42Hz writes its entire frontend.

This costs nothing that was planned: `project.md` already requires that "UI code
must not depend directly on upstream EasyEffects screens." But it does mean the
frontend is the bulk of the remaining work, and the schedule should reflect that.

Upstream renders the spectrum with QtGraphs (`Qt::Graphs`), used **only** from
QML — no C++ file references it, so it drops out with the frontend.

## Patch inventory

`spike/reduce-deps.py` applies the full dependency reduction. It is the current
patch inventory and should stay small.

| File | Change |
|---|---|
| `CMakeLists.txt` | drop `Kirigami`, `KirigamiAddons`, `QQC2DesktopStyle`, `IconThemes`, `ColorScheme` from `find_package(KF6)`; drop `Graphs` from Qt; drop `ecm_find_qmlmodule(org.kde.kirigami)` |
| `src/CMakeLists.txt` | replace `QML_FILES` list with one `Main.qml`; drop `kcolor_manager.cpp`; unlink `KF6::ColorScheme`, `KF6::IconThemes`, `Qt::Graphs` |
| `src/main.cpp` | remove `KColorSchemeManager`, `KIconTheme`, `KColorManager`, breeze style block, `QQuickStyle::setStyle("org.kde.desktop")` |
| `src/kcolor_manager.{cpp,hpp}` | deleted — replaced by the Omarchy theme adapter |
| `src/contents/ui/` | all 66 Kirigami QML files removed; one plain-QtQuick `Main.qml` added |

Resulting KF6 component set: **9 → 4** (`Config`, `ConfigWidgets`, `CoreAddons`,
`I18n`). `ConfigWidgets` is retained conservatively and may also be removable.

The single frontend attachment point is `src/main.cpp:285`:

```cpp
engine.loadFromModule("ee.ui", "Main");
```

## Verification status

Static analysis only. **Not yet built.** Two residual risks:

1. `KLocalizedString` / `KF6::I18nQml` may transitively pull KDE UI components at
   link time.
2. `ConfigWidgets` retains a QtWidgets dependency; the app also constructs
   `QApplication` (not `QGuiApplication`) for `QSystemTrayIcon`.

Neither threatens the architecture — both are link-level details.

Build prerequisites missing on this machine:
`cmake`, `extra-cmake-modules`, `ninja`, `intltool`, `mold`, `ladspa`.

## Conclusion

The derivation strategy in `project.md` holds, and is cheaper than the document
assumes. Recommended amendments:

1. Record that upstream is already Qt6/QML, and that Omarchy's shell is Quickshell.
2. Note that the theme adapter reads `colors.toml` **and** `shell.toml` — Omarchy's
   own `Commons/Color.qml` uses `shell.toml` for per-surface roles and is the
   reference implementation to follow.
3. State plainly that no upstream QML is reusable, so frontend effort dominates
   milestones 2–4.
