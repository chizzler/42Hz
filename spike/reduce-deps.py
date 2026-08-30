#!/usr/bin/env python3
"""Apply the 42Hz patch inventory to an extracted EasyEffects tree.

    ./spike/reduce-deps.py upstream/easyeffects-8.2.8

This is the whole delta against upstream, in two phases:

  1. DEPENDENCY REDUCTION -- remove the Kirigami/KDE-UI frontend and the
     QtGraphs dependency, leaving a plain-QtQuick placeholder.

  2. IDENTITY REASSIGNMENT -- give the derived binary its own application ID,
     config directory, lock file, logging category, PipeWire node names, and
     filter-node prefix, so it neither reads nor collides with an installed
     Easy Effects. See IDENTITY SURFACE below.

Neither phase touches the PipeWire session, DSP, routing, preset, or state
logic. Keep it small -- every entry here is an upstream edit that must be
re-verified on each version bump.

The edit is DESTRUCTIVE and IN-PLACE: it deletes files and rewrites others.
Point it at a freshly extracted tree, never at one you have hand-edited.
See docs/spike-01-frontend-coupling.md for the rationale behind phase 1 and
docs/spike-03-identity.md for phase 2.
"""

import re, pathlib, sys

# ---------------------------------------------------------------------------
# IDENTITY SURFACE
#
# Every user-visible or system-visible name the derived core inherits from
# Easy Effects. Changing a value here is the whole rename; nothing below
# hard-codes these strings.
#
# VENDOR is the reverse-DNS prefix of the application ID, and therefore also the
# desktop-entry name, the icon name, the PipeWire app.id, and the Wayland class
# that any Hyprland window rule will match on.
#
# NOTE: APP_ID's final component ("42Hz") begins with a digit. Desktop entries,
# AppStream and Wayland app_ids allow this; Flatpak application IDs and D-Bus
# bus names do NOT -- each of their components must begin with a letter or
# underscore. Neither is in play: 42Hz registers no D-Bus name (single-instance
# runs over a local socket) and targets an Arch package. A Flatpak would need a
# different ID.
# ---------------------------------------------------------------------------

VENDOR      = "io.github.chizzler"       # reverse-DNS prefix; owns the app ID
APP_NAME    = "42Hz"                    # human-readable: window title, about
APP_SLUG    = "42hz"                    # executable, config dir, log category
APP_ID      = f"{VENDOR}.{APP_NAME}"    # reverse-DNS application ID
APP_PATH    = "/" + APP_ID.replace(".", "/")
HOMEPAGE    = "https://github.com/chizzler/42Hz"

NODE_PREFIX = "hz_"                     # own DSP filter nodes: hz_soe_*, hz_sie_*
SINK_NAME   = f"{APP_SLUG}_sink"        # virtual sink exposed to PipeWire
SOURCE_NAME = f"{APP_SLUG}_source"      # virtual source exposed to PipeWire

if len(sys.argv) != 2:
    sys.exit(f"usage: {sys.argv[0]} <extracted-easyeffects-tree>")

root = pathlib.Path(sys.argv[1]).resolve()

# Refuse anything that is not recognisably an EasyEffects source tree, so a
# mistyped path cannot start deleting files somewhere else.
for marker in ("CMakeLists.txt", "src/main.cpp", "src/effects_base.cpp"):
    if not (root / marker).is_file():
        sys.exit(f"error: {root} is not an EasyEffects source tree (missing {marker})")

# kcolor_manager.cpp is removed below, so its absence means this tree has
# already been patched. Re-running would fail confusingly part-way through;
# fail clearly instead and let the caller re-extract.
if not (root / "src/kcolor_manager.cpp").is_file():
    sys.exit(f"error: {root} is already patched -- re-extract the tree first")

print(f"patching {root}")


def edit(p, fn):
    f = root / p
    s = f.read_text()
    s2 = fn(s)
    if s2 == s:
        sys.exit(f"error: patch for {p} matched nothing -- upstream has moved")
    f.write_text(s2)
    print(f"  patched {p} ({len(s)} -> {len(s2)} bytes)")


def sub(s, old, new):
    """Literal replace that refuses to silently no-op."""
    if old not in s:
        sys.exit(f"error: expected text not found: {old!r}")
    return s.replace(old, new)


# ===========================================================================
# PHASE 1 -- DEPENDENCY REDUCTION
# ===========================================================================

# ---- top-level CMakeLists: drop KDE UI + QtGraphs components ----
def top_deps(s):
    for comp in ["Kirigami", "KirigamiAddons", "QQC2DesktopStyle", "IconThemes", "ColorScheme"]:
        s = re.sub(rf"^\s*{comp}\s*$\n", "", s, flags=re.M)
    s = re.sub(r"^\s*Graphs\s*$\n", "", s, flags=re.M)
    s = re.sub(r"^ecm_find_qmlmodule\(org\.kde\.kirigami REQUIRED\)\s*$\n", "", s, flags=re.M)
    return s

