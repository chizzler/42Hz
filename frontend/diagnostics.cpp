/*
 * 42Hz — the diagnostics report. See diagnostics.hpp for why this opens its
 * own PipeWire connection instead of asking the core.
 */

#include "diagnostics.hpp"

#include <lilv/lilv.h>
#include <pipewire/pipewire.h>
#include <spa/utils/dict.h>

#include <QStringList>
#include <QTextStream>
#include <ctime>
#include <string_view>

#include "theme.hpp"

namespace {

// What one read-only pass over the graph can establish. Nothing here is bound
// beyond the registry, so nothing here can move a stream.
struct Graph {
  bool reachable = false;
  QString serverVersion;
  QString clockRate;
  QStringList ownNodes;      // 42Hz's virtual devices and DSP filters
  int playbackStreams = 0;
  QString errorMessage;

  // Handed to the registry callback so it can recognise 42Hz's own nodes
  // without this file knowing what they are called.
  const hz::Identity* identity = nullptr;

  pw_main_loop* loop = nullptr;
  int syncSeq = 0;
};

void on_core_info(void* data, const pw_core_info* info) {
  auto* graph = static_cast<Graph*>(data);

  graph->reachable = true;
  graph->serverVersion = QString::fromUtf8(info->version);

  if (const auto* rate = spa_dict_lookup(info->props, "default.clock.rate"); rate != nullptr) {
    graph->clockRate = QString::fromUtf8(rate);
  }
}

// The roundtrip's answer. Anything the server was going to tell us about the
// registry has arrived by the time our own sync comes back.
void on_core_done(void* data, uint32_t id, int seq) {
  auto* graph = static_cast<Graph*>(data);

  if (id == PW_ID_CORE && seq == graph->syncSeq) {
    pw_main_loop_quit(graph->loop);
  }
}

void on_core_error(void* data, uint32_t /*id*/, int /*seq*/, int /*res*/, const char* message) {
  auto* graph = static_cast<Graph*>(data);

  graph->errorMessage = QString::fromUtf8(message);

  pw_main_loop_quit(graph->loop);
}

void on_registry_global(void* data,
                        uint32_t /*id*/,
                        uint32_t /*permissions*/,
                        const char* type,
                        uint32_t /*version*/,
                        const spa_dict* props) {
  auto* graph = static_cast<Graph*>(data);

  if (props == nullptr || type == nullptr || std::string_view(type) != PW_TYPE_INTERFACE_Node) {
    return;
  }

  const auto* name = spa_dict_lookup(props, PW_KEY_NODE_NAME);
  const auto* media_class = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);

  if (name != nullptr) {
    const auto node_name = QString::fromUtf8(name);
    const auto& id = *graph->identity;

    if (node_name == id.sinkName || node_name == id.sourceName || node_name.startsWith(id.nodePrefix)) {
      graph->ownNodes.append(node_name);
    }
  }

  if (media_class != nullptr && std::string_view(media_class) == "Stream/Output/Audio") {
    graph->playbackStreams++;
  }
}

const pw_core_events core_events = {.version = PW_VERSION_CORE_EVENTS,
                                    .info = on_core_info,
                                    .done = on_core_done,
                                    .ping = nullptr,
                                    .error = on_core_error,
                                    .remove_id = nullptr,
                                    .bound_id = nullptr,
                                    .add_mem = nullptr,
                                    .remove_mem = nullptr,
                                    .bound_props = nullptr};

const pw_registry_events registry_events = {.version = PW_VERSION_REGISTRY_EVENTS,
                                            .global = on_registry_global,
                                            .global_remove = nullptr};

// A diagnostic that hangs is worse than one that reports a timeout: an audio
// service can accept a connection and then answer nothing.
void on_timeout(void* data, uint64_t /*expirations*/) {
  auto* graph = static_cast<Graph*>(data);

  if (graph->errorMessage.isEmpty()) {
    graph->errorMessage = QStringLiteral("no reply within 2 seconds");
  }

  pw_main_loop_quit(graph->loop);
}

auto probe_graph(const hz::Identity& identity) -> Graph {
  Graph graph;
  graph.identity = &identity;

  pw_init(nullptr, nullptr);

  graph.loop = pw_main_loop_new(nullptr);

  if (graph.loop == nullptr) {
    graph.errorMessage = QStringLiteral("could not create a PipeWire loop");

    return graph;
  }

  auto* loop = pw_main_loop_get_loop(graph.loop);

  // No media properties are set: this connection asks questions and is not a
  // client of anything.
  auto* context = pw_context_new(loop, nullptr, 0);

  if (context == nullptr) {
    graph.errorMessage = QStringLiteral("could not create a PipeWire context");

    pw_main_loop_destroy(graph.loop);

    return graph;
  }

  auto* core = pw_context_connect(context, nullptr, 0);

  if (core == nullptr) {
    graph.errorMessage = QStringLiteral("connection refused");

    pw_context_destroy(context);
    pw_main_loop_destroy(graph.loop);

    return graph;
  }

  spa_hook core_listener{};
  spa_hook registry_listener{};

  auto* registry = pw_core_get_registry(core, PW_VERSION_REGISTRY, 0);

  pw_core_add_listener(core, &core_listener, &core_events, &graph);
  pw_registry_add_listener(registry, &registry_listener, &registry_events, &graph);

  auto* timer = pw_loop_add_timer(loop, on_timeout, &graph);
  timespec timeout = {.tv_sec = 2, .tv_nsec = 0};
  pw_loop_update_timer(loop, timer, &timeout, nullptr, false);

  graph.syncSeq = pw_core_sync(core, PW_ID_CORE, 0);

  pw_main_loop_run(graph.loop);

  pw_loop_destroy_source(loop, timer);
  spa_hook_remove(&registry_listener);
  spa_hook_remove(&core_listener);
  pw_proxy_destroy(reinterpret_cast<pw_proxy*>(registry));
  pw_core_disconnect(core);
  pw_context_destroy(context);
  pw_main_loop_destroy(graph.loop);

  graph.loop = nullptr;

  return graph;
}

