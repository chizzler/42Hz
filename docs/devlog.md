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

## 2026-08-29 — Where 42Hz's own source lives

**Commit:** `ec9d5dd`

Milestone 1 left the frontend as a 65-line QML string literal inside
`reduce-deps.py`. That was right for a placeholder and is wrong for anything
milestone 2 needs, so this session settled where 42Hz's own code lives and
proved the arrangement by building it.

### Decision: the repository is the build root

A tracked top-level `CMakeLists.txt` adds the patched core and then `frontend/`:

```cmake
add_subdirectory(upstream/easyeffects-8.2.8)   # derived core, disposable
add_subdirectory(frontend)                     # 42Hz's own, tracked
```

`upstream/` stays wholly regenerable, so the disposable-tree guarantee is
untouched — but 42Hz's source now sits outside it, tracked, and is compiled
from its real path rather than a copy. That last part is the whole point.

**Rejected: copying `frontend/` into the tree at patch time.** It works, and it
recreates the exact trap the disposable-tree rule exists to prevent, aimed at
your own code instead of upstream's. Compile errors, QML traces,
`compile_commands.json` and qmlls would all point at the copy under
`upstream/`; editing the copy is the natural motion and the next `fetch.sh`
eats it. A safeguard that misfires daily on the code you actually write is
worse than none.

**Rejected for now: splitting the core into a library** and giving 42Hz the
executable. That is the shape `project.md`'s architecture section describes, and
it makes the facade a link boundary instead of a directory convention. It also
means rewriting `src/CMakeLists.txt` — ~30 target references — and
re-verifying that rewrite on every upstream bump, against a file upstream
changes freely. Straight conflict with the small-patch-inventory obligation.
Revisit when the facade is under real pressure, around milestone 3-4.

### The finding that justifies prototyping

**The obvious way to do this builds cleanly and fails at runtime.**

The first attempt kept one QML module and contributed 42Hz's files to it from
outside, via `qt_target_qml_sources(easyeffects QML_FILES Main.qml)` in
`frontend/`. CMake configured. 207/207 targets built. The generated
`.qrc` pointed at the tracked file, and `Main.qml` was demonstrably embedded in
the binary. Then:

```
terminate called after throwing an instance of 'std::runtime_error'
  what():  Failed to load QML UI
```

The generated `qmldir` had no `Main` entry. **Qt finalizes a QML module at the
end of the directory scope that declared it**, so by the time `frontend/` was
processed the core's module was already written. The call added the resource
and could not amend the module. Nothing warned — not CMake, not the build, not
Qt at startup beyond the failure itself.

Fixed by giving the frontend its **own** module: `qt_add_qml_module(hz_frontend
STATIC URI hz.ui QML_FILES Main.qml)`, linked in as `hz_frontendplugin`. The
core keeps its upstream URI `ee.ui` and, after patching, registers C++ types
and ships no QML at all.

The split turns out to be better than the thing it replaced. `ee.ui` is the
derived core's type registry; `hz.ui` is 42Hz's interface. **Every `import
ee.ui` in 42Hz QML is a reach across the facade boundary, and is greppable as
such** — which is the first mechanical check `project.md`'s "UI code must not
depend directly on upstream" has ever had.

Two scope traps found on the way, both because CMake does not propagate
sideways: `frontend/` needs its own `set(CMAKE_AUTOMOC ON)` and its own
`qt_policy(SET QTP0001/QTP0004 NEW)`. Upstream sets both, in its own directory.

### What this did to the patch inventory

It shrank: 551 → 514 lines, and the frontend heredoc is gone. `reduce-deps.py`
now deletes 66 upstream QML files and writes none. Two edits replaced it —
dropping `QML_FILES` from the core's module, and pointing `main.cpp` at
`qrc:/qt/qml/hz/ui/Main.qml` / `loadFromModule("hz.ui", "Main")`.

That second one deserves a note: the literal in `main.cpp` gates
`window->show()`. Get it wrong and the process runs happily with a live audio
graph and no window, no error, no log line. It cost a confused minute here; it
would cost more later. Also dropped the now-dead
`set_source_files_properties(...Common.qml Validators.qml...)` block, which
named QML singletons this script deletes.

