# 42Hz development log

Chronological record of work, decisions, and dead ends.

**Convention.** Newest entry first — the common case is "what was I doing last
time". One entry per working session, dated. Each entry carries what changed,
what was *decided* (with the reasoning, so it can be revisited rather than
re-litigated), and what remains open.

This log records **what happened**. `project.md` records **what is true** about
the design. Findings graduate from here into `project.md` once they are durable;
status and narrative stay here. Detailed evidence lives in `docs/spike-*.md`.

---

## 2026-08-27 — Reduced-dependency build verified

**Commit:** `807099b`

The reduced tree configures, compiles, and links against Qt 6.11.2 / KF6 6.29.0,
producing a 13M binary. Linked KF6 libraries drop from 10 to 5 — `Archive`,
`BreezeIcons`, `ColorScheme`, `GuiAddons`, and `IconThemes` are gone — with no
Kirigami, QtGraphs, or QQC2-desktop-style objects remaining. Total shared
libraries fall 129 → 123.

Both risks pre-registered in spike 01 resolved favourably:

- `KF6::I18nQml` does **not** transitively pull in KDE UI components.
- `Qt::Graphs` was QML-only; removing it broke no C++ compilation.

**The informative failure.** The first build failed on exactly one target,
`main.cpp`, with `fatal error: kicontheme.h: No such file or directory`. 208 of
209 targets had already compiled, and the sole casualty was the entry point 42Hz
replaces regardless. No core file needed modification — a stronger result than a
clean first build, because it exercised the core/frontend boundary and the
boundary held.

Cause was a defect in `spike/reduce-deps.py`: `main.cpp` includes KDE headers in
both the CamelCase forwarding form (`<KIconTheme>`) and the lowercase real form
(`<kicontheme.h>`), and the patch matched only the former. Fixed. **Lesson for
future audits of KDE-adjacent code: grep both casings.**

**Not done:** the binary has never been executed. Running it starts a PipeWire
graph that creates virtual nodes and may alter default routing, so it needs a
deliberate first run rather than a build-check afterthought.

**Open:** vendoring strategy still undecided (see 2026-08-26). `.gitignore`
currently assumes patch-on-tarball.

---

## 2026-08-26 — Feasibility spike, and the repository

**Commits:** `b96ed1f`

**Decision: QML frontend, not a TUI.** The question raised was whether a TUI
could carry a spectrum analyser, on the strength of BTOP's feel. It can —
`cava` does exactly this, braille cells give 2×4 addressable dots, and `foot`
additionally supports sixel. Resolution and framerate were never the obstacle.

Rejected anyway, because a TUI would mean writing a frontend against a C++ core
reachable only over IPC, contradicting three of this project's own commitments:
backend stability over reinvention, single-process design, and a small patch
inventory. Two findings settled it in the other direction — upstream EasyEffects
8.x is *already* Qt6/QML, and Omarchy 4's shell is Quickshell, also QML/Qt6. QML
is simultaneously the upstream toolkit and the desktop's own.

What survives from the TUI idea is BTOP's *economy* — density, progressive
disclosure, no chrome — which `project.md` already framed correctly as something
to emulate rather than imitate. Worth noting the door isn't shut: the core
delivers a plain `QList<QPointF>`, which would feed a terminal renderer just as
easily.

**Coupling mapped.** Full evidence in `docs/spike-01-frontend-coupling.md`.
Headline: KDE coupling confined to 3 files; 62 of 66 QML files import Kirigami,
so no frontend is inheritable; the spectrum facade
(`requestSpectrumData` / `newSpectrumData`, resampled to a configurable
`nPoints`) already exists upstream.

**Decision: GPL-3.0-or-later from commit one.** 42Hz is a derivative of
GPL-3.0-or-later EasyEffects, so that is the destination regardless. Licensing at
commit one is free; relicensing later requires agreement from every contributor
by that point. The contributor set is currently one person — the cheapest it will
ever be.

**Decision: repo-local git identity**, not `--global`, so a project session does
not silently set authorship for every other repository on the machine.

**Open: vendoring strategy.** Does the repo vendor EasyEffects source, or stay
patch-on-tarball? Vendoring gives a buildable checkout at the cost of a
diff-noisy import and manual upstream merges. Patch-on-tarball keeps the repo
small and makes the modifications legible as *the whole repo* — closer to the
"small patch inventory" goal — but needs a fetch step and patches rot as upstream
moves. Deferred; it does not block current work, though `.gitignore` currently
leans patch-on-tarball.
