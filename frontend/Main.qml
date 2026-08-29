import QtQuick
import QtQuick.Window
import ee.ui

// Placeholder shell: a live spectrum on the active Omarchy palette. Every
// colour and the type face come from Theme, which tracks the theme live --
// nothing here is a hard-coded appearance.
Window {
    id: root

    // supplied via engine.setInitialProperties() in main.cpp
    property string applicationName: "42Hz"
    property string applicationId: "io.github.chizzler.42Hz"
    property bool canUseSysTray: false

    width: 480
    height: 200
    visible: true
    title: root.applicationName
    color: Theme.background

    property var points: []

    Connections {
        target: StreamOutputEffects
        function onNewSpectrumData(newData) {
            root.points = newData;
            canvas.requestPaint();
        }
    }

    Timer {
        interval: 1000 / 60
        running: true
        repeat: true
        onTriggered: StreamOutputEffects.requestSpectrumData()
    }

    // Repaint on a theme change as well as on new data, or the spectrum keeps
    // the old palette until the next frame arrives -- which, with no audio
    // playing, is never.
    Connections {
        target: Theme
        function onChanged() {
            canvas.requestPaint();
        }
    }

    Canvas {
        id: canvas

        anchors.fill: parent
        anchors.margins: 8

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const pts = root.points;
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

            // Hoisted: these are bindings, and the ramp is interpolated in
            // JS rather than per-bar through C++, which this loop runs at 60 Hz.
            const cLo = Theme.spectrumLow;
            const cHi = Theme.spectrumHigh;
            const bw = width / n;

            for (let i = 0; i < n; i++) {
                const norm = (pts[i].y - lo) / span;
                // Quiet bins sit near the floor colour, peaks reach the top of
                // the ramp, so amplitude is legible without a legend.
                ctx.fillStyle = Qt.rgba(cLo.r + (cHi.r - cLo.r) * norm, cLo.g + (cHi.g - cLo.g) * norm, cLo.b + (cHi.b - cLo.b) * norm, 1);
                ctx.fillRect(i * bw, height - norm * height, Math.max(1, bw - 1), norm * height);
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.points.length === 0
        text: qsTr("no signal")
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
    }
}
