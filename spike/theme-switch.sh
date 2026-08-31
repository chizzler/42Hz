#!/usr/bin/env bash
# Switch the theme under a *running* 42Hz, and capture what it does.
#
# theme-preview.sh restarts 42Hz once per theme, which verifies that a theme
# resolves correctly and says nothing at all about switching. The thing
# milestone 2 asks for is different: the palette, the typography and the
# spectrum ramp following a switch on a process that stays up, while audio is
# flowing.
#
# The obstacle was that theme state is machine-global, so testing a real switch
# looked like it meant switching the user's desktop. It does not. The adapter
# resolves its state path from QDir::homePath(), and `omarchy-theme-set` swaps
# themes with two filesystem operations:
#
#     rm -rf  ~/.local/state/omarchy/current/theme
#     mv      ~/.local/state/omarchy/current/next-theme  .../theme
#
# The watcher cannot tell who performed those, so performing them inside a fake
# HOME is the same event. That is what this does. The running desktop is never
# touched and no theme is ever set.
#
#   ./spike/nested-session.sh start
#   ./spike/theme-switch.sh OUTDIR [theme ...]
#
# Play something first. A themed spectrum with no signal is a themed blank, and
# "under load" is half of what is being tested.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NESTED="$HERE/nested-session.sh"
THEMES=/usr/share/omarchy/themes

OUT="${1:?usage: theme-switch.sh OUTDIR [theme ...]}"
shift || true

