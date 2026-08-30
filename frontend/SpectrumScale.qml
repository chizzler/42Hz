pragma Singleton

import QtQuick

// The dB window the spectrum is drawn in, and the one place that knows it.
//
// The core delivers each point as a magnitude in dB, referenced to full scale
// and clamped at -100 by `util::linear_to_db`. Those are absolute levels, and
// 42Hz draws them as absolute levels: a bar's height is what the signal is
// doing, not what it is doing relative to the rest of the frame.
//
// The frontend used to rescale every frame to its own minimum and maximum,
// which made the display span full height at all times. It was livelier and it
// was a lie -- quiet passages and loud ones were pixel-identical, and the
// resting surface never rested. Quiet audio now looks quiet, at the cost of
// the ramp's top colours appearing only when something is actually loud.
//
// The window is shared rather than owned by the renderer because the state
// report needs the same floor: silence is reported exactly when every point
// falls below the level at which a bar would be drawn, so the message appears
// precisely when there would otherwise be nothing on screen.
QtObject {
    // Full height. A 0 dBFS sine reads -6 dB here, not 0: the core mixes to
    // mono as 0.5 * (L + R) and compensates the Hann window's coherent gain
    // with a factor of 2, which leaves a half. Anchoring the ceiling there
    // means a full-scale signal fills the window exactly and nothing ever
    // clips.
    readonly property real ceilingDb: -6

    // Nothing drawn. Set above the core's -100 clamp so the clamp itself lands
    // at the bottom of the window rather than below it, and below the quietest
    // content worth showing -- pink noise at -60 dBFS RMS still peaks around
    // -87 dB per point and stays visible.
    readonly property real floorDb: -90

    readonly property real rangeDb: ceilingDb - floorDb

    // Level to bar height, 0..1. Clamped at both ends: the floor is where a
    // bar disappears, and the ceiling is full height.
    function normalize(db) {
        return Math.max(0, Math.min(1, (db - floorDb) / rangeDb));
    }
}
