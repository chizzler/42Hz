#!/usr/bin/env bash
# What 42Hz does when the audio service goes away, and what it leaves behind
# when it is killed.
#
# Milestone 5 asks for two things that cannot be checked by looking at a
# window: that losing PipeWire is survived and reported rather than fatal, and
# that nothing of 42Hz outlives the process -- forced termination included.
#
# Both are destructive by nature, so the default mode brings its OWN PipeWire.
# A private daemon in its own runtime directory, with one null sink and no
# device monitors, is a complete graph that 42Hz connects to exactly as it
# connects to the session's: it loads its virtual devices, builds its filters
# and never sees a real card. Killing that daemon is then a service failure
# with no consequences for the desktop, which is the only way this test is
# worth running twice.
#
#   ./spike/recovery.sh              private graph; the whole suite, no risk
#   ./spike/recovery.sh --desktop    ALSO the default-route test, on the
#                                    session's own PipeWire (see below)
#
# --desktop is the one thing the private graph cannot answer. "The default
# route must never be left pointing at a dead 42Hz node" is a claim about what
# the SESSION MANAGER does when the node disappears, and the private daemon
# deliberately runs without one. So that check sets the session default to
# 42hz_sink, kills 42Hz outright, and looks at what the desktop settles on. It
# restores the original default on every exit path, but it does move the
# desktop's audio for a second or two, so it is opt-in.
#
# Read the log this prints, not just the exit status: some of what it asserts
# is a documented LIMITATION rather than a fix, and if one of those ever starts
# passing differently that is news.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
BIN="${HZ_BIN:-$ROOT/build/42hz}"

# Short, because a unix socket path is capped at 108 bytes and a scratch
# directory under /tmp/claude-*/... is already most of that.
RUN="${XDG_RUNTIME_DIR:-/tmp}/42hz-recovery"
CONF="$RUN/pipewire.conf"
# 42Hz's stored settings are not this test's business, and a first launch would
# otherwise write over a populated equalizerrc.
FENCE="$RUN/config"

REMOTE=42hz-recovery
SINK=42hz_sink

DESKTOP=0
[[ ${1:-} == --desktop ]] && DESKTOP=1

pass=0
fail=0

ok()   { echo "  ok    $*"; pass=$((pass + 1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail + 1)); }
note() { echo "        $*"; }
step() { echo; echo "$*"; }

[[ -x $BIN ]] || { echo "no 42Hz binary at $BIN -- build it, or set HZ_BIN" >&2; exit 1; }

# The single-instance lock is session-global and does not care which PipeWire
# an instance is talking to: with one already running, every 42Hz this harness
# starts exits immediately as a secondary instance, and every check below then
# measures nothing. It is a silent failure -- the secondary exits 0.
# Zombies are excluded deliberately: a reaped-but-not-yet-collected 42Hz still
# matches by name and holds no lock.
running=$(ps -C 42hz -o pid=,stat= 2>/dev/null | awk '$2 !~ /Z/ { print $1 }')
if [[ -n $running ]]; then
    echo "a 42Hz instance is already running (pid $running) -- quit it first" >&2
    exit 1
fi

# --------------------------------------------------------------------------
# the private graph
# --------------------------------------------------------------------------

# module-access is not optional here, and its absence is silent: without it a
# client connects, receives no permissions, and hangs waiting for a registry
# that never arrives. Every other module below is the minimum a client node
# needs to exist and be linked.
write_conf() {
    mkdir -p "$RUN" "$FENCE"
    cat > "$CONF" <<EOF
context.properties = { core.daemon = true, core.name = $REMOTE }

context.spa-libs = {
  audio.convert.* = audioconvert/libspa-audioconvert
  support.*       = support/libspa-support
}

context.modules = [
  { name = libpipewire-module-rt }
  { name = libpipewire-module-protocol-native }
  { name = libpipewire-module-access }
  { name = libpipewire-module-metadata }
  { name = libpipewire-module-spa-node-factory }
  { name = libpipewire-module-client-node }
  { name = libpipewire-module-client-device }
  { name = libpipewire-module-adapter }
  { name = libpipewire-module-link-factory }
]

# One sink, so the graph has somewhere to route to. No device monitors: this
# daemon must never touch the machine's sound card.
context.objects = [
  { factory = adapter
    args = {
      factory.name       = support.null-audio-sink
      node.name          = "recovery_sink"
      node.description   = "42Hz recovery test sink"
      media.class        = "Audio/Sink"
      audio.position     = "FL,FR"
      object.linger      = true
    }
  }
]
EOF
}