### Verified

Full cycle from scratch — `fetch.sh` re-extracting over the hand-edited tree,
which is exactly what it is for, then patch, then build from the repo root:

- **229/229 targets**, 13M binary, 123 shared libraries, the same five KF6
  (`ConfigCore`, `ConfigGui`, `CoreAddons`, `I18n`, `I18nQml`). Identical to the
  milestone-1 baseline, so the layout change cost nothing.
- No Kirigami, QtGraphs or QQC2-desktop-style linked. No stale `ee.ui` resource
  paths in the binary.
- `qmldir` declares `Main 1.0 Main.qml`.
- Runs: window maps under Hyprland with class `io.github.chizzler.42Hz`, title
  `42Hz`. Virtual nodes correct (`42hz_sink`, `42hz_source`, `hz_soe_*`,
  `hz_sie_*`), all reaped on `SIGTERM`.
- Spectrum delivery re-confirmed across the new module boundary: with a 440 Hz
  tone playing into `42hz_sink`, `Main.qml` receives 100 points per frame.

The binary is now `build/42hz` — `RUNTIME_OUTPUT_DIRECTORY` set at the root, so
the path no longer moves with the upstream version.

### A silent frontend, and why logs could not have caught it

Creating `frontend/Main.qml` I changed its import from `ee.ui` to `hz.ui`,
reasoning that the file now belongs to the frontend module. Wrong: `Main.qml`
*is* `hz.ui` and does not import itself, while `StreamOutputEffects` and every
other core type is registered in `ee.ui`. The correct import is unchanged from
upstream.

The application started, mapped its window, created its PipeWire nodes and
looked entirely healthy. `StreamOutputEffects` was `undefined`, the
`Connections` block bound to nothing, and a 60 Hz timer called a method on
undefined — a frontend with no signal at all.

**Nothing in the logs said so, and nothing could have.** Upstream includes KDE's
`KDECompilerSettings`, which defines `QT_NO_DEBUG_OUTPUT` for Release builds, so
`console.log` and QML's diagnostics are compiled out entirely. Every run this
session produced a **zero-byte** log, which was read as "clean" when it only
ever meant "muted". An earlier draft of this entry cited "zero QML warnings" as
evidence; that claim was worth nothing.

What worked was making the program state externally observable: the probe put
`typeof StreamOutputEffects` and the live point count into the window title and
read them back with `hyprctl clients -j`. `soe=undefined pts=0` before the fix,
`soe=object pts=100` after, with a tone playing.

Two things follow, and both outlast this bug. **A Release build cannot be
verified from its own logs** — either build Debug for diagnosis, or observe from
outside the process. And **a QML frontend fails silently by construction**:
undefined identifiers are a runtime warning, not a build error, so "it launched
and drew a window" is not evidence that anything is connected. Milestone 2 needs
a way to assert the spectrum is live that does not depend on someone looking at
it.

### Still open

The theme adapter is the next real work, and it is the honest starting point for
milestone 2: the placeholder's colours carry `// Omarchy: theme accent` comments
that are currently lies. `/usr/share/omarchy/shell/Commons/Color.qml` is the
reference implementation and is on this host.

Two pieces of tidying not done: `spike/` is no longer a spike directory — those
two files are the build system — and the repo is on `master` while `project.md`
and the README both say `main`. Free to fix before a first push, annoying after.

---

## 2026-08-28 — Identity reassignment, and closing milestone 1

**Commit:** `b43a017`

The rename spike 02 called for, then the milestone-1 checks that were still
open. Evidence in `docs/spike-03-identity.md`.

### The rename was larger than an application ID, and one constant wide

Sixteen distinct surfaces carried Easy Effects' identity: application ID,
executable name, KConfig database path, presets directory, single-instance lock
*and socket*, logging category, virtual sink and source names and descriptions,
DSP filter node prefix, node groups, test-tone node, internal media classes,
desktop entry, metainfo, icons, and the portal autostart token. All of them now
derive from constants at the top of `reduce-deps.py`. The patch inventory grew
from 5 files to 17, and from 162 lines to 513.

