# Spike 03 — Identity reassignment, and the rest of milestone 1

**2026-08-28.** Base `v8.2.8`. Patch inventory: `spike/reduce-deps.py`, phase 2.

Spike 02 closed with the derived binary sharing every identifier with upstream,
so every development run had to fence `XDG_CONFIG_HOME`. This removes that
constraint and closes milestone 1.

## The identity surface

All of it derives from constants at the top of `reduce-deps.py`; nothing
downstream hard-codes a name.

| Surface | Was | Is | Where |
|---|---|---|---|
| Application ID | `com.github.wwmm.easyeffects` | `io.github.chizzler.42Hz` | `CMakeLists.txt`, `tags_app.hpp` |
| Executable | `easyeffects` | `42hz` | `src/CMakeLists.txt` (`OUTPUT_NAME`) |
| Config directory | `~/.config/easyeffects/db` | `~/.config/42hz/db` | `db_manager.cpp` |
| KConfig file paths | `easyeffects/db/*rc` | `42hz/db/*rc` | 38 × `contents/kcfg/*.kcfg` |
| Settings file | `easyeffectsrc` | `42hzrc` | `contents/kcfg/*.kcfg` |
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

The patch reached 17 files and 513 lines. The CMake *target* keeps its upstream
name — it is referenced ~30 times in `src/CMakeLists.txt` and by
`qt_add_qml_module`, and renaming it multiplies the inventory for no external
effect. Only `OUTPUT_NAME` is identity.

**Coupled pairs**, flagged at each site in the script:

- `plugin_base.cpp` builds filter node names from the prefix, and
  `pw_node_manager.cpp` recognises *its own* filters by testing that prefix. If
  they drift, 42Hz lists its own DSP filters as application streams.
- `test_signals.cpp` names its node with the same prefix, for the same reason.
- `APPLICATION_DOMAIN` is simultaneously the gettext catalogue name,
  `KAboutData::componentName`, `QCoreApplication::applicationName` and therefore
  the `AppConfigLocation` leaf — renaming it moved the presets directory for
  free.

**Deliberately not renamed.** `tags_plugin_name.hpp`'s `ee = "Easy Effects"` is a
plugin *vendor* label beside "Linux Studio Plugins", "MDA" and "x42"; the DSP it
labels really is upstream's work. Five `util::warning()` strings reading "…cannot
be handled by Easy Effects" appear only on `--debug` error paths, where naming
the origin is honest. The about-box copyright was *extended*, not replaced.
`PROJECT_VERSION` stays upstream's `8.2.8` until packaging in milestone 6.

## The defect the rename exposed

**`target.object` name-vs-serial resolution mis-parses digit-leading names.**

```cpp
if (util::str_to_num(target_object, serial)) { /* treat as serial */ }
else if (target_object != output_device.name && target_object != ee_sink_node.name) { ignore_node = true; }
```

`util::str_to_num` wraps `std::from_chars`, which reports success on a **partial**
parse — it sets `ptr` to the first unconsumed character and leaves `ec` empty,
and the helper checks only `ec`. So `"42hz_sink"` parsed as serial `42`, matched
no real node, and the stream was dropped from the model while staying perfectly
audible. `"easyeffects_sink"` never triggered it, not beginning with a digit.

Observed: `ffplay` sets `target.object = 42hz_sink` and was rejected —
`pw_node_manager.cpp:339` then `:673`, "has been removed". Control: stock
EasyEffects `v8.2.8`, same host, same invocation against `easyeffects_sink`,
accepted and linked. **The regression was ours.**

Fixed by treating `target.object` as a serial only when entirely digits — one
replacement covering the textually identical output and input blocks, since
`42hz_source` had the same defect. Deliberately **not** fixed in `str_to_num`:
18 call sites, several parsing Equalizer-APO captures where a trailing-unit
string such as `-3.0 dB` may rely on the lenient parse.

## Milestone 1 verification

Build after a clean cycle: 209/209 targets, 13M, 123 shared libraries, KF6 down
to five. Identity cost no dependencies.