# ---- src/CMakeLists: drop QML_FILES, kcolor_manager, and the KDE UI links ----
#
# The core's qt_add_qml_module keeps its upstream URI (ee.ui) and registers only
# C++ types; it ships no QML at all. 42Hz's QML is a SEPARATE module (hz.ui)
# declared in frontend/CMakeLists.txt and linked in as a plugin.
#
# That split is forced, not stylistic. Qt finalizes a QML module at the end of
# the directory scope that declared it, so a qt_target_qml_sources() call from
# frontend/ embeds the file in the binary but never reaches this module's
# qmldir. The result builds and links cleanly and then fails at load with
# "Failed to load QML UI" -- verified, 2026-08-29.
def src_deps(s):
    lines = s.split("\n")
    start = next(i for i, l in enumerate(lines) if l.strip() == "QML_FILES")
    end   = next(i for i, l in enumerate(lines) if i > start and l.startswith(")"))
    del lines[start:end]
    s = "\n".join(lines)
    # These name QML singletons this script deletes; leaving them is dead weight.
    s = sub(s, """set_source_files_properties(
    contents/ui/Common.qml
    contents/ui/EeMetersReset.qml
    contents/ui/Validators.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

""", "")
    s = re.sub(r"^\s*kcolor_manager\.cpp\s*$\n", "", s, flags=re.M)
    for lib in ["KF6::ColorScheme", "KF6::IconThemes", "Qt::Graphs"]:
        s = re.sub(rf"^\s*{re.escape(lib)}\s*$\n", "", s, flags=re.M)
    return s

# ---- main.cpp: strip KDE theming ----
def main_deps(s):
    # NOTE: main.cpp includes KDE headers in BOTH the CamelCase forwarding
    # form (<KIconTheme>) and the lowercase real form (<kicontheme.h>).
    # Both must go; matching only the former leaves a fatal missing header.
    for inc in ["#include <KColorSchemeManager>", "#include <KIconTheme>",
                "#include <kicontheme.h>",
                '#include "kcolor_manager.hpp"']:
        s = s.replace(inc + "\n", "")
    s = s.replace("  KIconTheme::initTheme();\n", "")
    s = s.replace("  KColorSchemeManager::instance();\n", "")
    s = s.replace("  auto color_manager = std::make_unique<KColorManager>();\n", "")
    # drop breeze style + kde desktop QQC2 style blocks
    s = re.sub(r"\n  if \(DbMain::forceBreezeTheme\(\)\) \{\n.*?\n  \}\n", "\n", s, flags=re.S)
    s = re.sub(r"\n  if \(qEnvironmentVariableIsEmpty\(\"QT_QUICK_CONTROLS_STYLE\"\)\) \{\n.*?\n  \}\n", "\n", s, flags=re.S)
    # Load Main from the 42Hz frontend module instead of upstream's ee.ui.
    # The literal below gates window->show(); a stale value leaves the process
    # running with no window and no error.
    s = sub(s, '"qrc:/qt/qml/ee/ui/contents/ui/Main.qml"', '"qrc:/qt/qml/hz/ui/Main.qml"')
    s = sub(s, 'engine.loadFromModule("ee.ui", "Main")', 'engine.loadFromModule("hz.ui", "Main")')
    return s


# ===========================================================================
# PHASE 2 -- IDENTITY REASSIGNMENT
# ===========================================================================

# ---- top-level CMakeLists: the identity variables feeding src/config.h ----
#
# APPLICATION_DOMAIN is both the gettext catalogue name and KAboutData's
# componentName, which becomes QCoreApplication::applicationName and therefore
# the AppConfigLocation/AppDataLocation leaf. Renaming it moves the presets
# directory to ~/.config/42hz/ for free -- and detaches the remaining core
# i18n strings from the installed easyeffects.mo catalogues, which is accepted:
# 42Hz supplies its own frontend strings and ships no catalogues yet.
def top_identity(s):
    s = sub(s, 'set(APPLICATION_DOMAIN "easyeffects")',  f'set(APPLICATION_DOMAIN "{APP_SLUG}")')
    s = sub(s, 'set(COMPONENT_NAME "easyeffects")',      f'set(COMPONENT_NAME "{APP_SLUG}")')
    s = sub(s, 'set(ORGANIZATION_NAME "WWMM")',          f'set(ORGANIZATION_NAME "{APP_NAME}")')
    s = sub(s, 'set(ORGANIZATION_DOMAIN "com.github.wwmm")', f'set(ORGANIZATION_DOMAIN "{VENDOR}")')
    s = sub(s, 'set(APPLICATION_ID "com.github.wwmm.easyeffects.Devel")', f'set(APPLICATION_ID "{APP_ID}.Devel")')
    s = sub(s, 'set(APPLICATION_ID "com.github.wwmm.easyeffects")',       f'set(APPLICATION_ID "{APP_ID}")')
    s = sub(s, 'set(APPLICATION_NAME "Easy Effects (Devel)")', f'set(APPLICATION_NAME "{APP_NAME} (Devel)")')
    s = sub(s, 'set(APPLICATION_NAME "Easy Effects")',         f'set(APPLICATION_NAME "{APP_NAME}")')
    return s

# ---- src/CMakeLists: rename the produced binary ----
#
# The CMake TARGET stays `easyeffects`: it is referenced ~30 times in this file
# and by qt_add_qml_module, and renaming it would multiply the patch inventory
# for no external effect. Only the produced filename is identity.
def src_identity(s):
    return sub(s, "add_executable(easyeffects)",
               f"add_executable(easyeffects)\nset_target_properties(easyeffects PROPERTIES OUTPUT_NAME {APP_SLUG})")