private() { PIPEWIRE_RUNTIME_DIR="$RUN" PIPEWIRE_REMOTE="$REMOTE" "$@"; }

start_service() {
    # A daemon that finds its socket name taken quietly binds the NEXT one
    # ("-manager") and keeps running, so a leftover daemon from an earlier run
    # would go on answering every client here while this script killed and
    # restarted something nothing was talking to. That mistake reads as 42Hz
    # reconnecting after a service restart, which is a claim project.md
    # explicitly denies -- so refuse to start on top of one.
    if private timeout 3 pw-dump >/dev/null 2>&1; then
        echo "something is already serving $REMOTE in $RUN -- kill it first:" >&2
        pgrep -af "pipewire -c $CONF" >&2
        exit 1
    fi

    # Env inline rather than through private(): backgrounding a function
    # makes $! the subshell that wraps it, and killing that leaves the daemon
    # running and answering.
    PIPEWIRE_RUNTIME_DIR="$RUN" PIPEWIRE_REMOTE="$REMOTE" \
        pipewire -c "$CONF" > "$RUN/pipewire.log" 2>&1 &
    SERVICE_PID=$!
    wait_for "the private service" 'private timeout 3 pw-dump >/dev/null 2>&1'
}

stop_service() {
    [[ -n ${SERVICE_PID:-} ]] || return 0
    kill -9 "$SERVICE_PID" 2>/dev/null
    wait "$SERVICE_PID" 2>/dev/null
    SERVICE_PID=
    wait_for "the service to stop answering" '! private timeout 2 pw-dump >/dev/null 2>&1'
}

start_42hz() {
    XDG_CONFIG_HOME="$FENCE" PIPEWIRE_RUNTIME_DIR="$RUN" PIPEWIRE_REMOTE="$REMOTE" \
        "$BIN" > "$RUN/42hz.log" 2>&1 &
    HZ_PID=$!

    wait_for "42Hz's own nodes" "[[ \$(node_count) -gt 0 ]]" || return 1

    # The graph arrives in pieces. Waiting for the first node would report
    # whatever moment the read caught, so wait for the count to stop moving.
    local last=-1 now i
    for ((i = 0; i < 50; i++)); do
        now=$(node_count)
        [[ $now == "$last" ]] && return 0
        last=$now
        sleep 0.1
    done
}

# Nothing here may sleep for a fixed time: a graph that is slow once is a false
# failure, and a graph that is fast every other time is a wasted second.
wait_for() {
    local what="$1" test="$2" i
    for ((i = 0; i < 100; i++)); do
        eval "$test" && return 0
        sleep 0.1
    done
    bad "timed out waiting for $what"
    return 1
}

# Every node 42Hz owns: its two virtual devices and its DSP filters.
nodes() {
    private timeout 3 pw-dump 2>/dev/null |
        python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for o in d:
    if o.get("type") == "PipeWire:Interface:Node":
        n = o.get("info", {}).get("props", {}).get("node.name", "")
        if n.startswith("42hz_") or n.startswith("hz_"):
            print(n)
'
}

node_count() { nodes | wc -l; }

alive() { [[ -n ${HZ_PID:-} ]] && kill -0 "$HZ_PID" 2>/dev/null; }

SAVED_DEFAULT=

restore_default() {
    [[ -n $SAVED_DEFAULT ]] || return 0
    wpctl set-default "$(sink_id "$SAVED_DEFAULT")" 2>/dev/null
    echo "        restored the default sink to $SAVED_DEFAULT"
    SAVED_DEFAULT=
}

default_sink() { pw-metadata -n default 2>/dev/null | sed -n "s/.*'default.audio.sink' value:'{\"name\":\"\([^\"]*\)\".*/\1/p" | tail -1; }

sink_id() {
    pw-dump 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
for o in json.load(sys.stdin):
    if o.get("type") == "PipeWire:Interface:Node":
        p = o.get("info", {}).get("props", {})
        if p.get("node.name") == name:
            print(o["id"])
            break
' "$1"
}

live_node() { [[ -n $(sink_id "$1") ]]; }

