# 42Hz

42Hz is an ultra-minimal, Omarchy-native control surface derived from EasyEffects. It preserves EasyEffects' proven PipeWire, stream-routing, and DSP foundations while replacing its conventional interface with a responsive, spectrum-first Qt/QML frontend.

- **Public name:** 42Hz
- **Executable:** `42hz`
- **Working directory:** `~/Work/42Hz/`
- **Status:** milestone 1 complete. The derived core builds, runs under its own identity, and has been verified against real application streams, the EQ LV2 provider, default-sink routing, forced termination, and a speaker-tuning filter-chain. The 42Hz frontend does not exist yet. Current state is tracked in `docs/devlog.md`, not here.

### How to read this document

Sections carry different weight, and it matters which is which — much of this was
written before the derived core had ever been executed.

**Commitments** are settled and should be argued with rather than quietly
revised: the product principles, the initial scope, the architecture and its
single-process constraint, the licensing and upstream obligations, the
milestones, and the non-goals.

**Sketches** are provisional and expected to change on contact with a running
system. They are marked where they appear. A sketch is a record of current
intent, not a specification to build against; if implementation contradicts one,
the sketch is what gives way.

Findings graduate into this document from `docs/devlog.md` once durable. Evidence
lives in `docs/spike-*.md`.

## Product goal

42Hz provides concise access to the useful functionality of EasyEffects without dictating how the user arranges it. It is a normal Wayland application window that adapts to the geometry Hyprland and the user give it: a narrow spectrum strip, a compact application mixer, a larger effects editor, or anything between.

The interface follows the economy of BTOP rather than copying its appearance. Information density, layout, and disclosed controls respond to available space. Placement, tiling, floating, workspaces, and fullscreen remain the user's decision.

At its smallest useful size, 42Hz is a live spectrum that quietly confirms audio activity and invites interaction. As space or intent increases, it reveals application streams, routing state, bypass, and effect controls without permanent sidebars, card grids, fake hardware, or decorative chrome.

## Product principles

### Responsive, not prescribed

No layout is privileged. The interface must remain legible and useful across a broad range of window dimensions, reorganizing or progressively disclosing content rather than enforcing a fixed mode or location.

### Spectrum first

The live signal is the resting surface, not decoration around a settings panel. No signal, unavailable audio, and processing failure are distinct states and must be reported clearly.

### Mixing is central

42Hz must preserve EasyEffects' application-stream model. Users can identify active playback streams such as games, voice chat, browsers, and music players; adjust volume and mute state; and control whether each stream passes through processing. Input and output pipelines remain distinct.

### Reveal on intent

Stream controls are immediately reachable from the spectrum. EQ and other effects appear when selected and use direct graphical controls with precise values. Hiding an editor never interrupts its processing.

### Omarchy-native

The application behaves as an ordinary, well-mannered Hyprland client and continuously reflects the active Omarchy theme. It does not install a shell plugin, require a daemon, prescribe window rules, or modify user or packaged Omarchy configuration.

### Backend stability over reinvention

Reuse EasyEffects' PipeWire integration, processing pipelines, stream models, DSP hosting, presets, state handling, and spectrum production wherever practical. 42Hz is a focused frontend over a minimally changed derived core, not a new audio engine.

## Initial scope

The first useful release includes:

- a responsive live spectrum analyzer;
- an active application-stream mixer with volume, mute, and processing inclusion;
- clear input/output pipeline and endpoint state;
- global processing bypass;
- an on-demand output equalizer;
- keyboard and pointer navigation at every supported size;
- live synchronization with the complete active Omarchy palette and typography;
- explicit capability and recovery feedback;
- one-command Arch installation.

Preset management, input effects editing, the complete EasyEffects effect catalogue, advanced routing, and extensive per-plugin configuration may follow after the core interaction proves reliable. The architecture must preserve a path to them without exposing unfinished controls.

## Architecture

42Hz is initially one application process containing:

- **EasyEffects-derived core:** PipeWire session integration, stream discovery and routing, input/output pipelines, DSP/LV2 hosting, state, presets, and spectrum production.
- **42Hz frontend:** responsive window lifecycle, spectrum rendering, stream mixer, effect editors, keyboard/pointer interaction, and Omarchy theme adapter.
- **Internal facade:** models and commands for streams, endpoints, pipelines, spectrum frames, effects, EQ, bypass, capabilities, and errors. UI code must not depend directly on upstream EasyEffects screens.

One process and one package are preferred until measured reliability or multiple independent clients justify a backend service. The internal facade must make a later split possible without designing an IPC protocol prematurely.

### Upstream baseline