# ---- tags_app.hpp: application ID and (currently unused) D-Bus paths ----
def tags_app(s):
    s = sub(s, '"/com/github/wwmm/easyeffects/streaminputs/"',  f'"{APP_PATH}/streaminputs/"')
    s = sub(s, '"/com/github/wwmm/easyeffects/streamoutputs/"', f'"{APP_PATH}/streamoutputs/"')
    s = sub(s, '"/com/github/wwmm/easyeffects"', f'"{APP_PATH}"')
    s = sub(s, '"com.github.wwmm.easyeffects"', f'"{APP_ID}"')
    return s

# ---- tags_pipewire.hpp: virtual node names and internal media classes ----
#
# ee_sink / ee_source are INTERNAL sentinels: pw_node_manager stamps them onto
# its own node info after the fact and never sends them to PipeWire (the wire
# media.class stays Audio/Sink and Audio/Source/Virtual). Renaming them is
# therefore free of graph-visible consequences.
def tags_pipewire(s):
    s = sub(s, '"easyeffects_source"', f'"{SOURCE_NAME}"')
    s = sub(s, '"easyeffects_sink"',   f'"{SINK_NAME}"')
    s = sub(s, '"EE/Audio/Sink"',   f'"{APP_NAME}/Audio/Sink"')
    s = sub(s, '"EE/Audio/Source"', f'"{APP_NAME}/Audio/Source"')
    return s

# ---- db_manager.cpp: the KConfig database directory ----
#
# This is the path that made every unfenced development run dangerous: it is
# hard-coded rather than derived from applicationName.
def db_manager(s):
    return sub(s, '.append("/easyeffects/db")', f'.append("/{APP_SLUG}/db")')

# ---- util.cpp: logging category and single-instance lock ----
#
# The lock file is what keeps 42Hz and Easy Effects from refusing to coexist.
def util(s):
    s = sub(s, 'Q_LOGGING_CATEGORY(ee_logs, "easyeffects")', f'Q_LOGGING_CATEGORY(ee_logs, "{APP_SLUG}")')
    s = sub(s, '"/easyeffects.lock"', f'"/{APP_SLUG}.lock"')
    return s

# ---- main.cpp: logging rules and upstream links ----
def main_identity(s):
    s = sub(s, '"easyeffects.debug=false"', f'"{APP_SLUG}.debug=false"')
    s = sub(s, '"https://github.com/wwmm/easyeffects/issues"', f'"{HOMEPAGE}/issues"')
    s = sub(s, '"https://github.com/wwmm/easyeffects"', f'"{HOMEPAGE}"')
    return s

# ---- command_line_parser.cpp: logging rules and the usage example ----
def cli(s):
    s = sub(s, '"easyeffects.debug=true"', f'"{APP_SLUG}.debug=true"')
    s = sub(s, 'Load a preset. Example: easyeffects -l music',
               f'Load a preset. Example: {APP_SLUG} -l music')
    return s

# ---- plugin_base.cpp: the DSP filter node prefix and node groups ----
def plugin_base(s):
    s = sub(s, 'const auto filter_name = "ee_" +', f'const auto filter_name = "{NODE_PREFIX}" +')
    s = sub(s, '"ee_sink_group" : "ee_source_group"', f'"{NODE_PREFIX}sink_group" : "{NODE_PREFIX}source_group"')
    return s

# ---- pw_node_manager.cpp: self-recognition, node groups, descriptions ----
#
# The starts_with() test is how the core tells its own filter nodes from every
# other DSP filter on the graph. It MUST track the prefix in plugin_base.cpp;
# if the two drift, 42Hz lists its own filters as application streams.
def pw_node_manager_cpp(s):
    s = sub(s, 'node_name.starts_with("ee_")', f'node_name.starts_with("{NODE_PREFIX}")')
    s = sub(s, 'PW_KEY_NODE_GROUP, "ee_sink_group"',   f'PW_KEY_NODE_GROUP, "{NODE_PREFIX}sink_group"')
    s = sub(s, 'PW_KEY_NODE_GROUP, "ee_source_group"', f'PW_KEY_NODE_GROUP, "{NODE_PREFIX}source_group"')
    s = sub(s, '"Easy Effects Sink"',   f'"{APP_NAME} Sink"')
    s = sub(s, '"Easy Effects Source"', f'"{APP_NAME} Source"')
    return s

# ---- pw_node_manager.hpp: stream blocklist ----
#
# The Easy Effects entries are kept as well as added to: a concurrently running
# upstream Easy Effects is no more interesting as a mixer entry than we are.
def pw_node_manager_hpp(s):
    return sub(s, '{"Easy Effects", "EasyEffects", "easyeffects",',
                  f'{{"{APP_NAME}", "{APP_SLUG}", "Easy Effects", "EasyEffects", "easyeffects",')

# ---- autostart.cpp: the command written into the autostart entry ----
def autostart(s):
    s = sub(s, 'g_strdup("easyeffects")', f'g_strdup("{APP_SLUG}")')
    s = sub(s, '"Exec=easyeffects --hide-window"', f'"Exec={APP_SLUG} --hide-window"')
    s = sub(s, 'Please allow Easy Effects to ask again', f'Please allow {APP_NAME} to ask again')
    return s

# ---- global_shortcuts: xdg-desktop-portal handle tokens ----
#
# A handle token becomes a D-Bus object-path element, so it must match
# [A-Za-z0-9_]+. "hz42" rather than "42hz" keeps it leading-alphabetic.
def shortcuts(s):
    return sub(s, '"easyeffects%1"', '"hz42%1"')