# Ordered to cross every boundary that matters: dark to light, light to dark,
# a theme whose whole identity is one accent, and a genuinely monochrome one
# that must stay monochrome.
SET=("$@")
[[ ${#SET[@]} -eq 0 ]] && SET=(tokyo-night catppuccin-latte matte-black flexoki-light vantablack gruvbox tokyo-night)

HOME_DIR="$OUT/.home"
STATE="$HOME_DIR/.local/state/omarchy/current"

mkdir -p "$OUT"
rm -rf "$HOME_DIR"
mkdir -p "$STATE/theme" "$HOME_DIR/.config/omarchy"

# Only the files the adapter reads, so a run cannot accidentally depend on
# something else a theme directory happens to carry.
install_theme() {
    local theme="$1" dest="$2"
    local src="$THEMES/$theme"

    [[ -d "$src" ]] || { echo "no such theme: $theme" >&2; return 1; }

    mkdir -p "$dest"
    cp "$src/colors.toml" "$dest/" 2>/dev/null || true
    [[ -f "$src/shell.toml" ]] && cp "$src/shell.toml" "$dest/"
    return 0
}

# Exactly what omarchy-theme-set does, in the same order: build the replacement
# beside the live one, destroy the live one, rename over it, then write the
# name. The rm/mv pair is the whole point -- a watcher on `theme/` or on
# colors.toml is dropped by it and never recovers, which is why the adapter
# watches the parent.
swap_to() {
    local theme="$1"

    rm -rf "$STATE/next-theme"
    install_theme "$theme" "$STATE/next-theme" || return 1

    rm -rf "$STATE/theme"
    mv "$STATE/next-theme" "$STATE/theme"
    echo "$theme" > "$STATE/theme.name"
}

# HOME alone does not isolate a run on this machine.
#
# The theme adapter resolves its state path from QDir::homePath(), so HOME is
# enough for *theming*. 42Hz's settings do not go that way: they go through
# QStandardPaths, which honours XDG_CONFIG_HOME when it is set -- and Omarchy
# sets it. So a fake HOME redirected the theme and left every run reading and
# writing the user's real ~/.config/42hz, which is how a profile applied in one
# test turned up in the next. spike-02 fenced all four of these explicitly; the
# theme harness was written later and relied on HOME alone, which is not the
# same thing.
fence() {
    env HOME="$HOME_DIR" \
        XDG_CONFIG_HOME="$HOME_DIR/.config" \
        XDG_STATE_HOME="$HOME_DIR/.local/state" \
        XDG_DATA_HOME="$HOME_DIR/.local/share" \
        XDG_CACHE_HOME="$HOME_DIR/.cache" \
        "$@"
}

# What a theme switch must not do. The adapter is frontend-only and touches no
# PipeWire object, so this should be constant across every switch -- and if the
# sink ever stops running mid-sweep, the captures after that point are of a
# state report rather than of a theme.
sink_state() { pactl list short sinks 2>/dev/null | awk '$2 == "42hz_sink" { print $NF }'; }

install_theme "${SET[0]}" "$STATE/theme"
echo "${SET[0]}" > "$STATE/theme.name"

for p in $(pgrep -x 42hz 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done
sleep 1

fence setsid nohup "$NESTED" run "$HERE/../build-debug/42hz" --debug \
    > "$OUT/42hz.log" 2>&1 < /dev/null &

for _ in $(seq 40); do
    "$NESTED" ctl clients -j 2>/dev/null | grep -q 'io.github.chizzler.42Hz' && break
    sleep 0.25
done
sleep 2

"$NESTED" expand > /dev/null
"$NESTED" window 720x300 > /dev/null
sleep 1

# Under load is half of what this verifies, and starting 42Hz destroyed the
# sink whatever was playing had been captured into -- mpv goes idle and stays
# there, a browser destroys its output node. So wait for something to be
# playing again rather than photographing a themed blank and calling it a
# themed spectrum.
# RUNNING, not merely linked. A stream that has been captured but is corked or
# paused leaves the sink IDLE and the output pipeline unlinked -- upstream drops
# its filters when no app linked to the device wants to play -- so the window
# correctly reports `processing stopped` and every capture is of that report
# rather than of a themed spectrum.
echo "waiting for 42hz_sink to run..."
sink_running() {
    pactl list short sinks 2>/dev/null | awk '$2 == "42hz_sink" { print $NF }' | grep -q RUNNING
}

for _ in $(seq 120); do
    sink_running && break
    sleep 0.5
done

if ! sink_running; then
    echo "42hz_sink is not RUNNING; every capture would be a themed blank." >&2
    echo "Start a stream that is actually playing, then re-run." >&2
    exit 1
fi

before="$(sink_state)"
n=0

shot() {
    n=$((n + 1))
    local file
    file="$(printf '%s/%02d-%s.png' "$OUT" "$n" "$1")"

    # Re-asserted per capture rather than once at the start. A sweep long
    # enough to switch six themes is long enough for something on the parent to
    # take focus and drop this session out of fullscreen, and the captures
    # after that point are of a window hanging off the edge of its own output.
    "$NESTED" expand > /dev/null
    "$NESTED" shot "$file" > /dev/null
    printf '  %-22s %s\n' "$1" "$(sink_state)"
}

shot "${SET[0]}"

for theme in "${SET[@]:1}"; do
    swap_to "$theme" || continue

    # The adapter coalesces a burst into one reload at 100 ms; a capture taken
    # before that has fired is a capture of the previous theme.
    sleep 1.5
    shot "$theme"
done

# A burst with no settling between swaps. The adapter coalesces at 100 ms, so
# one reload should come out the far end on the last theme -- not one per swap,
# and not a watcher left holding paths that three rm -rf's ago stopped existing.
echo
echo "burst of ${#SET[@]}, no settling"
for theme in "${SET[@]}"; do
    swap_to "$theme" || true
done
sleep 2
shot "burst-ends-on-${SET[-1]}"

# And one more switch afterwards, which is the part that actually proves the
# watcher survived the burst rather than merely that the last swap won. It has
# to be a *different* theme from the one the burst ended on, or the capture is
# the same picture either way and says nothing.
after=""
for theme in "${SET[@]}"; do
    [[ "$theme" != "${SET[-1]}" ]] && { after="$theme"; break; }
done

if [[ -n "$after" ]]; then
    swap_to "$after"
    sleep 1.5
    shot "after-burst-$after"
fi

echo
echo "42hz_sink before: $before"
echo "42hz_sink after:  $(sink_state)"

for p in $(pgrep -x 42hz 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done
echo "$n captures in $OUT"