The derivation rests on the following properties of EasyEffects `v8.2.8`, verified by build:

- Upstream is already a Qt6/QML application. The derivation is a frontend replacement within one toolkit, not a port.
- KDE/Kirigami coupling is confined to the application entry point and the KDE colour-scheme adapter. The PipeWire, DSP, routing, preset, and state layers carry no KDE UI dependency and require no modification.
- The spectrum is already exposed to QML as a pull-based singleton API delivering points pre-resampled to a configurable point count. Responsive resampling is therefore a settings binding, not new DSP code.
- No upstream QML is reusable. 42Hz supplies its entire frontend, which dominates the effort in milestones 2-4.
- Spectrum delivery to a plain-QtQuick frontend is verified by execution, not only by inspection: a live signal renders through the derived core with no Kirigami, QtGraphs, or KDE style present (`docs/spike-02-first-run.md`).
- A release build reports nothing. Upstream includes KDE's `KDECompilerSettings`, which defines `QT_NO_DEBUG_OUTPUT` for Release, so `console.log` and QML's own diagnostics are compiled out — and QML resolves undefined identifiers at runtime, not at build time. A Release build therefore fails silently by construction, and cannot be verified from its own logs. Diagnose in a Debug build, or observe the running process from outside it.
- Identity reassignment is safe against the core, but the *shape* of a new name is not free. The core resolves a client's `target.object` by attempting a numeric parse first, and its `str_to_num` helper accepts a partial `std::from_chars` result — so a node name beginning with digits is misread as a serial and the stream is silently dropped from the model while remaining audible. `42hz_sink` triggered this; `easyeffects_sink` never could. Fixed in the patch inventory, and confirmed by control against stock EasyEffects (`docs/spike-03-identity.md`).

Measured coupling, the patch inventory, and build verification are recorded in `docs/spike-01-frontend-coupling.md`. First execution of the derived core — live spectrum delivery, graph topology, routing behaviour, and teardown — is recorded in `docs/spike-02-first-run.md`.

42Hz is a derived application, not a remote control for an installed EasyEffects executable. A release build contains the EasyEffects-derived core it was tested against; EasyEffects does not need to be installed or running.

## Window and interaction behavior

42Hz uses a conventional Wayland toplevel with a stable application ID. Identity has been reassigned across every surface the derived core inherited — application ID, executable, config directory *and the 38 KConfig file paths that actually decide where settings land*, presets directory, single-instance lock and socket, logging category, virtual node names, filter node prefix, node groups, media classes, desktop entry, metainfo, icons, and portal token — and is now driven by constants at the top of `spike/reduce-deps.py`. Development runs no longer need to isolate `XDG_CONFIG_HOME`, verified unfenced after a *forced* settings write; verifying that no write occurred is meaningless unless a write is provoked first, since KConfig only persists on change. The application ID is `io.github.chizzler.42Hz`, which is also the Wayland class any Hyprland window rule matches on. `io.omarchy.*` was rejected because the README disclaims Omarchy affiliation and a reverse-DNS ID should name a domain its author controls. Its final component begins with a digit, which desktop entries, AppStream and Wayland `app_id` all permit but Flatpak application IDs and D-Bus bus names do not; neither constrains 42Hz, which registers no D-Bus name and targets an Arch package, but a Flatpak would need a different ID. Hyprland owns placement and window management. 42Hz supplies a sensible initial size, remembers valid user geometry where appropriate, and remains fully usable when tiled, floated, resized, moved between monitors, or made fullscreen.

The layout responds to available space rather than switching among rigid product modes. The three tiers below are a *sketch* — useful names for regions of a continuum, not breakpoints to implement:

- **Minimal:** spectrum, signal state, and essential processing status.
- **Compact:** spectrum plus active application streams and concise mix controls.
- **Expanded:** stream mixer, pipeline/effect navigation, and the selected effect editor.

Clicking or invoking a keyboard action reveals the next relevant control. Escape dismisses transient controls without stopping audio. A second launch presents the existing instance.

42Hz may ship optional example Hyprland rules for common arrangements, but installation never applies them automatically.

## Stream and routing model

Preserve EasyEffects semantics rather than reducing audio to a single ambiguous "source" selector:

- enumerate live playback application streams;
- expose per-stream volume and mute when supported;
- show and control whether a stream is processed;
- keep input and output processing pipelines separate;
- distinguish virtual processing nodes from effective physical endpoints;
- preserve Omarchy speaker-tuning chains;
- never move a DSP filter's own stream as if it were an application;
- refuse to link a stream whose path returns to 42Hz's own sink;
- change routing only after the replacement processing path is confirmed live;
- fall back to a valid physical endpoint if the graph fails or disappears.