# ---- contents/CMakeLists: install rules follow APPLICATION_ID ----
def contents_cmake(s):
    s = s.replace("com.github.wwmm.easyeffects-symbolic.svg",     "${APPLICATION_ID}-symbolic.svg")
    s = s.replace("com.github.wwmm.easyeffects-off-symbolic.svg", "${APPLICATION_ID}-off-symbolic.svg")
    s = s.replace("com.github.wwmm.easyeffects.metainfo.xml.in",  "${APPLICATION_ID}.metainfo.xml.in")
    s = s.replace("com.github.wwmm.easyeffects.desktop.in",       "${APPLICATION_ID}.desktop.in")
    return s

# ---- the desktop entry ----
def desktop(s):
    s = sub(s, "Exec=easyeffects", f"Exec={APP_SLUG}")
    s = sub(s, "GenericName=Equalizer, Compressor and Other Audio Effects",
               "GenericName=Audio Spectrum and Effects")
    s = sub(s, "Comment=Simple audio effects",
               "Comment=Minimal spectrum-first control surface for PipeWire audio")
    return s


# ---- tags_local_server.hpp: the single-instance socket name ----
#
# This is a socket in XDG_RUNTIME_DIR, and it is how `42hz -q`, `-l <preset>`
# and friends reach an already-running instance. Sharing it with Easy Effects
# means 42Hz's command line drives Easy Effects and vice versa -- the lock-file
# rename alone does NOT prevent this. Functional, not cosmetic.
def local_server(s):
    return sub(s, '"EasyEffectsServer"', f'"{APP_NAME}Server"')

# ---- test_signals.cpp: the test-tone filter node ----
#
# This node MUST carry NODE_PREFIX. pw_node_manager recognises its own filters
# by that prefix, so a stale "ee_" here would make the test tone show up as an
# ordinary application stream in the mixer.
def test_signals(s):
    s = sub(s, 'filter_name = "ee_test_signals"', f'filter_name = "{NODE_PREFIX}test_signals"')
    s = sub(s, '"Easy Effects Filter"', f'"{APP_NAME} Filter"')
    return s

# ---- main.cpp: the about-box copyright line ----
#
# Upstream's attribution is preserved rather than replaced. 42Hz is a
# derivative work under GPL-3.0-or-later; dropping the original copyright
# notice would be both wrong and a licence violation. The named-author entries
# immediately below this line are left exactly as upstream wrote them.
def about(s):
    return sub(s, 'i18n("© 2017-2026 Easy Effects Team")',
                  f'i18n("© 2017-2026 Wellington Wallace (Easy Effects) · {APP_NAME} frontend © 2026 {APP_NAME} contributors")')

# ---- command_line_parser.cpp: user-visible help text ----
def cli_text(s):
    s = sub(s, 'parser->setApplicationDescription("Easy Effects")',
               f'parser->setApplicationDescription("{APP_NAME}")')
    s = sub(s, 'i18n("Quit Easy Effects. Useful when running in service mode.")',
               f'i18n("Quit {APP_NAME}. Useful when running in service mode.")')
    s = sub(s, 'i18n("Reset Easy Effects.")', f'i18n("Reset {APP_NAME}.")')
    return s

# ---- autostart.cpp: the xdg portal background-permission identity ----
def autostart_portal(s):
    s = sub(s, '"EasyEffects-Autostart"', f'"{APP_NAME}-Autostart"')
    s = sub(s, 'permission for Easy Effects in your system app settings.',
               f'permission for {APP_NAME} in your system app settings.')
    return s

# NOT renamed, deliberately:
#
#   tags_plugin_name.hpp   `ee` = "Easy Effects" is a plugin VENDOR label, shown
#                          beside "Linux Studio Plugins", "MDA" and "x42". The
#                          DSP it labels really is Easy Effects' work; relabelling
#                          it "42Hz" would misattribute someone else's code.
#
#   util::warning() text   A handful of internal diagnostics read "... cannot be
#                          handled by Easy Effects". They surface only on error
#                          paths under --debug, and naming the derived core's
#                          origin there is honest. Renaming them would add five
#                          patch entries for no user-visible gain.


# ---- pw_node_manager.cpp: target.object name-vs-serial resolution ----
#
# REQUIRED BY THE RENAME, and an upstream defect in its own right.
#
# A client may pin its output with the PipeWire property `target.object`, whose
# value is "a name or serial number". The core decides which by trying a
# numeric parse first -- but util::str_to_num wraps std::from_chars, which
# reports success on a PARTIAL parse. "42hz_sink" therefore parses as serial
# 42, matches no real node, and the stream is silently dropped from the mixer
# while remaining perfectly audible.
#
# "easyeffects_sink" never triggered this because it does not begin with a
# digit. Verified against stock Easy Effects v8.2.8, which accepts the same
# ffplay stream that the renamed build rejected.
#
# The single replacement below covers BOTH the output block (target = sink)
# and the input block (target = source); the two are textually identical.
def target_object(s):
    return sub(s,
        "      if (util::str_to_num(target_object, serial)) {",
        "      // target.object is a NAME unless it is entirely digits. str_to_num wraps\n"
        "      // std::from_chars, which succeeds on a PARTIAL parse, so a digit-leading\n"
        "      // name would be misread as a serial and the stream silently ignored.\n"
        "      if (std::string(target_object).find_first_not_of(\"0123456789\") == std::string::npos &&\n"
        "          util::str_to_num(target_object, serial)) {")


