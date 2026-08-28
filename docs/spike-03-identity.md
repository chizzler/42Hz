# Spike 03 — Identity reassignment, and the rest of milestone 1

**Date:** 2026-08-28
**Base:** EasyEffects `v8.2.8` (`6d9b1220d3dcebb154ba759a05600662bc0af549`)
**Patch inventory:** `spike/reduce-deps.py`, phase 2

Spike 02 established that the derived core ran and delivered a live spectrum,
and closed with the observation that the binary still shared *every* identifier
with upstream — so every development run had to fence `XDG_CONFIG_HOME` or it
would read and write the user's real EasyEffects settings. This spike removes
that constraint and then executes the milestone-1 checks that were still open.

---

## 1. The identity surface

Everything the derived core inherited that names it to the user, the desktop, or
the PipeWire graph. All of it now derives from constants at the top of
`spike/reduce-deps.py`; nothing downstream hard-codes a name.

| Surface | Was | Is | Where |
|---|---|---|---|
| Application ID | `com.github.wwmm.easyeffects` | `io.github.chizzler.42Hz` | `CMakeLists.txt`, `tags_app.hpp` |
| Executable | `easyeffects` | `42hz` | `src/CMakeLists.txt` (`OUTPUT_NAME`) |
| Config / KConfig db | `~/.config/easyeffects/db` | `~/.config/42hz/db` | `db_manager.cpp` |
| Presets dir | `~/.config/easyeffects` | `~/.config/42hz` | follows `APPLICATION_DOMAIN` |
| Single-instance lock | `$XDG_RUNTIME_DIR/easyeffects.lock` | `.../42hz.lock` | `util.cpp` |
| Single-instance socket | `$XDG_RUNTIME_DIR/EasyEffectsServer` | `.../42HzServer` | `tags_local_server.hpp` |
| Logging category | `easyeffects` | `42hz` | `util.cpp`, `main.cpp`, `command_line_parser.cpp` |
| Virtual sink / source | `easyeffects_sink` / `_source` | `42hz_sink` / `42hz_source` | `tags_pipewire.hpp` |
| Sink / source description | `Easy Effects Sink` | `42Hz Sink` | `pw_node_manager.cpp` |
| DSP filter node prefix | `ee_` | `hz_` | `plugin_base.cpp` |
| Filter self-recognition | `starts_with("ee_")` | `starts_with("hz_")` | `pw_node_manager.cpp` |
| Node groups | `ee_sink_group` | `hz_sink_group` | `plugin_base.cpp`, `pw_node_manager.cpp` |
| Test-tone node | `ee_test_signals` | `hz_test_signals` | `test_signals.cpp` |
| Internal media class | `EE/Audio/Sink` | `42Hz/Audio/Sink` | `tags_pipewire.hpp` |
| Desktop / metainfo / icons | `com.github.wwmm.easyeffects.*` | `${APPLICATION_ID}.*` | `src/contents/` |
| Portal autostart token | `EasyEffects-Autostart` | `42Hz-Autostart` | `autostart.cpp` |

The patch now touches 17 files and runs 513 lines. The CMake *target* is still
named `easyeffects` — it is referenced roughly thirty times in `src/CMakeLists.txt`
and by `qt_add_qml_module`, and renaming it would multiply the inventory for no
external effect. Only `OUTPUT_NAME` is identity.

### Coupled pairs

Three of these must move together, and the script says so at each site:

- `plugin_base.cpp` builds filter node names from the prefix;
  `pw_node_manager.cpp` recognises *its own* filters by testing that prefix. If
  they drift, 42Hz lists its own DSP filters as application streams.
- `test_signals.cpp` names its node with the same prefix, for the same reason.
- `APPLICATION_DOMAIN` is simultaneously the gettext catalogue name, KAboutData's
  `componentName`, `QCoreApplication::applicationName`, and therefore the
  `AppConfigLocation` leaf. Renaming it moved the presets directory for free.

### Deliberately not renamed

- **`tags_plugin_name.hpp`** — `ee` = `"Easy Effects"` is a plugin *vendor*
  label shown beside "Linux Studio Plugins", "MDA" and "x42". The DSP it labels
  really is Easy Effects' work; relabelling it "42Hz" would misattribute
  someone else's code.
- **`util::warning()` diagnostics** — five strings read "… cannot be handled by
  Easy Effects". They appear only on error paths under `--debug`, and naming the
  derived core's origin there is honest.
- **The about-box copyright** was *extended*, not replaced:
  `© 2017-2026 Wellington Wallace (Easy Effects) · 42Hz frontend © 2026 42Hz
  contributors`. Dropping the original notice would violate the GPL.