42Hz chains cleanly in front of a speaker-tuning filter-chain sink, verified in spike 03 against a representative stand-in. One hazard is inherited: a filter-chain sink whose playback stream pins no target follows the default sink, so making a DSP virtual sink the default closes a feedback loop through it. Stock EasyEffects behaves identically, but 42Hz should detect a cycle through its own sink rather than link it — hence the constraint above.

Omarchy's speaker tuning is a **native PipeWire filter-chain**, not an EasyEffects preset. `/usr/share/omarchy/default/audio/tunings/` ships `filter-chain.conf` files fitted by measurement from an EasyEffects profile, redistributing no upstream asset. Conflicting with the EasyEffects package therefore costs Omarchy's tuning nothing. The coexistence problem is 42Hz chained behind a filter-chain sink — an ordering and endpoint-resolution question — not 42Hz versus EasyEffects.

### DSP-sink volume resolution

Omarchy resolves a selected DSP sink to the physical sink whose volume it really controls, so that volume keys, the output switcher, and the shell audio panel act on the endpoint rather than on the level going *into* processing. `/usr/bin/omarchy-audio-output-sink` implements this by walking `pactl list sink-inputs`.

**That walk cannot see the EasyEffects-derived output leg.** Measured in spike 02: the node feeding the physical device is `ee_soe_output_level`, a PipeWire filter node carrying no `media.class`, linked port to port. It is never enumerated as a sink-input, so the resolver falls through and returns the DSP sink itself.

This is a resolver limitation, not an identity-negotiation problem, and no choice of node naming avoids it. 42Hz must resolve it one of three ways — presenting a real sink-input for the output leg (a core modification), extending the resolver to walk PipeWire links rather than PulseAudio sink-inputs (an upstream Omarchy contribution that also fixes EasyEffects and tuning chains), or accepting the fallback and its consequences. The second is preferred. Evidence and trade-offs are in `docs/spike-02-first-run.md`.

For the first release, the Arch package should conflict with EasyEffects so two processors do not compete for the same streams and virtual-device role. Safe coexistence can be considered later only after application IDs, PipeWire nodes, settings, presets, autostart, and routing ownership are isolated and tested.

## Effects and dependencies

The first supported effect is an output equalizer backed by one pinned LV2 implementation. On Arch Linux this is the LSP equalizer `http://lsp-plug.in/plugins/lv2/para_equalizer_x32_lr`, supplied by `lsp-plugins-lv2`; its package is a required runtime dependency. The URI is verified to instantiate, and its absence is verified to be survivable: the core reports `packageInstalled` false, does not crash, and passes audio through — while emitting several hundred port warnings, so the frontend must surface the capability flag rather than rely on logs. The spectrum separately uses `comp_delay_x2_stereo` from the same package for A/V sync compensation and degrades gracefully without it.

Packaging is not sufficient proof of capability. At runtime, 42Hz must discover the expected LV2 URI and successfully instantiate it before enabling the EQ editor. If EQ is unavailable, spectrum and mixing continue where possible, while the EQ action provides a precise diagnosis. Controls must never accept changes that cannot reach a live processing engine.

Future effects use the same capability-driven pattern and appear only when supported and requested.

## Omarchy theme integration

42Hz must fully and continuously adapt to the Omarchy theme selected by the user. Theme integration is functional behavior, not a one-time approximation at launch.

- Read the resolved palette from `~/.local/state/omarchy/current/theme/colors.toml`, and per-surface role overrides from the adjacent `shell.toml`, when available. A theme may ship `shell.toml` directly to override the generated file.
- Layer `~/.config/omarchy/shell.toml` on top of both. It is a machine-level override that survives theme switches and is where `omarchy display text size` writes `[font] base-size`, so its keys must win over the theme's.
- Map the complete usable palette into semantic UI tokens, including background levels, foreground levels, muted state, accent, selection, warning, error, and spectrum colors.
- Follow the active Omarchy font and text scaling where exposed.
- Watch the atomically replaced current-theme state and apply changes live without restarting the application or audio graph. **Watch the parent directory, not the theme directory or its files.** `omarchy-theme-set` performs `rm -rf current/theme` followed by `mv next-theme current/theme`, so a watch on `theme/` or on `colors.toml` is dropped by the swap and never recovers even though a file reappears at the same path moments later. `~/.local/state/omarchy/current/` outlives the swap and is the only durable signal. Re-establish the finer-grained watches after every load, and coalesce: one switch produces a burst of events.
- Use theme and font hooks only as optional low-latency notifications; file/state monitoring remains the reliable path. Omarchy's own shell is notified through Quickshell IPC, which 42Hz cannot receive, so this is not a preference but the only available route.
- Follow the font family Omarchy manages system-wide, which is the fontconfig alias `monospace` rather than a concrete family. Naming a resolved family defeats `omarchy font set`.
- Derive contrast-safe fallbacks when a theme omits a value or produces an illegible pairing.
- Start with built-in fallback tokens if Omarchy state is unavailable.
- Keep all 42Hz mappings inside the application; never edit `/usr/share/omarchy/`, stock themes, or user configuration.