# ---- pw_manager.cpp: an audio service that goes away is a state, not an exit ----
#
# Two defects, one cause: nothing ever told the frontend that the connection had
# changed.
#
# runtimeVersionChanged is DECLARED in pw_manager.hpp and emitted nowhere, so a
# QML binding on runtimeVersion is evaluated once at load and frozen for the
# life of the process. `audioServiceReady` could therefore never go false --
# the only thing it exists to say.
#
# And on_core_error called util::fatal on "connection error", which is qCFatal,
# which aborts. A `systemctl --user restart pipewire` killed 42Hz outright,
# against the requirement that it recover from PipeWire restarts without a UI
# restart -- and a process that has vanished reports nothing at all, which is
# the outcome the runtime-state rules exist to forbid.
#
# Both writes are moved onto the object's own thread. on_core_error and
# on_core_info run on the PipeWire thread, and the value is now read by a GUI
# thread binding, so assigning it here would race.
#
# This does NOT make an unreachable-at-startup PipeWire survivable. That is a
# larger change -- pw_filter_new() and pw_filter_add_port() dereference the
# core, and three spin loops have no exit without a connection -- and it is
# recorded as open work rather than half-done here.
def pw_manager_service_state(s):
    s = sub(s,
        '    if (std::string(message) == "connection error") {\n'
        '      util::fatal("No connection to PipeWire. Aborting!");\n'
        '    }\n',
        '    if (std::string(message) == "connection error") {\n'
        '      // Was util::fatal, which aborts. See reduce-deps.py.\n'
        '      util::critical("No connection to PipeWire.");\n'
        '\n'
        '      QMetaObject::invokeMethod(\n'
        '          pm,\n'
        '          [pm]() {\n'
        '            pm->runtimeVersion.clear();\n'
        '\n'
        '            Q_EMIT pm->runtimeVersionChanged();\n'
        '          },\n'
        '          Qt::QueuedConnection);\n'
        '    }\n')

    return sub(s,
        "  pm->runtimeVersion = info->version;\n",
        "  // Assigned on the object's own thread, and emitted at all. See\n"
        "  // reduce-deps.py -- runtimeVersionChanged was declared and never fired.\n"
        "  QMetaObject::invokeMethod(\n"
        "      pm,\n"
        "      [pm, version = QString::fromUtf8(info->version)]() {\n"
        "        pm->runtimeVersion = version;\n"
        "\n"
        "        Q_EMIT pm->runtimeVersionChanged();\n"
        "      },\n"
        "      Qt::QueuedConnection);\n")


# ---- refuse to capture a stream whose path returns to 42Hz's own sink ----
#
# apps -> 42hz_sink -> processing -> the stream -> 42hz_sink is a closed loop,
# and under processAllOutputs 42Hz builds it itself. One command makes it:
#
#     pactl load-module module-loopback source=42hz_sink.monitor
#
# project.md requires refusing exactly this, and marks it as 42Hz's own
# requirement rather than upstream's -- stock EasyEffects behaves identically.
#
# PipeWire names the relationship: the capture and playback halves of a loopback
# (and of a filter-chain sink) share PW_KEY_NODE_LINK_GROUP. The hop between
# them is inside the module and is not a PipeWire link, so walking the graph
# never finds it; the link-group is the only thing that does.
#
# Two things had to be found the hard way. Neither key is in the registry's
# global props, only in the node's own info props, so reading them at
# registration silently yielded empty strings. And the core DISCARDS the proof
# before it is needed: a capture stream recording from 42hz_sink is not
# recording from the mic, so it is ignored and removed from the node model --
# the half that proves a loop is thrown away one step before the half that would
# close it is judged. Hence the set, populated ahead of those tests.
#
# The refusal releases rather than merely skips. onNodeInfo fires repeatedly and
# the two halves register in no guaranteed order, so an earlier callback may
# already have pointed the stream at us; clearing target.node/target.object
# undoes that and the stream falls back to the default sink.
def pw_objects_link_group(s):
    return sub(s, "  QString application_id;\n", "  QString application_id;\n\n" + "  // PW_KEY_NODE_LINK_GROUP. PipeWire marks the halves of one logical\n  // stream with this -- the capture and playback sides of a loopback, or of\n  // a filter-chain sink. It is what lets a path that returns to 42Hz's own\n  // sink be recognised at registration, before the links that would close\n  // the loop exist.\n  QString link_group;\n\n  // PW_KEY_TARGET_OBJECT as the client asked for it, by name or by serial.\n  // Empty means the node follows the default device.\n  QString target_object;\n")


