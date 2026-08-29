import QtQuick
import ee.ui

// Pixel spectrum: one filled bar per point, coloured along the theme's ramp by
// amplitude. Knows nothing about layout -- whoever instantiates it decides how
// much room it gets.
Canvas {
    id: canvas

    // Latest frame from the core. Points are pre-resampled to DbSpectrum.nPoints.
    property var points: []

    property color lowColor: Theme.spectrumLow
    property color highColor: Theme.spectrumHigh

    // Gap between bars, in pixels. 0 reads as a continuous band.
    property real gap: 1

    // Target width of one bar. The core resamples to however many bars fit,
    // so the spectrum has the same density at every window size instead of
    // stretching. This is the responsive resampling project.md describes --
    // a settings binding, not new DSP.
    property int barWidth: 10

    onWidthChanged: canvas.applyPointCount()
    onBarWidthChanged: canvas.applyPointCount()
    Component.onCompleted: canvas.applyPointCount()

    function applyPointCount() {
        DbSpectrum.nPoints = Math.max(2, Math.min(2048, Math.floor(width / Math.max(1, barWidth))));
    }

    onPointsChanged: requestPaint()

    // Repaint on a theme change as well as on new data, or the spectrum keeps
    // the old palette until the next frame -- which, with no audio, is never.
    Connections {
        target: Theme
        function onChanged() {
            canvas.requestPaint();
        }
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();

        const pts = canvas.points;
        const n = pts.length;
        if (n === 0)
            return;

        let lo = Infinity, hi = -Infinity;
        for (let i = 0; i < n; i++) {
            const v = pts[i].y;
            if (v < lo)
                lo = v;
            if (v > hi)
                hi = v;
        }
        const span = (hi - lo) > 1e-6 ? (hi - lo) : 1;

        // Hoisted: these are bindings, and the ramp is interpolated in JS
        // rather than per-bar through C++, which this loop runs at 60 Hz.
        const cLo = canvas.lowColor;
        const cHi = canvas.highColor;
        const bw = width / n;

        for (let i = 0; i < n; i++) {
            const norm = (pts[i].y - lo) / span;
            ctx.fillStyle = Qt.rgba(cLo.r + (cHi.r - cLo.r) * norm, cLo.g + (cHi.g - cLo.g) * norm, cLo.b + (cHi.b - cLo.b) * norm, 1);
            ctx.fillRect(i * bw, height - norm * height, Math.max(1, bw - canvas.gap), norm * height);
        }
    }
}