**Configuration isolation — got wrong once, and the way it was wrong is the
useful part.** `db_manager.cpp` holds the only *obvious* config path, and
renaming it produced a build that created `~/.config/42hz/db/` and looked
correct. Every KConfig object writes to the path in its own
`<kcfgfile name="…"/>`, and all 38 `.kcfg` files hard-coded `easyeffects/db/*rc`,
so the new directory stayed empty while settings went on landing in the user's
real one. The first verification missed it because **KConfig only writes when a
setting changes**: a checksum taken minutes after startup showed the file
untouched and was reported as proof. It was proof of nothing — window geometry
leaked into the user's `easyeffectsrc` later the same session. *Verifying that a
write did not happen is worthless unless you first force a write.* The corrected
test starts the app, changes a setting through the CLI (`-b 1`), quits, then
compares. Run **unfenced**: `42hzrc` created and written,
`~/.config/easyeffects/` SHA-256 identical before and after.

**Real application streams.** `mpv`, `ffplay` and `paplay` concurrently to
`42hz_sink` as default: all enumerated with distinct `application.name` /
`media.name`, none ignored, full chain confirmed by `pw-link` through
`hz_soe_equalizer → hz_soe_spectrum → hz_soe_output_level` to the device.

**The EQ LV2 URI, both ways.** Present:
`http://lsp-plug.in/plugins/lv2/para_equalizer_x32_lr` from `lsp-plugins-lv2
1.2.33-2` instantiates as `hz_soe_equalizer` and links. Absent, forced by masking
`/usr/lib/lv2` with `bwrap --tmpfs` — the core hard-codes the standard LV2
directories and only *appends* `LV2_PATH`, so the environment variable alone
cannot hide a plugin: it reports `is not installed`, sets `packageInstalled`
false, does not crash, still creates the filter node so audio passes through, and
emits roughly **580 `port symbol not found` warnings**. A frontend must surface
`packageInstalled` rather than expect anyone to read logs. A second LV2
dependency surfaced: the spectrum uses `comp_delay_x2_stereo` for A/V sync and
degrades gracefully without it.

**Teardown with the virtual sink as default** — the case spike 02 refused to
count as passing. Under both `SIGTERM` and `SIGKILL`: process gone, all 42Hz
nodes reaped, default sink fell back to the headset on its own, every stream
migrated and kept playing. `SIGKILL` leaves a stale `42hz.lock` and `42HzServer`,
and restart over them succeeds.

**Coexistence.** 42Hz and stock EasyEffects ran simultaneously with fully
disjoint node sets, neither enumerating the other's filter nodes as application
streams, and `42hz -q` quit only 42Hz. The socket rename was load-bearing:
sharing `EasyEffectsServer` would have meant 42Hz's command line driving
EasyEffects.

**Behind a speaker-tuning filter chain.** No Omarchy tuning exists on this host,
so PipeWire's own `sink-eq6.conf` filter-chain sink stood in, run as a client via
`pipewire -c` — non-persistent, no user config touched, and representative since
Omarchy's tuning is itself a native filter chain. With its playback stream pinned
to the device, 42Hz chains in front cleanly and the spectrum keeps running.

**A hazard worth recording:** the stock `sink-eq6.conf` sets `node.passive` but
*no* target on its playback stream, so that stream follows the default sink. Make
a DSP virtual sink the default and the graph closes a feedback loop through it.
Stock EasyEffects forms the identical loop, so this is inherited — but it argues
that 42Hz should detect a cycle through its own sink rather than link it.

**The Omarchy volume resolver, re-confirmed.** With 42Hz and a tuning chain both
live, `omarchy-audio-output-sink` still returns its own argument, now with two
filter layers it cannot walk instead of one.

## Not covered by milestone 1

Per-stream volume, mute and processing-inclusion *control* (milestone 3); device
churn; a genuine Omarchy tuning profile rather than a stand-in; and 42Hz's own
authorship in `KAboutData` and AppStream (milestone 6).
