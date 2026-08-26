# 42Hz

42Hz is an ultra-minimal, Omarchy-native control surface derived from EasyEffects. It preserves EasyEffects' proven PipeWire, stream-routing, and DSP foundations while replacing its conventional interface with a responsive, spectrum-first Qt/QML frontend.

- **Public name:** 42Hz
- **Executable:** `42hz`
- **Working directory:** `~/Work/42Hz/`
- **Status:** early design and architecture

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

Measured coupling, the patch inventory, and build verification are recorded in `docs/spike-01-frontend-coupling.md`.

42Hz is a derived application, not a remote control for an installed EasyEffects executable. A release build contains the EasyEffects-derived core it was tested against; EasyEffects does not need to be installed or running.

## Window and interaction behavior

42Hz uses a conventional Wayland toplevel with a stable application ID such as `io.omarchy.42hz`. Hyprland owns placement and window management. 42Hz supplies a sensible initial size, remembers valid user geometry where appropriate, and remains fully usable when tiled, floated, resized, moved between monitors, or made fullscreen.

The layout responds to available space rather than switching among rigid product modes:

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
- change routing only after the replacement processing path is confirmed live;
- fall back to a valid physical endpoint if the graph fails or disappears.

42Hz should cooperate with Omarchy's EasyEffects-aware audio behavior. The feasibility spike must determine whether retaining compatible PipeWire properties is sufficient or whether Omarchy should also recognize a distinct 42Hz processing identity.

For the first release, the Arch package should conflict with EasyEffects so two processors do not compete for the same streams and virtual-device role. Safe coexistence can be considered later only after application IDs, PipeWire nodes, settings, presets, autostart, and routing ownership are isolated and tested.

## Effects and dependencies

The first supported effect is an output equalizer backed by one pinned LV2 implementation. On Arch Linux, the initial candidate is the LSP equalizer supplied by `lsp-plugins-lv2`; its package should be a required runtime dependency.

Packaging is not sufficient proof of capability. At runtime, 42Hz must discover the expected LV2 URI and successfully instantiate it before enabling the EQ editor. If EQ is unavailable, spectrum and mixing continue where possible, while the EQ action provides a precise diagnosis. Controls must never accept changes that cannot reach a live processing engine.

Future effects use the same capability-driven pattern and appear only when supported and requested.

## Omarchy theme integration

42Hz must fully and continuously adapt to the Omarchy theme selected by the user. Theme integration is functional behavior, not a one-time approximation at launch.

- Read the resolved palette from `~/.local/state/omarchy/current/theme/colors.toml`, and per-surface role overrides from the adjacent `shell.toml`, when available. A theme may ship `shell.toml` directly to override the generated file.
- Map the complete usable palette into semantic UI tokens, including background levels, foreground levels, muted state, accent, selection, warning, error, and spectrum colors.
- Follow the active Omarchy font and text scaling where exposed.
- Watch the atomically replaced current-theme state and apply changes live without restarting the application or audio graph.
- Use theme and font hooks only as optional low-latency notifications; file/state monitoring remains the reliable path.
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

## Command surface

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

Generally useful backend-decoupling fixes may be offered upstream, but they are not a prerequisite for progress.

## Milestones

1. **Repository and feasibility spike**  
   Pin the EasyEffects base, preserve licensing, map frontend/backend coupling, and prove access to live spectrum frames, application streams, PipeWire endpoints, and compatible Omarchy routing behavior. Build a 42Hz executable that owns its derived core and runs without the EasyEffects application installed. Validate the selected EQ LV2 URI and failure path.

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
