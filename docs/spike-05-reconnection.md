# Spike 05 — Recovering from a PipeWire restart

Design for the reconnection work. Nothing here is implemented; this is the
result of reading the derived core closely enough to know what implementing it
costs, written down so that the next session executes rather than rediscovers.

Established by measurement in the diary entry for `76fe070`, which fixed the
adjacent and much smaller problem: 42Hz no longer *dies* when PipeWire restarts.
It still does not *recover*.

## What happens today

`systemctl --user restart pipewire` produces, in order:

1. `on_core_error` fires with `res: Broken pipe`, `message: connection error`.
2. 42Hz clears `runtimeVersion` and the window reports **no audio service**.
   (This is the part `76fe070` added; before it, `util::fatal` aborted here.)
3. Nothing else happens. `42hz_sink` is gone from the graph and is never
   rebuilt. The process is alive, honest, and useless until restarted by hand.

Surviving the loss is not recovering from it. Milestone 3's definition of done
includes "safe recovery after graph failure", so **this work is on milestone 3's
critical path**, not optional hardening.

## The constraint that decides the design

The obvious approach — throw away the audio stack and build a new one — is not
available.

`StreamOutputEffects` and `StreamInputEffects` are QML singletons whose instance
is captured in a static pointer at construction:

```cpp
inline static StreamOutputEffects* singletonInstance = nullptr;

static StreamOutputEffects* create(QQmlEngine* qmlEngine, QJSEngine* jsEngine) {
    // The instance has to exist before it is used. We cannot replace it.
    Q_ASSERT(singletonInstance);
    QJSEngine::setObjectOwnership(singletonInstance, QJSEngine::CppOwnership);
    return singletonInstance;
}
```

QML holds that exact pointer with C++ ownership for the life of the engine.
Destroying and recreating `soe` leaves every `StreamOutputEffects.…` in the
frontend pointing at freed memory. Upstream's own comment says it outright.

**So every object must keep its identity and rebuild its PipeWire state in
place.** That is what makes this bigger than it first appears.

One thing does help. The sub-managers hold the connection by reference:

```cpp
explicit LinkManager(pw_core*& core, pw_thread_loop*& thread_loop, ...);
```

`pw_core*&`, not `pw_core*`. `LinkManager`, `ModuleManager` and `ClientManager`
therefore follow a reassignment of `Manager::core` with no changes of their own.
That removes a whole class of work from the Manager half.

## The seam

`Manager::Manager()` runs `pw_manager.cpp:222-424` and does three separable
things:

| lines | what | on reconnect |
|---|---|---|
| 233-324 | Qt signal connections between the sub-managers and `Manager` | once only — repeating them double-fires every handler |
| 325-334 | `pw_init`, `pw_thread_loop_new`, `pw_thread_loop_start` | once only — the loop outlives the connection |
| **335-424** | context, core, registry, listeners, virtual devices, node wait, stream relink | **this is the reconnectable part** |

The seam is `lock();` at line 335.

One hazard inside it: a `connect(db::Manager::self().main,
&DbMain::activateMonitorChannelVolumesChanged, …)` sits in the middle of that
range, around line 377. It is a Qt connection, belongs to the "once only" group,
and must be hoisted into the constructor before the extraction — otherwise every
reconnection adds another handler.

## Plan

### `pw_manager.{hpp,cpp}`

- Extract lines 335-424 into `auto connect_to_server() -> bool`, hoisting the
  `DbMain` connect out first.
- Extract the connection teardown from `~Manager()` into
  `void disconnect_from_server()`: remove the three hooks, destroy the metadata,
  destroy the two virtual-device proxies and the registry, `pw_core_disconnect`,
  `pw_context_destroy`, then null `core`, `registry` and `context`. Reset
  `ee_sink_node` and `ee_source_node` to `SPA_ID_INVALID` so the next connect
  reloads the virtual devices rather than skipping them.
  **The destructor keeps the thread-loop teardown** — the loop is not part of a
  connection.
- Replace the five startup `util::fatal` calls with `util::critical`, `unlock()`
  where a lock is held, and `return false`. A constructor that cannot connect is
  no longer a dead process; it is a `Manager` with a null core.
- **Bound the virtual-device wait.** The `do { sleep(1ms); } while (id ==
  SPA_ID_INVALID)` at line 380 has no exit when the nodes will never arrive, so
  a failed reconnect hangs the caller forever instead of returning false.
- Add `Q_INVOKABLE void reconnect()` = `disconnect_from_server()` +
  `connect_to_server()`, and on success `Q_EMIT serverReconnected()`.
- Drive it from `on_core_error`, which currently only reports: start a retry
  timer with backoff and keep trying until a connect succeeds. PipeWire is
  usually back within a second or two, but the socket may not be listening at
  the moment the error arrives, so the first attempt will often fail.

### `plugin_base.{hpp,cpp}`

Every plugin owns a `pw_filter*` built against the old core and is stale after
reconnection.

- Extract the filter and port construction from the constructor
  (`pw_filter_new` through the last `pw_filter_add_port`, roughly
  `plugin_base.cpp:345-...`) into `void create_filter()`.
- Add `void rebuild_filter()` = destroy the stale filter, `create_filter()`,
  `connect_to_pw()`.
- Guard `connect_to_pw()`'s `while (!can_get_node_id)` spin. Like the
  virtual-device wait, it has no exit when nothing will ever arrive, and it is
  reached on exactly the path where that is possible.

### `effects_base.cpp`

- Connect to `pm->serverReconnected()`: `rebuild_filter()` on `output_level`,
  `spectrum` and every entry in `plugins`, then relink the pipeline.

## Cost, and whether it belongs here at all

This would be the largest entry in the patch inventory by a wide margin, and it
lands in the least forgiving part of the core: tearing down a connection the
server has already dropped, where the failure mode is a use-after-free that
presents as the process disappearing — the exact symptom `76fe070` just removed.
Every iteration needs a real `systemctl --user restart pipewire`.

**Upstream EasyEffects has the identical bug**, from the identical code. Per
`project.md`, generally useful backend fixes may be offered upstream, and this
is the clearest candidate the project has produced: it is not a 42Hz concern,
it costs upstream nothing to want, and carrying it locally means carrying the
riskiest patch in the inventory across every version bump.

Offering it upstream is not a prerequisite for progress and should not block
milestone 3. But the choice between *carry it* and *contribute it* should be
made deliberately before the code is written, not discovered afterwards.
