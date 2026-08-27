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

## 2026-08-27 (afternoon) — Reproducible build, and first light

**Commit:** `75cdbd5`

Two threads: making this morning's build reproducible, and executing the derived
binary for the first time. Evidence in `docs/spike-02-first-run.md`.

### The build could not be re-run

`spike/reduce-deps.py` hard-coded a scratchpad path from the session that
produced it, and that directory no longer existed. This morning's verification
was a claim in a document rather than a repeatable fact. Fixed.

**Decision: patch-on-tarball, confirmed.** The vendoring question left open
yesterday is settled in favour of the option `.gitignore` already leaned
towards. Nothing about the reproducibility defect argued for vendoring — it was
an unpinned base and a hard-coded path, both fixable without importing 700 files
of someone else's source and inheriting a manual merge on every upstream release.

**Decision: the extracted tree is disposable.** `fetch.sh` deletes and
re-extracts `upstream/` on every run, build directory included, with no prompt.
Alternatives considered: refusing when a tree exists, and clobbering only an
unpatched one.

The reasoning is worth keeping, because it converts an aspiration into a
mechanism. The small-patch-inventory obligation in `project.md` was until now a
promise to be disciplined. Under a disposable tree it is enforced by
construction — an edit not in `reduce-deps.py` does not survive the next fetch,
so it cannot quietly become load-bearing, and the patch script cannot drift out
of step with what is actually built. Discarding the build directory first looked
like the cost of the policy; it is better read as part of it, since a build
reflecting a source state that no longer exists is the same class of
inconsistency.

**Two-tier checksum.** The base is pinned by commit, by archive checksum, *and*
by a digest of the extracted 709-file tree. GitHub generates tag archives on
demand and has changed their compression before, invalidating pinned checksums
ecosystem-wide without a line of source changing. The tree digest distinguishes
"same source, recompressed" (warn, continue) from "source changed" (refuse).
Pinning only the archive pins the artifact, not the content.

**Guards on the patch script.** It now refuses a path that is not an EasyEffects
tree, and refuses an already-patched one. The second matters more than expected:
the script is destructive and in-place, and its CMake edits are regex line
deletions, so a second run would not error — it would no-op those deletions and
then fail mid-splice, leaving a half-patched tree that looks fine.

Verified end to end from a clean checkout: 209/209 targets, 13M binary, 123
shared libraries, KF6 down to ConfigCore, ConfigGui, CoreAddons, I18n, I18nQml —
identical to this morning's figures, now reproducible rather than merely
recorded. The re-fetch path was exercised against an 89M patched-and-built tree.

### First light

**The binary ran, and the spectrum is live.** A 440 Hz sine played into
`easyeffects_sink` rendered as a single narrow peak in the placeholder
`Main.qml` canvas. That closes the derivation's central assumption: PipeWire →
FFTW → spline → `newSpectrumData` → plain QtQuick works with no Kirigami, no
QtGraphs, no KDE style. Spike 01 inferred this from source; it is now
demonstrated.

**The run was fenced, and needed to be.** `XDG_CONFIG_HOME` was redirected to
scratch. Unisolated, the first launch would have written to the real
`~/.config/easyeffects/db/`, over a populated `equalizerrc`. The derived binary
still shares *every* identifier with upstream — app id, window title, config
path, virtual node names, filter node prefixes. Two consequences: the isolation
fence is mandatory on every development run until identity is reassigned, and
the rename is larger than the application ID `project.md` described.

**Startup does not hijack routing**, and teardown is clean under both `SIGTERM`
and `SIGKILL` — nodes reaped, default sink untouched. But the virtual sink was
never made default in this run, so the case the requirement exists for — killing
the process while the default route points at it — is still untested. Recorded
as such rather than counted as passing.

### The finding that changes something

Omarchy resolves a DSP sink to the physical sink whose volume it really
controls, so volume keys act on the endpoint rather than on the level going into
processing. `omarchy-audio-output-sink` does this by walking
`pactl list sink-inputs`.

It cannot see the EasyEffects output leg. The node feeding the physical device is
`ee_soe_output_level` — a PipeWire filter node with no `media.class`, linked port
to port, never enumerated as a sink-input. Asked directly with the graph live,
the resolver hands back its own argument.

This overturns an assumption raised in review: that 42Hz could satisfy the
resolver's generic branch by naming its downstream stream after its virtual sink.
That branch is unreachable regardless of naming, because there is no sink-input
to name. **Node naming was never the lever.** The honest options are to present a
real sink-input (a core modification), to extend the resolver to walk PipeWire
links (an upstream Omarchy change that also fixes EasyEffects and tuning chains),
or to accept a fallback producing exactly the failure the resolver exists to
prevent. The second is preferred and is not 42Hz's code to change.

Not a 42Hz regression — the same gap applies to stock EasyEffects on Omarchy
today. Inheriting a bug is one of the quieter costs of derivation.

### Corrections folded into project.md

Omarchy's speaker tuning is a native PipeWire filter-chain fitted by measurement
from an EasyEffects profile, not an EasyEffects preset. `conflicts=easyeffects`
costs the tuning nothing; the coexistence question was mis-stated.

`project.md` now also distinguishes commitments from sketches. Much of it was
written before anything ran, and the command surface and layout tiers in
particular were being read with more authority than they had earned.

### Milestone 1 status

Done: base pinned, licensing preserved, coupling mapped, reproducible build,
executable owning its derived core, live spectrum, PipeWire endpoints.

Open: application-stream enumeration against real clients (only a synthetic
`paplay` stream so far), the EQ LV2 URI and its failure path (never
instantiated), routing with the virtual sink as default, and behaviour chained
behind a speaker-tuning filter-chain (none present on this host).

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