def pw_node_manager_cycle_cpp(s):
    anchor_out = '  if (nd->nd_info->media_class == tags::pipewire::media_class::output_stream) {\n    if (const auto* target_object'
    s = sub(s, anchor_out, "  // Read before the ignore tests below, because they are what discards the\n  // evidence. Neither key is in the registry's global props -- only in the\n  // node's own info props.\n  if (const auto* link_group = spa_dict_lookup(info->props, PW_KEY_NODE_LINK_GROUP)) {\n    nd->nd_info->link_group = link_group;\n  }\n\n  if (const auto* target_object = spa_dict_lookup(info->props, PW_KEY_TARGET_OBJECT)) {\n    nd->nd_info->target_object = target_object;\n  }\n\n  // Remember any link-group that reads from our own sink.\n  //\n  // This has to be recorded here, before the tests below, because those tests\n  // throw the proof away: a capture stream recording from 42hz_sink is not\n  // recording from the mic, so it is ignored and REMOVED from the model. The\n  // half that proves a loop exists is discarded one step before the half that\n  // would close it is judged.\n  if (!nd->nd_info->link_group.isEmpty() && !nd->nd_info->target_object.isEmpty() &&\n      nd->nd_info->media_class == tags::pipewire::media_class::input_stream) {\n    const auto sink_serial = QString::fromStdString(util::to_string(nm->ee_sink_node.serial));\n\n    if (nd->nd_info->target_object == nm->ee_sink_node.name || nd->nd_info->target_object == sink_serial) {\n      nm->link_groups_reading_ee_sink.insert(nd->nd_info->link_group);\n    }\n  }\n\n" + anchor_out)

    anchor_sink = '  auto connect_to_ee_sink = [&]() {\n    if (DbMain::processAllOutputs() && !nd->nd_info->is_blocklisted) {\n'
    s = sub(s, anchor_sink, anchor_sink + '      // Refuse to link a stream whose path returns to our own sink.\n      //\n      // Released rather than merely skipped. onNodeInfo fires repeatedly, and\n      // the two halves of the loop do not register in a guaranteed order, so an\n      // earlier callback may already have pointed this stream at us before the\n      // capture half arrived to prove it was a loop. Clearing the target is\n      // what undoes that; the stream then follows the default sink, which for a\n      // monitor loopback is what was wanted anyway.\n      if (nm->returns_to_ee_sink(*nd->nd_info)) {\n        util::debug(std::format("{} feeds back into {}. Refusing to capture it.",\n                                nd->nd_info->name.toStdString(), tags::pipewire::ee_sink_name));\n\n        nm->metadata_manager.set_property(nd->nd_info->id, "target.node", nullptr, nullptr);\n        nm->metadata_manager.set_property(nd->nd_info->id, "target.object", nullptr, nullptr);\n\n        return;\n      }\n' + "\n")

    return sub(s, 'void NodeManager::setNodeMute(uint64_t serial, bool state) {', "// A stream must not be captured if what it plays is what 42Hz's own sink\n// produces. apps -> 42hz_sink -> processing -> the stream -> 42hz_sink is a\n// closed loop, and under processAllOutputs 42Hz builds it itself.\n//\n// PipeWire names the relationship for us: the capture and playback halves of a\n// loopback, and of a filter-chain sink, share PW_KEY_NODE_LINK_GROUP. The hop\n// between them is inside the module and is not a PipeWire link, so no amount of\n// walking the graph finds it -- the link-group is the only thing that does.\n//\n// The upstream guard in StreamOutputEffects::on_link_changed does not cover\n// this. It compares the default output device against our sink by name, one\n// specific arrangement, and a loopback sourced from our own monitor closes a\n// loop without the default device being involved at all.\nauto NodeManager::returns_to_ee_sink(const NodeInfo& node) const -> bool {\n  return !node.link_group.isEmpty() && link_groups_reading_ee_sink.contains(node.link_group);\n}\n\n" + 'void NodeManager::setNodeMute(uint64_t serial, bool state) {')


def pw_node_manager_cycle_hpp(s):
    s = sub(s, '#include "pw_model_nodes.hpp"', '#include <QSet>\n#include "pw_model_nodes.hpp"')
    s = sub(s, "  void setNodeMute(uint64_t serial, bool state);",
            "  void setNodeMute(uint64_t serial, bool state);\n\n" + "  // True when capturing this stream would close a loop through 42Hz's own sink.\n  // See the definition for why link-group is the right relationship.\n  [[nodiscard]] auto returns_to_ee_sink(const NodeInfo& node) const -> bool;")
    return sub(s, "  models::Nodes& model_nodes;", "  // Link-groups known to read from 42Hz's own sink. Kept here rather than\n  // derived from the node model, because the capture half that proves it is\n  // ignored and removed from that model before it can be consulted.\n  QSet<QString> link_groups_reading_ee_sink;\n" + "\n  models::Nodes& model_nodes;")


# ---- honour node.dont-move: a filter's stream is not an application's ----
#
# project.md: "never move a DSP filter's own stream as if it were an
# application". 42Hz did move it, and got away with it only because someone else
# said no.
#
# Omarchy's speaker tuning is a filter-chain sink whose output leg pins
# target.object at the speaker and sets node.dont-move, with a comment naming the
# risk: anything rerouting "all streams" would drag the processing along, "or
# into the tuning's own sink, which is a cycle". Under processAllOutputs 42Hz did
# exactly that -- it wrote target.object = <42hz_sink> onto that pinned node, and
# WirePlumber refused the move. A filter chain that omits the pin, or a different
# session manager, would have been dragged in; measured, one without it was.
#
# node.dont-move is not a PW_KEY_ constant. It is a convention WirePlumber reads
# as a raw string in scripts/linking/find-defined-target.lua, so it is read as
# one here too.
#
# Both mechanisms need it. The node manager writes the metadata itself when a
# node appears; Manager::connectStream{Output,Input} are called from the startup
# reconciliation and from the blocklist handler. Guarding only the first honours
# the pin for streams that arrive while 42Hz is running and ignores it for
# everything already there when it started.
def pw_objects_dont_move(s):
    return sub(s, "  bool connected = false;\n", '  // node.dont-move. Not a PipeWire constant -- a convention WirePlumber\n  // reads as a raw string, set by anything whose routing is a structural\n  // fact rather than a preference: the output leg of a filter-chain sink,\n  // which belongs to the device it was fitted for and nowhere else.\n  bool dont_move = false;\n' + "\n  bool connected = false;\n")