Omarchy's own shell is a Quickshell (QML) application, so 42Hz and the desktop shell share a toolkit. `/usr/share/omarchy/shell/Commons/Color.qml` is the reference implementation for resolving `colors.toml` and `shell.toml` into surface roles, including the `-alpha` companion keys and gradient-token handling.

Theme fidelity includes light and dark themes, but signal clarity, focus visibility, and readable contrast take priority over literal color reuse.

## Runtime states and recovery

Detect and report capabilities independently:

- **Application ready:** the binary and derived core started.
- **Audio service ready:** PipeWire and required session interfaces are reachable.
- **Processing ready:** virtual nodes and the processing graph are live.
- **EQ ready:** the supported LV2 provider was discovered and instantiated.
- **Omarchy theme ready:** resolved theme and font state were loaded.

Startup proceeds in stages:

1. Acquire the single-instance identity and create the responsive window with safe fallback tokens.
2. Resolve and begin watching Omarchy theme state.
3. Connect to PipeWire and enumerate streams, devices, virtual nodes, and speaker tuning.
4. Discover required DSP capabilities.
5. Create the processing graph without changing existing defaults prematurely.
6. Reconcile streams and endpoints through the Omarchy-aware routing policy.
7. Start spectrum delivery and expose only controls backed by live capabilities.

The application should recover from PipeWire restarts and device churn without a UI restart. It must never leave the default route pointing at a dead 42Hz node. Tests must cover forced termination as well as graceful shutdown.

Partially verified in spike 02: under both `SIGTERM` and `SIGKILL`, PipeWire reaped the virtual nodes and the default sink was unchanged. That run never made the virtual sink the default, so it did not exercise the case the requirement exists for — killing the process while the default route points *at* it. That case remains untested and is the one that matters.

## Command surface

*Sketch.* The shape below is provisional: it was drafted before any of it existed, and the split between what the running process owns and what a separate control binary owns is unsettled. Treat it as a statement of the interaction the command surface should support, not as a committed argument grammar.

Provide a small stable command interface for keybindings, scripting, and diagnostics:

```text
42hz                         launch or present the existing instance
42hzctl status --json       capabilities, streams, routing, and processing state
42hzctl bypass toggle       toggle the live processing path
42hzctl eq show             present the EQ editor
42hzctl stream list         list active application streams
42hzctl stream set <id> ... change supported stream state
42hzctl theme reload        reload resolved Omarchy theme state
42hzctl doctor              explain missing services, plugins, and graph failures
```

Commands return meaningful exit statuses and machine-readable errors. The first release may require the 42Hz process to remain running while processing is enabled; a separate daemon is not implied.

## Packaging and upstream strategy

Ship one reproducible Arch package containing the application, desktop entry, symbolic icon, AppStream metadata, licenses, and required runtime dependencies. Installation must not require an Omarchy plugin, manual hook, service activation, or configuration edit.

42Hz is a GPL-compliant EasyEffects derivative. It must:

- retain applicable licensing, copyright notices, and source-availability obligations;
- credit EasyEffects and identify derived components;
- document meaningful modifications and the exact upstream base revision;
- use new modules and resources where possible;
- minimize unavoidable upstream edits and maintain a small patch inventory;
- test the boundary between the derived core and 42Hz frontend;
- avoid implying official affiliation with EasyEffects or Omarchy;
- track and integrate upstream changes at planned intervals.

Contributions are authored under a real name with a dedicated public contact address, matching the convention of the GPL/system-tooling projects 42Hz sits among and of EasyEffects itself. This is not ceremony: the licensing decision recorded for 2026-08-26 turns on relicensing requiring agreement from every contributor, which is materially easier to obtain — or to prove — from identifiable ones. 42Hz does not yet credit its own author in `KAboutData` or in AppStream `<developer>` data; both belong with the attribution work in milestone 6.

Generally useful backend-decoupling fixes may be offered upstream, but they are not a prerequisite for progress.

### Upstream working copy

