import QtQuick
import QtQuick.Window
import ee.ui

Window {
    id: root
    // supplied via engine.setInitialProperties() in main.cpp
    property string applicationName: "42Hz"
    property string applicationId: "io.github.chizzler.42Hz"
    property bool canUseSysTray: false

    width: 480; height: 200
    visible: true
    title: root.applicationName
    color: "#111c18"                       // Omarchy: theme background

    property var points: []

    Connections {
        target: StreamOutputEffects
        function onNewSpectrumData(newData) {
            root.points = newData
            canvas.requestPaint()
        }
    }

    Timer {
        interval: 1000 / 60; running: true; repeat: true
        onTriggered: StreamOutputEffects.requestSpectrumData()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 8
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const pts = root.points
            const n = pts.length
            if (n === 0) return

            let lo = Infinity, hi = -Infinity
            for (let i = 0; i < n; i++) {
                const v = pts[i].y
                if (v < lo) lo = v
                if (v > hi) hi = v
            }
            const span = (hi - lo) > 1e-6 ? (hi - lo) : 1

            const bw = width / n
            ctx.fillStyle = "#509475"      // Omarchy: theme accent
            for (let i = 0; i < n; i++) {
                const norm = (pts[i].y - lo) / span
                const h = norm * height
                ctx.fillRect(i * bw, height - h, Math.max(1, bw - 1), h)
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.points.length === 0
        text: "no signal"
        color: "#53685B"                   // Omarchy: theme muted
        font.family: "JetBrainsMono Nerd Font"
    }
}
