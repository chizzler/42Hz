import QtQuick
import ee.ui

// Dot-matrix spectrum: a column is a stack of discrete painted dots, lit from
// the bottom up to the level, and coloured along the theme's ramp by where each
// dot sits rather than by how tall its column is.
//
// This is the third appearance, and the one that is neither of the other two.
// Bars draw a continuous quantity; cells draw one quantised to a character
// grid and inherit the font's geometry along with it. Dots own their lattice
// outright -- radius and pitch come from the density control, not from
// `monospace` -- which is what buys the even spacing a character grid cannot
// give and the visible separation a filled bar will not.
//
// Nothing unlit is drawn. An LED matrix shows its dark dots because it has
// them whether it likes it or not; this has the choice, and a faint dot in
// every unlit position would put a permanent picture across the window. 42Hz
// reports silence in words in an empty window, and a resting lattice would be
// the one thing on screen contradicting that.
//
// The dB window is SpectrumScale's, shared with the other two styles: cycling
// appearance must never look like the signal changed.
Canvas {
    id: matrix

    // Latest frame from the core. Points are pre-resampled to DbSpectrum.nPoints.
    property var points: []

    property color lowColor: Theme.spectrumLow
    property color highColor: Theme.spectrumHigh

    // Target width of one column, and with it the pitch of the lattice: the
    // dots are laid out square, so the density control sets the vertical
    // spacing as well as the horizontal one. Two controls for one lattice
    // would let the user build a grid of ellipses out of a control labelled
    // density.
    property int barWidth: 10

    // Floored, because a lattice finer than a few pixels stops being dots. The
    // control is still honoured -- it just cannot ask for a dot smaller than
    // one that reads as a dot.
    readonly property real pitch: Math.max(4, matrix.barWidth)

    onWidthChanged: matrix.applyPointCount()
    onBarWidthChanged: matrix.applyPointCount()
    Component.onCompleted: matrix.applyPointCount()

    // One column per point, as the other two styles do, so the core resamples
    // to what fits instead of the renderer stretching what it is given.
    function applyPointCount() {
        DbSpectrum.nPoints = Math.max(2, Math.min(2048, Math.floor(width / Math.max(1, matrix.pitch))));
    }

    onPointsChanged: requestPaint()

    // Repaint on a theme change as well as on new data, or the spectrum keeps
    // the old palette until the next frame -- which, with no audio, is never.
    Connections {
        target: Theme
        function onChanged() {
            matrix.requestPaint();
        }
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();

        const pts = matrix.points;
        const n = pts.length;
        if (n === 0)
            return;

        // Hoisted: these are bindings, and this loop runs at 60 Hz.
        const cLo = matrix.lowColor;
        const cHi = matrix.highColor;
        const floorDb = SpectrumScale.floorDb;
        const rangeDb = SpectrumScale.rangeDb;

        const pitch = matrix.pitch;
        const colPitch = width / n;

        // Whole rows only, aligned to the bottom edge. A partial row at the
        // top would be a clipped dot, and a lattice standing off its own floor
        // would put the same level at a different height from the bars.
        const rows = Math.max(1, Math.floor(height / pitch));
        const base = height;

        // Sized against whichever pitch is tighter, so a dot never touches its
        // neighbour in the narrow direction -- the separation is the whole
        // point of this style, and a lattice of overlapping circles is a bar
        // renderer with extra steps.
        const radius = Math.max(1, Math.min(pitch, colPitch) * 0.34);

        for (let i = 0; i < n; i++) {
            const norm = Math.max(0, Math.min(1, (pts[i].y - floorDb) / rangeDb));

            // At the floor there is no column. Lighting the bottom dot instead
            // would draw a permanent row across the window that reads as
            // signal, and silence is reported in words rather than drawn.
            if (norm <= 0)
                continue;

            const lit = norm * rows;
            const whole = Math.min(rows, Math.floor(lit));
            const frac = lit - whole;
            const cx = (i + 0.5) * colPitch;

            // The tip dot is drawn at the fraction's opacity rather than
            // rounded in or out. Rounding is what makes a dot matrix strobe:
            // the top of a column crossing a lattice boundary pops a whole dot
            // in and out, and at 60 Hz that reads as noise on top of the
            // signal rather than as the signal moving.
            const top = whole < rows && frac > 0 ? whole + 1 : whole;

            for (let d = 0; d < top; d++) {
                // Ramp position is the dot's own place in the dB window, not
                // its column's height. That is what makes the gradient a
                // property of the picture rather than of each column
                // separately -- every dot at a given height is the same
                // colour, so the ramp reads across the whole spectrum.
                const t = rows > 1 ? d / (rows - 1) : 1;
                const a = d < whole ? 1 : frac;

                ctx.fillStyle = Qt.rgba(cLo.r + (cHi.r - cLo.r) * t, cLo.g + (cHi.g - cLo.g) * t, cLo.b + (cHi.b - cLo.b) * t, a);
                ctx.beginPath();
                ctx.arc(cx, base - (d + 0.5) * pitch, radius, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
    }
}
