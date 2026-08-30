#!/usr/bin/env bash
# Render 42Hz under a series of Omarchy themes, without changing the one the
# user is running.
#
# The theme adapter resolves its state path from QDir::homePath(), so a fake
# HOME containing nothing but ~/.local/state/omarchy/current/theme is enough to
# put 42Hz on any theme in /usr/share/omarchy/themes. The real desktop never
# changes, no theme is switched, and 42Hz's own settings land in the fake home
# too -- which is the isolation spike-02 had to build by hand.
#
#   ./spike/nested-session.sh start
#   ./spike/theme-preview.sh OUTDIR [theme ...]
#
# With no theme names it renders a spread across light, dark and monochrome.
# Play something first; a themed spectrum with no signal is a themed blank.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NESTED="$HERE/nested-session.sh"
THEMES=/usr/share/omarchy/themes

OUT="${1:?usage: theme-preview.sh OUTDIR [theme ...]}"
shift || true

# A spread rather than everything: two light, one where the accent is the whole
# identity, one genuinely monochrome, and the two the desktop actually uses.
DEFAULT_SET=(tokyo-night matte-black catppuccin-latte flexoki-light vantablack gruvbox)
SET=("$@")
[[ ${#SET[@]} -eq 0 ]] && SET=("${DEFAULT_SET[@]}")

mkdir -p "$OUT"

for theme in "${SET[@]}"; do
    src="$THEMES/$theme"
    [[ -d "$src" ]] || { echo "no such theme: $theme" >&2; continue; }

    home="$OUT/.home-$theme"
    rm -rf "$home"
    mkdir -p "$home/.local/state/omarchy/current/theme" "$home/.config/omarchy"

    # Only the two files the adapter reads, so a preview cannot accidentally
    # depend on anything else a theme directory happens to carry.
    cp "$src/colors.toml" "$home/.local/state/omarchy/current/theme/" 2>/dev/null || true
    [[ -f "$src/shell.toml" ]] && cp "$src/shell.toml" "$home/.local/state/omarchy/current/theme/"
    echo "$theme" > "$home/.local/state/omarchy/current/theme.name"

    for p in $(pgrep -x 42hz 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done
    sleep 1

    HOME="$home" setsid nohup "$NESTED" run "$HERE/../build-debug/42hz" --debug \
        > "$OUT/$theme.log" 2>&1 < /dev/null &

    # Wait for the window rather than guessing: a themed capture of a window
    # that has not appeared is a capture of the previous theme.
    for _ in $(seq 40); do
        "$NESTED" ctl clients -j 2>/dev/null | grep -q 'io.github.chizzler.42Hz' && break
        sleep 0.25
    done
    sleep 2

    "$NESTED" window 720x300 > /dev/null
    sleep 1
    "$NESTED" shot "$OUT/$theme.png" > /dev/null
    printf '  %-20s %s\n' "$theme" "$OUT/$theme.png"
done

for p in $(pgrep -x 42hz 2>/dev/null || true); do kill "$p" 2>/dev/null || true; done
echo "done"