**Decision: the CMake target keeps its upstream name.** Only `OUTPUT_NAME`
changes, so the binary is `42hz` while the target stays `easyeffects`. Renaming
the target would have touched roughly thirty lines in `src/CMakeLists.txt` plus
`qt_add_qml_module`, for no effect visible outside the build directory. Identity
is what the system sees, not what CMake calls things internally.

**Decision: extend the copyright line, do not replace it.** The about box now
reads `© 2017-2026 Wellington Wallace (Easy Effects) · 42Hz frontend © 2026 42Hz
contributors`. Dropping the original notice from a GPL derivative would be a
licence violation, not merely impolite. For the same reason the plugin vendor
label `"Easy Effects"` in `tags_plugin_name.hpp` was deliberately left alone: it
labels DSP that really is upstream's work, and relabelling it "42Hz" would
misattribute someone else's code. Upstream's 65K metainfo — entirely Easy
Effects release notes — was replaced with a short stub rather than shipped under
the 42Hz application ID.

**Decision: the application ID is `io.github.chizzler.42Hz`.** `project.md`
suggested `io.omarchy.42hz`, but the README disclaims Omarchy affiliation and a
reverse-DNS ID should name a domain its author controls. Settled and verified
live on all four surfaces it reaches — binary, installed asset names, the
Wayland class Hyprland reports, and the PipeWire `application.id` on every node.

Its final component begins with a digit, which Flatpak application IDs and
D-Bus bus names both forbid. Neither binds 42Hz — no D-Bus name is registered
and the target is an Arch package — but a Flatpak would need a different ID.
Worth noting only because it is the *second* digit-leading-name hazard today,
after `42hz_sink`; the shape of this project's name keeps mattering.

### The finding that justifies running things

**Renaming the virtual sink to `42hz_sink` silently broke stream enumeration.**

`target.object` is how a client pins its output, and PipeWire documents the value
as "a name or serial number". The core decides which by trying a numeric parse
first — via `util::str_to_num`, which wraps `std::from_chars` and checks only
`ec`. But `from_chars` reports success on a **partial** parse. `"42hz_sink"`
therefore parsed as serial `42`, matched nothing, and the stream was dropped
from the mixer while staying perfectly audible.

`ffplay` does exactly this. It vanished from the model. `mpv` and `paplay`,
which set no target, were fine — so a casual test would have passed.

The control mattered: stock Easy Effects v8.2.8, same host, same `ffplay`,
targeting `easyeffects_sink`, accepted it. **We introduced this**, purely by
choosing a name that begins with a digit. `42hz_source` had the same defect on
the capture side.

Fixed by treating `target.object` as a serial only when it is entirely digits —
one replacement covering both blocks. **Deliberately not** fixed in `str_to_num`
itself: 18 call sites, several parsing Equalizer-APO values where a trailing
unit may rely on the lenient parse. Tightening the shared helper is the better
long-term fix and is worth reporting upstream, but not blind.

The lesson generalises past this bug. A rename is not a cosmetic operation when
the new name has a different *shape* from the old one — leading digits, length,
character class. Nothing in the coupling map predicted this; only execution did.

### Milestone 1, closed

Same build figures as spike 02 — 209/209 targets, 13M, 123 libraries, five KF6
— so identity cost no dependencies.

- **Config isolation, unfenced.** Settings land in `~/.config/42hz/db/42hzrc`;
  `~/.config/easyeffects` unchanged across a *forced* write. `XDG_CONFIG_HOME`
  fencing is no longer required, which was the whole point. This took two
  attempts — see below.
- **Real application streams.** `mpv`, `ffplay` and `paplay` concurrently, all
  enumerated, none ignored, full chain confirmed to the physical device.