- **`PROJECT_VERSION`** is still upstream's `8.2.8`. Versioning 42Hz separately
  belongs with packaging, in milestone 6.

### The vendor prefix, settled

`VENDOR` is `io.github.chizzler`, giving `io.github.chizzler.42Hz`. `project.md`
offered `io.omarchy.42hz` as an example, but the README explicitly disclaims
Omarchy affiliation and a reverse-DNS ID should name a domain its author
controls. Verified live on all four surfaces it reaches: the binary, the
installed asset names, the Wayland class Hyprland reports, and the PipeWire
`application.id` stamped on every 42Hz node.

The final component begins with a digit. Desktop entries, AppStream and Wayland
`app_id` permit this; **Flatpak application IDs and D-Bus bus names do not** —
each of their components must begin with a letter or underscore. Neither
constrains 42Hz today: it registers no D-Bus name (single-instance runs over a
local socket, see `tags_local_server.hpp`) and targets an Arch package. A
Flatpak would need a different ID. Recorded because this is the second
digit-leading-name hazard this project has hit, after `42hz_sink`.

The upstream artwork
was renamed to the new ID but is still upstream's — replacing it is milestone 6,
as is real appstream data. Upstream's 65K metainfo, which is entirely Easy
Effects release notes, was replaced with a short honest stub rather than shipped
under the 42Hz application ID.

---

## 2. The defect the rename exposed

**`target.object` name-vs-serial resolution mis-parses digit-leading names.**

A client may pin its output with the PipeWire property `target.object`, whose
value is, per PipeWire's own header, "a name or serial number". The core decides
which by attempting a numeric parse first:

```cpp
if (util::str_to_num(target_object, serial)) { /* treat as serial */ }
else if (target_object != output_device.name && target_object != ee_sink_node.name) { ignore_node = true; }
```

`util::str_to_num` wraps `std::from_chars`, which reports success on a **partial**
parse — it sets `ptr` to the first unconsumed character and leaves `ec` empty.
The helper checks only `ec`. So `"42hz_sink"` parses as serial `42`, matches no
real node, and the stream is dropped from the model while remaining perfectly
audible.

`"easyeffects_sink"` never triggered this because it does not begin with a digit.

**Observed.** `ffplay` sets `target.object = 42hz_sink`. Against the renamed
build it was rejected:

```
pw_node_manager.cpp:339  The output stream ffplay does not have as target
                         the same output device used as EE: alsa_output...Razer...
pw_node_manager.cpp:673  Stream/Output/Audio 130 ffplay has been removed
```

**Control.** Stock EasyEffects `v8.2.8`, same host, same `ffplay` invocation,
targeting `easyeffects_sink`: accepted and linked. The regression was ours.

**Fix.** Treat `target.object` as a serial only when it is entirely digits. One
replacement covers both the output block (target = sink) and the input block
(target = source), which are textually identical — `42hz_source` had the same
defect on the capture side.

**Scope.** The narrow fix was preferred over correcting `str_to_num` itself.
There are 18 call sites; several parse regex captures out of Equalizer-APO
config, where a trailing-unit string such as `-3.0 dB` may currently rely on the
lenient parse. Tightening the shared helper is the better long-term fix and is
worth reporting upstream, but it is not a change to make blind.

This is the second inherited-or-introduced question this project has had to
answer by experiment rather than inspection, and the second time the answer
mattered. The first (`omarchy-audio-output-sink`) was inherited; this one was
not.

---

## 3. Milestone 1 verification

Build, after a clean `fetch.sh` → `reduce-deps.py` → `cmake` → `ninja` cycle:
209/209 targets, 13M binary, 123 shared libraries, KF6 down to `ConfigCore`,
`ConfigGui`, `CoreAddons`, `I18n`, `I18nQml`. Unchanged from spike 02 — the
identity work cost no dependencies.

### Configuration isolation — the reason for this spike

Run **unfenced**, with no `XDG_CONFIG_HOME` redirection:

- `~/.config/42hz/db/` created.
- `$XDG_RUNTIME_DIR/42hz.lock` and `42HzServer` created, alongside pre-existing
  `easyeffects.lock` and `EasyEffectsServer` from earlier sessions.
- `~/.config/easyeffects/` SHA-256 identical before and after — and again after
  every subsequent run in this session.

The development fence is no longer required.

### Application streams against real clients

Three concurrent real clients — `mpv`, `ffplay`, `paplay` — playing to
`42hz_sink` as the default sink. All three enumerated by the core with distinct
`application.name` / `media.name`; zero streams ignored. Full output chain
confirmed by `pw-link`:

```
mpv / ffplay / paplay
  → 42hz_sink
  → hz_soe_equalizer → hz_soe_spectrum → hz_soe_output_level
  → alsa_output...Razer BlackShark V2 Pro
```

Chromium and Steam were running throughout and were deliberately not driven.

### The EQ LV2 URI and its failure path

**Present.** `http://lsp-plug.in/plugins/lv2/para_equalizer_x32_lr`, provided by
`lsp-plugins-lv2 1.2.33-2`, instantiates as `hz_soe_equalizer` and links into the
graph. The URI in `equalizer.cpp` is valid on a current Arch host.

**Absent.** Forced by masking `/usr/lib/lv2` with a `bwrap --tmpfs` — the core
hard-codes the standard LV2 directories and only *appends* `LV2_PATH`, so the
environment variable alone cannot hide a plugin.

- Reported honestly: `soe: …para_equalizer_x32_lr is not installed`,
  `packageInstalled` false.
- No crash. The process ran normally and the filter node was still created, so
  audio passes through.
- The failure is **noisy**: roughly 580 `port symbol not found` warnings per
  absent plugin, because every port is still set. Survivable, but a 42Hz
  frontend must surface `packageInstalled` rather than expect anyone to read
  logs.

A second LV2 dependency surfaced: the spectrum uses
`http://lsp-plug.in/plugins/lv2/comp_delay_x2_stereo` for A/V sync compensation
and degrades gracefully without it —
`spectrum will not have A/V sync compensation`.

### Routing with the virtual sink as default, and teardown

The case spike 02 recorded as untested. With `42hz_sink` as the default sink and
three streams playing:

| | `SIGTERM` | `SIGKILL` |
|---|---|---|
| Process gone | yes | yes |
| 42Hz nodes reaped | all, 0 remaining | all, 0 remaining |
| Default sink | fell back to the Razer | fell back to the Razer |
| Streams | all migrated, still playing | all migrated, still playing |
| Runtime leftovers | none | stale `42hz.lock`, `42HzServer` |

Restart after `SIGKILL`, with the stale lock and socket present, succeeded.

### Coexistence with stock EasyEffects

Both ran simultaneously with fully disjoint node sets:

```
42Hz:        42hz_sink 42hz_source hz_sie_output_level hz_sie_spectrum
             hz_soe_equalizer hz_soe_output_level hz_soe_spectrum hz_test_signals
EasyEffects: easyeffects_sink easyeffects_source ee_sie_output_level ee_sie_spectrum
             ee_soe_output_level ee_soe_spectrum ee_test_signals
```

`42hz -q` quit 42Hz and left EasyEffects running — the socket rename holds.
Neither enumerated the other's filter nodes as application streams.

### Behind a speaker-tuning filter-chain

No Omarchy speaker tuning exists on this host, so a stand-in was used:
PipeWire's own `sink-eq6.conf` filter-chain sink, run as a client via
`pipewire -c` against the live daemon — non-persistent, no user config touched.
This is representative: Omarchy's tuning is itself a native PipeWire
filter-chain.

With the tuning chain's playback stream pinned to the physical device, 42Hz
chains in front of it cleanly and the spectrum keeps running:

```
mpv → 42hz_sink → hz_soe_equalizer → hz_soe_spectrum → hz_soe_output_level
    → effect_input.eq6 → [tuning] → effect_output.eq6 → Razer
```

**A hazard worth recording.** The stock `sink-eq6.conf` sets `node.passive` but
*no* target on its playback stream, so that stream follows the default sink.
Make a DSP virtual sink the default in that situation and the graph closes a
feedback loop:

```
42hz_sink → 42Hz DSP → effect_input.eq6 → effect_output.eq6 → 42hz_sink → …
```

Stock EasyEffects forms the identical loop under the same conditions, so this is
inherited, not a 42Hz defect — but it is a real failure mode for any user whose
tuning chain does not pin its output, and it argues that 42Hz should detect a
cycle through its own sink rather than link it.

### The Omarchy volume resolver, re-confirmed

With 42Hz and a tuning chain both live and `42hz_sink` as default,
`omarchy-audio-output-sink` returns `42hz_sink` — its own argument — exactly the
failure spike 02 documented. The chained configuration makes it worse: there are
now two filter layers it cannot walk. Unchanged in cause and still not 42Hz's
code to fix.

---

## 4. What milestone 1 still does not cover

- Per-stream volume, mute, and processing-inclusion *control*. Enumeration is
  verified; acting on streams is milestone 3.
- Device churn — the headset was never unplugged mid-run.
- A genuine Omarchy speaker-tuning profile, as opposed to a representative
  stand-in.
- The `VENDOR` placeholder, which must be settled before anything is packaged
  or installed.