The repository does not vendor EasyEffects source. `spike/fetch.sh` fetches and
verifies the pinned base into `upstream/`; `spike/reduce-deps.py` applies the
complete patch inventory to it. The build root is the repository itself: the
top-level `CMakeLists.txt` adds the patched core and then `frontend/`, so a
clean checkout reaches a built binary in four commands.

42Hz's own source is tracked in `frontend/` and is never copied into the
disposable tree — the file you edit is the file that compiles. Its QML is a
**separate Qt module** (`hz.ui`) linked into the core's target as a plugin,
rather than files added to the core's own module (`ee.ui`, which after patching
registers C++ types and ships no QML). That separation is forced by Qt, which
finalizes a QML module at the end of the directory scope that declared it: QML
contributed from `frontend/` to the core's module is embedded in the binary but
never reaches its `qmldir`, producing a clean build that fails at load. The
split is also useful — every `import ee.ui` in 42Hz QML is a direct reach into
upstream, and greppable as such.

The base is pinned three ways: the upstream commit, a checksum of the downloaded
archive, and a checksum of the extracted file tree. The last of these exists
because GitHub generates release archives on demand and does not guarantee they
are byte-stable, so a repackaged archive must be distinguishable from changed
source. Changed packaging warns and continues; changed source refuses to build.

**The extracted tree is disposable.** Re-running `fetch.sh` deletes and
re-extracts it without prompting, and takes any build directory inside it along.

This is the mechanism that makes the small-patch-inventory obligation
enforceable rather than aspirational. A modification that is not in
`reduce-deps.py` does not survive the next fetch, so no upstream edit can
quietly become load-bearing, and the patch inventory cannot drift out of step
with what is actually being built. Discarding the build directory is part of the
guarantee, not a cost of it: a rebuilt source tree deserves a fresh build, and a
build reflecting a source state that no longer exists is precisely the
inconsistency this arrangement prevents.

Consequently:

- Never treat a hand edit under `upstream/` as done. Prototype there freely, then
  fold the change into `reduce-deps.py` and re-run the cycle before relying on it.
- Every change to the derived core is a change to the patch script. Reviewing
  `reduce-deps.py` is reviewing the entire delta against upstream.
- A version bump is a change to the pinned values in `fetch.sh` followed by
  re-verification of each patch entry against the new base.

## Milestones

1. **Repository and feasibility spike** — **complete (2026-08-28)**  
   Pin the EasyEffects base, preserve licensing, map frontend/backend coupling, and prove access to live spectrum frames, application streams, PipeWire endpoints, and compatible Omarchy routing behavior. Build a 42Hz executable that owns its derived core and runs without the EasyEffects application installed. Validate the selected EQ LV2 URI and failure path.
   Identity reassignment was folded in from milestone 2, since first execution showed it gated safe development runs. Not covered here and deferred to their own milestones: per-stream volume, mute and processing-inclusion *control* (milestone 3), device churn, and a genuine Omarchy tuning profile as opposed to a stand-in.

2. **Responsive spectrum shell**  
   Build a normal themed Wayland window whose spectrum and essential state remain useful across representative tiled, floating, narrow, wide, and fullscreen geometries. Establish stable application identity, single-instance presentation, keyboard navigation, and capability-specific empty states.

3. **Application mixer**  
   Expose live playback streams with supported volume, mute, and processing-inclusion controls. Verify game, voice-chat, browser, and music streams; device churn; speaker tuning; virtual sinks; and safe recovery after graph failure.

4. **On-demand EQ**  
   Add a responsive output equalizer backed by the validated LV2 provider. Verify that resizing or hiding the editor never interrupts audio and that missing-plugin behavior remains honest and recoverable.

5. **Omarchy integration hardening**  
   Validate live palette, font, scale, light/dark, and contrast behavior across representative Omarchy themes. Complete diagnostics and command controls, test PipeWire recovery and forced termination, and produce the reproducible Arch package.

6. **First release candidate**  
   Complete attribution, limitations, build documentation, integration tests, and the upstream update procedure; then publish the initial source release.

## Non-goals for the first release

- reproducing every EasyEffects screen or effect;
- inventing a new audio engine or PipeWire session manager;
- requiring an Omarchy shell plugin or persistent backend daemon;
- prescribing where or how large the application window should be;
- silently modifying Hyprland or Omarchy configuration;
- adding decoration that does not improve signal reading, mixing, navigation, or state awareness.

## Working test

42Hz is on course when a user can arrange it however they prefer, immediately understand active audio, mix application streams, bypass processing, and reach EQ in one brief interaction—while the entire interface remains visually coherent with the currently selected Omarchy theme.