- **EQ LV2 URI validated both ways.** `para_equalizer_x32_lr` instantiates and
  links. Absent — forced with `bwrap --tmpfs` over `/usr/lib/lv2`, since the core
  only *appends* `LV2_PATH` and cannot be starved by environment alone — it
  reports `is not installed`, does not crash, and passes audio through. It also
  emits ~580 `port symbol not found` warnings, so the frontend must surface
  `packageInstalled` rather than expect anyone to read logs. A second LV2
  dependency surfaced: the spectrum wants `comp_delay_x2_stereo` for A/V sync and
  degrades gracefully without it.
- **Teardown with the virtual sink as default** — the case spike 02 explicitly
  refused to count as passing. Both `SIGTERM` and `SIGKILL`: nodes reaped,
  default fell back to the physical sink on its own, every stream migrated and
  kept playing. Restart over a stale lock and socket works.
- **Coexistence.** 42Hz and stock Easy Effects run simultaneously with disjoint
  node sets, and `42hz -q` quits only 42Hz. The socket rename was load-bearing:
  sharing `EasyEffectsServer` would have meant 42Hz's command line driving Easy
  Effects.

### Speaker tuning, and a loop worth knowing about

No Omarchy tuning exists on this host, so PipeWire's own `sink-eq6.conf`
filter-chain sink stood in, run as a client via `pipewire -c` — non-persistent,
no user config touched. Representative, since Omarchy's tuning is itself a
native filter-chain. 42Hz chains in front of it cleanly and the spectrum keeps
running.

**But** the stock example pins no target on its playback stream, so that stream
follows the default sink. Make a DSP virtual sink the default in that situation
and the graph closes a feedback loop through it. Stock Easy Effects forms the
identical loop, so this is inherited rather than ours — but it is a real failure
mode for any user whose tuning chain does not pin its output, and it argues that
42Hz should detect a cycle through its own sink instead of linking it.

Re-confirmed while there: `omarchy-audio-output-sink` still returns its own
argument, now with two filter layers it cannot walk instead of one.

### Authorship, and a history rewrite

**Decision: the application ID is settled as `io.github.chizzler.42Hz`**, after a
typo'd first pass. The `io.github.<handle>` form is a verifiable ownership claim
rather than decoration — AppStream uses it for uniqueness and Flathub enforces
that you control the corresponding repo — so it should name the account that
will actually host the project.

**Decision: commits are authored under a real name with a dedicated public
alias.** Real-name authorship is the dominant convention in the corner of FOSS
42Hz occupies: the kernel mandates it through the DCO, GPL and system-tooling
projects cluster near that norm, and EasyEffects itself is authored under a real
name and address. Using a handle for 42Hz's half would also sit oddly beside the
deliberate decision, made hours earlier, to *extend* rather than replace
upstream's copyright line. The alias keeps a private address out of an archive
that never forgets, without giving up attribution.

Note for whoever pushes first: **GitHub links commits to an account by email,
not by name.** The alias must be added and verified on the account, or these
commits appear unlinked — no avatar, no contribution graph — and correcting that
afterwards means another rewrite.

**The rewrite itself.** The private address was in all five existing commits.
Caught before any remote existed, which is the only point at which this is free;
after a push it means force-rewriting published history while forks and mirrors
keep the old values anyway.

The interesting cost was self-inflicted. This log records commit hashes, and
rewriting from the root changed all of them — orphaning four `**Commit:**`
references here *and* two commit subjects that name a hash. Both were
recoverable: `filter-branch` exposes a `map` function, so the subjects were
remapped inside the same pass, and the log itself took a follow-up commit,
which is the same backfill this project already does because a commit cannot
contain its own hash.

Worth keeping the convention — the hashes earn their place — but it now carries
a standing cost: **a history rewrite is never a single command in this repo.**

### Still open

Per-stream volume, mute and processing-inclusion *control* is milestone 3 —
enumeration is verified, acting on streams is not. Device churn was never
exercised; the headset stayed plugged in. 42Hz still credits only Wellington
Wallace in `KAboutData` and carries no AppStream `<developer>` element of its
own; both go with the attribution work in milestone 6.

---

## 2026-08-27 (afternoon) — Reproducible build, and first light

**Commit:** `b07e7b4`

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

**Commit:** `4f04024`

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

**Commits:** `3b90e6c`

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