cleanup() {
    [[ -n ${HZ_PID:-} ]] && kill -9 "$HZ_PID" 2>/dev/null
    stop_service
    restore_default
}
trap cleanup EXIT

# --------------------------------------------------------------------------
# the suite
# --------------------------------------------------------------------------

echo "42Hz recovery -- $BIN"
echo "private graph in $RUN"

write_conf
start_service || exit 1

step "1. 42Hz builds its graph in the private service"
start_42hz
built=$(nodes | paste -sd' ')
n=$(wc -w <<< "$built")
if [[ $n -gt 0 ]]; then
    ok "$n nodes: $built"
else
    bad "42Hz created no nodes; nothing below would mean anything"
    exit 1
fi

step "2. the audio service dies under it"
# The defect this closes: on_core_error called util::fatal on "connection
# error", so a service restart took 42Hz with it.
stop_service
if alive; then
    ok "42Hz survived losing PipeWire"
else
    bad "42Hz died with the audio service -- the on_core_error patch has regressed"
fi

step "3. the audio service comes back"
start_service
n=$(node_count)
if ! alive; then
    bad "42Hz died after the service returned"
elif [[ $n -eq 0 ]]; then
    ok "42Hz stayed up and did not rebuild its nodes"
    note "this is the DOCUMENTED limitation, not a fix: 42Hz does not reconnect,"
    note "and recovery is a manual restart. See project.md, Runtime states."
else
    ok "42Hz rebuilt $n nodes after the service returned"
    note "NEWS: 42Hz reconnected. project.md says it cannot -- update it, and"
    note "check docs/spike-05-reconnection.md before believing this."
fi

# Each of these needs an instance that actually OWNS nodes. The one left over
# from step 3 is disconnected and owns nothing, so killing it would prove
# nothing at all -- the assertion would pass on an empty graph.
discard() {
    [[ -n ${HZ_PID:-} ]] || return 0
    kill -9 "$HZ_PID" 2>/dev/null
    wait "$HZ_PID" 2>/dev/null
    HZ_PID=
}

exits_clean() {
    local signal="$1"

    discard
    start_42hz

    if [[ $(node_count) -eq 0 ]]; then
        bad "no nodes to remove before $signal; the check would pass vacuously"
        return 1
    fi

    kill -"$signal" "$HZ_PID" 2>/dev/null
    wait "$HZ_PID" 2>/dev/null
    HZ_PID=

    wait_for "the graph to drop 42Hz's nodes" "[[ \$(node_count) -eq 0 ]]" &&
        ok "no 42Hz nodes remain after $signal"
}

step "4. forced termination leaves nothing behind"
exits_clean KILL

step "5. a graceful quit leaves nothing behind"
exits_clean TERM

stop_service

# --------------------------------------------------------------------------
# the desktop's default route -- opt-in, and restored
# --------------------------------------------------------------------------

if [[ $DESKTOP -eq 1 ]]; then
    step "6. the desktop is not left routed at a dead 42Hz node"

    SAVED_DEFAULT=$(default_sink)
    [[ -n $SAVED_DEFAULT ]] || { bad "could not read the session's default sink"; SAVED_DEFAULT=; }

    if [[ -n $SAVED_DEFAULT ]]; then
        note "session default is $SAVED_DEFAULT"

        XDG_CONFIG_HOME="$FENCE" "$BIN" > "$RUN/42hz-desktop.log" 2>&1 &
        HZ_PID=$!

        if wait_for "42Hz's sink on the session graph" "live_node $SINK"; then
            wpctl set-default "$(sink_id $SINK)"

            if wait_for "the default to become $SINK" "[[ \$(default_sink) == $SINK ]]"; then
                kill -9 "$HZ_PID" 2>/dev/null
                wait "$HZ_PID" 2>/dev/null
                HZ_PID=

                if wait_for "a live default sink" '[[ -n $(default_sink) ]] && live_node "$(default_sink)"'; then
                    ok "the desktop settled on $(default_sink), which exists"
                else
                    bad "the default is $(default_sink), which is not a node in the graph"
                fi
            fi
        fi
    fi
else
    step "6. the desktop's default route -- skipped"
    note "run with --desktop to include it. It moves the session's default sink"
    note "for a second or two, and puts it back."
fi

echo
echo "$pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