def pw_node_manager_dont_move(s):
    s = sub(s, '  if (const auto* target_object = spa_dict_lookup(info->props, PW_KEY_TARGET_OBJECT)) {\n    nd->nd_info->target_object = target_object;\n  }\n', '  if (const auto* target_object = spa_dict_lookup(info->props, PW_KEY_TARGET_OBJECT)) {\n    nd->nd_info->target_object = target_object;\n  }\n\n  util::spa_dict_get_bool(info->props, "node.dont-move", nd->nd_info->dont_move);\n')
    s = sub(s, '  auto connect_to_ee_sink = [&]() {\n    if (DbMain::processAllOutputs() && !nd->nd_info->is_blocklisted) {\n', '  auto connect_to_ee_sink = [&]() {\n    if (DbMain::processAllOutputs() && !nd->nd_info->is_blocklisted) {\n' + '      // Some streams are not applications and their routing is not a\n      // preference. The output leg of a filter-chain sink -- an Omarchy\n      // speaker tuning, say -- belongs to the device it was fitted for,\n      // and says so with node.dont-move.\n      if (nd->nd_info->dont_move) {\n        return;\n      }\n\n')
    return sub(s, '  auto connect_to_ee_source = [&]() {\n    if (DbMain::processAllInputs() && !nd->nd_info->is_blocklisted) {\n', '  auto connect_to_ee_source = [&]() {\n    if (DbMain::processAllInputs() && !nd->nd_info->is_blocklisted) {\n' + '      if (nd->nd_info->dont_move) {\n        return;\n      }\n\n')


def pw_manager_dont_move(s):
    s = sub(s, 'void Manager::connectStreamOutput(const uint& id) const {\n  set_metadata_target_node(id, ee_sink_node.id, ee_sink_node.serial);\n}\n', '// The other way a stream is moved. The node manager writes the metadata itself\n// when a node appears; these are called from the startup reconciliation and from\n// the blocklist handler, so a pin has to be honoured in both places or it holds\n// only for streams that arrive while 42Hz is already running.\nvoid Manager::connectStreamOutput(const uint& id) const {\n  if (model_nodes.get_node_by_id(id).dont_move) {\n    return;\n  }\n\n  set_metadata_target_node(id, ee_sink_node.id, ee_sink_node.serial);\n}\n')
    return sub(s, 'void Manager::connectStreamInput(const uint& id) const {\n  set_metadata_target_node(id, ee_source_node.id, ee_source_node.serial);\n}\n', 'void Manager::connectStreamInput(const uint& id) const {\n  if (model_nodes.get_node_by_id(id).dont_move) {\n    return;\n  }\n\n  set_metadata_target_node(id, ee_source_node.id, ee_source_node.serial);\n}\n')


# ---- pw_model_nodes: the lookup those guards need is a read ----
def pw_model_nodes_const_lookup_hpp(s):
    return sub(s, "  auto get_node_by_id(const uint& id) -> NodeInfo;",
        "  // const: it is a lookup, and the routing guards that consult it are\n"
        "  // called from const context.\n"
        "  [[nodiscard]] auto get_node_by_id(const uint& id) const -> NodeInfo;")


def pw_model_nodes_const_lookup_cpp(s):
    return sub(s, "auto Nodes::get_node_by_id(const uint& id) -> NodeInfo {",
        "auto Nodes::get_node_by_id(const uint& id) const -> NodeInfo {")


# ---- contents/kcfg/*.kcfg: the KConfig file paths ----
#
# THIS is where settings actually land. db_manager.cpp only creates the
# directory; every KConfig object writes to the path declared in its own .kcfg
# <kcfgfile name="..."/>, and all 38 of them hard-code "easyeffects/db/*rc".
#
# Renaming db_manager.cpp alone therefore produced a build that created an empty
# ~/.config/42hz/db/ and went on writing the user's real
# ~/.config/easyeffects/db/easyeffectsrc -- silently, and only when a setting
# actually changed, which is why a checksum taken right after startup showed
# nothing wrong. Window geometry was the first thing to change and the first
# thing to leak.
def kcfg_paths(root):
    n = 0
    for f in sorted((root / "src/contents/kcfg").glob("*.kcfg")):
        t = f.read_text()
        if 'kcfgfile name="easyeffects/db/' not in t:
            sys.exit(f"error: {f.name} has no easyeffects/db kcfgfile path -- upstream has moved")
        t = t.replace('kcfgfile name="easyeffects/db/easyeffectsrc"',
                      f'kcfgfile name="{APP_SLUG}/db/{APP_SLUG}rc"')
        # The remaining 37 are named for the PLUGIN they configure (equalizerrc,
        # autogainrc, ...), not the application, so only the path moves.
        t = t.replace('kcfgfile name="easyeffects/db/', f'kcfgfile name="{APP_SLUG}/db/')
        f.write_text(t)
        n += 1
    if n == 0:
        sys.exit("error: no .kcfg files found -- upstream has moved")
    print(f"  patched {n} kcfg files (KConfig paths -> {APP_SLUG}/db/)")


# --- phase 1 edits ---
edit("CMakeLists.txt", top_deps)
edit("src/CMakeLists.txt", src_deps)
edit("src/main.cpp", main_deps)