// One capability, as the report draws it: a name, a state and the evidence the
// state was read from. The evidence column is the point -- "ready" on its own
// is not a diagnostic.
void line(QTextStream& out, const QString& name, const QString& state, const QString& detail) {
  out << "  " << name.leftJustified(16) << state.leftJustified(14) << detail << '\n';
}

}  // namespace

namespace hz {

auto report(const Identity& identity) -> int {
  QTextStream out(stdout);

  const auto graph = probe_graph(identity);

  Theme theme;

  LilvWorld* world = lilv_world_new();
  bool equalizerFound = false;

  if (world != nullptr) {
    lilv_world_load_all(world);

    if (auto* uri = lilv_new_uri(world, identity.equalizerUri.toUtf8().constData()); uri != nullptr) {
      equalizerFound = lilv_plugins_get_by_uri(lilv_world_get_all_plugins(world), uri) != nullptr;

      lilv_node_free(uri);
    }

    lilv_world_free(world);
  }

  out << "42Hz " << identity.version << " (Easy Effects core " << identity.upstreamVersion << ")\n"
      << identity.applicationId << "\n\n";

  line(out, QStringLiteral("application"), QStringLiteral("ready"),
       identity.instanceRunning ? QStringLiteral("an instance is already running")
                                : QStringLiteral("no instance is running"));

  if (graph.reachable) {
    auto detail = QStringLiteral("PipeWire ") + graph.serverVersion;

    if (!graph.clockRate.isEmpty()) {
      detail += QStringLiteral(", ") + graph.clockRate + QStringLiteral(" Hz");
    }

    line(out, QStringLiteral("audio service"), QStringLiteral("ready"), detail);
  } else {
    line(out, QStringLiteral("audio service"), QStringLiteral("unreachable"), graph.errorMessage);
  }

  // Processing is a property of a RUNNING instance, so its absence is only a
  // fault when there is an instance that should have built it. Reported as
  // "not running" rather than "stopped" -- project.md is explicit that those
  // are different states and must not be worded alike.
  const auto ownNodes = graph.ownNodes;

  if (!ownNodes.isEmpty()) {
    line(out, QStringLiteral("processing"), QStringLiteral("ready"),
         QStringLiteral("%1 nodes in the graph").arg(ownNodes.size()));
  } else if (identity.instanceRunning) {
    line(out, QStringLiteral("processing"), QStringLiteral("stopped"),
         QStringLiteral("an instance is running but has no nodes in the graph"));
  } else {
    line(out, QStringLiteral("processing"), QStringLiteral("not running"),
         QStringLiteral("42Hz is not processing audio"));
  }

  line(out, QStringLiteral("equalizer"), equalizerFound ? QStringLiteral("ready") : QStringLiteral("missing"),
       identity.equalizerUri);

  line(out, QStringLiteral("theme"), theme.ready() ? QStringLiteral("ready") : QStringLiteral("fallback"),
       theme.ready() ? QStringLiteral("%1 (%2)").arg(theme.name(), theme.dark() ? QStringLiteral("dark")
                                                                                : QStringLiteral("light"))
                     : QStringLiteral("no Omarchy state read; built-in tokens in force"));

  if (graph.reachable) {
    out << '\n';

    line(out, QStringLiteral("42Hz nodes"), QString::number(ownNodes.size()),
         ownNodes.isEmpty() ? QStringLiteral("none in the graph") : ownNodes.join(QStringLiteral(", ")));

    line(out, QStringLiteral("playback"), QString::number(graph.playbackStreams),
         graph.playbackStreams == 1 ? QStringLiteral("stream in the graph")
                                    : QStringLiteral("streams in the graph"));
  }

  out << '\n';

  // A script branches on this. Not being installed is not a failure of the
  // machine 42Hz is running on, so a stopped pipeline only counts when an
  // instance is up to have built one.
  const bool failed = !graph.reachable || !equalizerFound || !theme.ready() ||
                      (identity.instanceRunning && ownNodes.isEmpty());

  return failed ? 1 : 0;
}

}  // namespace hz
