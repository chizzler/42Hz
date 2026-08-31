#!/usr/bin/env bash
# Milestone 2's responsive verification: put the window at a series of exact
# geometries and capture each one.
#
# Requires a nested session with 42Hz running inside it:
#
#     ./spike/nested-session.sh start
#     ./spike/nested-session.sh run ./build-debug/42hz --debug &
#     ./spike/geometry-sweep.sh [OUTDIR]
#
# Play something first. An empty spectrum verifies the empty-state report and
# nothing about layout.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NESTED="$HERE/nested-session.sh"
OUT="${1:-$HERE/../.sweep}"

# A keypress raises a toast that fades over ~1.6s. Shooting sooner captures the
# toast instead of the layout, so every mode change pays this once.
TOAST_SETTLE=2.0

# Resizes are not instantaneous to the client: the compositor grants the size,
# then QML relayouts and the spectrum resamples on its next frame.
RELAYOUT_SETTLE=1.0

n=0

nest() { "$NESTED" "$@"; }

# The nested output is a window in the parent session, so its size is whatever
# the parent's layout granted and is not the same twice. Every geometry is
# therefore clamped to it, and the largest case is the output itself -- a sweep
# that hard-codes a size it cannot get produces captions that lie.
read -r OUTW OUTH < <(nest ctl monitors -j | jq -r '.[0] | "\(.width) \(.height)"')

# Clamping is what keeps a caption honest; it is not a way to run the sweep on
# an output that cannot hold it. On a busy parent workspace the nested output
# is a tile a few hundred pixels wide, every geometry below clamps to that one
# size, and the sweep completes with twenty-one correctly labelled captures of
# the same window. Refuse instead: the widest and tallest cases must be
# distinguishable or there is nothing to look at.
NEEDW=1200
NEEDH=600
if (( OUTW < NEEDW || OUTH < NEEDH )); then
    echo "nested output is ${OUTW}x${OUTH}; the sweep needs at least ${NEEDW}x${NEEDH}." >&2
    echo "Every geometry would clamp to the output and each capture would be the same window." >&2
    echo "Run 'spike/nested-session.sh expand' to fullscreen it on the parent, then retry." >&2
    exit 1
fi

clamp() {
    local w="${1%x*}" h="${1#*x}"
    echo "$(( w < OUTW ? w : OUTW ))x$(( h < OUTH ? h : OUTH ))"
}

# Chrome selection is by absolute key (1 = bare, 2 = framed) rather than the
# cycling `f`, so a sweep cannot drift out of step with the mode it thinks it
# is in. The mixer has no absolute key, so Escape normalises it closed first.
set_mode() {
    local chrome="$1" mixer="$2"

    nest key -k Escape
    case "$chrome" in
        bare)   nest key -k 1 ;;
        framed) nest key -k 2 ;;
        *) echo "unknown chrome: $chrome" >&2; exit 1 ;;
    esac
    [[ "$mixer" == open ]] && nest key s
    sleep "$TOAST_SETTLE"
}

shot() {
    local label="$1" granted="$2"
    n=$((n + 1))
    local file
    file="$(printf '%s/%02d-%s-%s.png' "$OUT" "$n" "$label" "$granted")"
    nest shot "$file" > /dev/null
    printf '  %-34s %s\n' "$label" "$granted"
}

# One geometry, already in the right mode.
at() {
    local label="$1" geom
    geom="$(clamp "$2")"
    local granted
    granted="$(nest window "$geom")"
    sleep "$RELAYOUT_SETTLE"
    shot "$label" "$granted"
}

mkdir -p "$OUT"
rm -f "$OUT"/*.png

status="$(nest status)"
echo "${status%%$'\n'*}"
echo

# The geometries are chosen to break things rather than to look plausible:
# wider than tall by 10:1, taller than wide, and small enough that the frame,
# the legend and the state report cannot all fit.
echo "framed, mixer closed"
set_mode framed closed
at framed "${OUTW}x${OUTH}"
at framed 1200x120
at framed 900x400
at framed 640x260
at framed 320x180
at framed 240x600
at framed 200x100
at framed 160x60

echo
echo "framed, mixer open"
set_mode framed open
at framed-mixer "${OUTW}x${OUTH}"
at framed-mixer 640x260
at framed-mixer 480x200
at framed-mixer 320x180
at framed-mixer 240x600

echo
echo "bare"
set_mode bare closed
at bare "${OUTW}x${OUTH}"
at bare 640x260
at bare 200x100
at bare 160x60

echo
echo "bare, mixer open"
set_mode bare open
at bare-mixer 640x260
at bare-mixer 320x180

echo
echo "window states"
set_mode framed closed
nest state tiled > /dev/null
sleep "$RELAYOUT_SETTLE"
shot tiled "$(nest ctl clients -j | jq -r '.[0] | "\(.size[0])x\(.size[1])"')"

nest state fullscreen > /dev/null
sleep "$RELAYOUT_SETTLE"
shot fullscreen "$(nest ctl clients -j | jq -r '.[0] | "\(.size[0])x\(.size[1])"')"

nest state floating > /dev/null

echo
echo "$n captures in $OUT"