# --- phase 2 edits ---
edit("CMakeLists.txt", top_identity)
edit("src/CMakeLists.txt", src_identity)
edit("src/tags_app.hpp", tags_app)
edit("src/tags_pipewire.hpp", tags_pipewire)
edit("src/db_manager.cpp", db_manager)
edit("src/util.cpp", util)
edit("src/main.cpp", main_identity)
edit("src/command_line_parser.cpp", cli)
edit("src/plugin_base.cpp", plugin_base)
edit("src/pw_node_manager.cpp", pw_node_manager_cpp)
edit("src/pw_node_manager.cpp", target_object)
edit("src/pw_node_manager.hpp", pw_node_manager_hpp)
edit("src/pw_manager.cpp", pw_manager_service_state)
edit("src/pw_objects.hpp", pw_objects_link_group)
edit("src/pw_node_manager.cpp", pw_node_manager_cycle_cpp)
edit("src/pw_node_manager.hpp", pw_node_manager_cycle_hpp)
edit("src/pw_objects.hpp", pw_objects_dont_move)
edit("src/pw_node_manager.cpp", pw_node_manager_dont_move)
edit("src/pw_manager.cpp", pw_manager_dont_move)
edit("src/pw_model_nodes.hpp", pw_model_nodes_const_lookup_hpp)
edit("src/pw_model_nodes.cpp", pw_model_nodes_const_lookup_cpp)
edit("src/autostart.cpp", autostart)
edit("src/global_shortcuts.cpp", shortcuts)
edit("src/global_shortcuts.hpp", shortcuts)
edit("src/contents/CMakeLists.txt", contents_cmake)
kcfg_paths(root)
edit("src/tags_local_server.hpp", local_server)
edit("src/test_signals.cpp", test_signals)
edit("src/main.cpp", about)
edit("src/command_line_parser.cpp", cli_text)
edit("src/autostart.cpp", autostart_portal)

# --- removals ---
for f in ["src/kcolor_manager.cpp", "src/kcolor_manager.hpp"]:
    (root / f).unlink()
    print(f"  removed {f}")

# --- renamed identity assets ---
contents = root / "src/contents"
old_desktop = contents / "com.github.wwmm.easyeffects.desktop.in"
new_desktop = contents / f"{APP_ID}.desktop.in"
old_desktop.rename(new_desktop)
edit(new_desktop.relative_to(root), desktop)
(contents / "com.github.wwmm.easyeffects.desktop.in.template").unlink()
print(f"  renamed desktop entry -> {new_desktop.name}")

for old, new in [("com.github.wwmm.easyeffects.svg",              f"{APP_ID}.svg"),
                 ("com.github.wwmm.easyeffects.Devel.svg",        f"{APP_ID}.Devel.svg"),
                 ("com.github.wwmm.easyeffects-symbolic.svg",     f"{APP_ID}-symbolic.svg"),
                 ("com.github.wwmm.easyeffects-off-symbolic.svg", f"{APP_ID}-off-symbolic.svg")]:
    (contents / "icons" / old).rename(contents / "icons" / new)
print(f"  renamed 4 icons -> {APP_ID}*.svg  (artwork still upstream's; milestone 6)")

# Upstream's metainfo is 65K of Easy Effects release notes. Shipping it under
# the 42Hz application ID would be a false claim about what this program is,
# so it is replaced with a minimal honest stub. Full appstream data, including
# screenshots and a real release history, is milestone 6.
(contents / "com.github.wwmm.easyeffects.metainfo.xml.in").unlink()
(contents / f"{APP_ID}.metainfo.xml.in").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>@APPLICATION_ID@.desktop</id>
  <name>@APPLICATION_NAME@</name>
  <summary>Minimal spectrum-first control surface for PipeWire audio</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>GPL-3.0-or-later</project_license>
  <description>
    <p>
      {APP_NAME} is an ultra-minimal control surface for PipeWire audio,
      derived from Easy Effects. It preserves Easy Effects' PipeWire
      integration, stream routing, and DSP hosting, and replaces its frontend
      with a responsive, spectrum-first interface.
    </p>
    <p>
      {APP_NAME} is a derivative work of Easy Effects, copyright
      2017-2026 Wellington Wallace, used under the GPL-3.0-or-later. It is not
      affiliated with or endorsed by the Easy Effects project.
    </p>
  </description>
  <launchable type="desktop-id">@APPLICATION_ID@.desktop</launchable>
  <url type="homepage">{HOMEPAGE}</url>
</component>
''')
print(f"  replaced metainfo -> {APP_ID}.metainfo.xml.in (stub; upstream release notes dropped)")

# ---- delete upstream's Kirigami QML ----
#
# 42Hz's own QML is NOT written here: it lives in frontend/, tracked in this
# repository, and is added to the build by the top-level CMakeLists. Keeping
# frontend source out of the patch inventory is the point -- this script stays
# a record of what was changed in someone else's tree, and 42Hz's code stays
# editable in place rather than being copied into a disposable directory.
ui = root / "src/contents/ui"
n_qml = len(list(ui.glob("*.qml")))
for q in ui.glob("*.qml"):
    q.unlink()
ui.rmdir()
print(f"  deleted {n_qml} upstream QML files (42Hz supplies frontend/ instead)")

print(f"done -- patch inventory applied to {root}")
print(f"       identity: {APP_ID} / {APP_SLUG} / {SINK_NAME} / {NODE_PREFIX}*")
print( "next    cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release && ninja -C build")
