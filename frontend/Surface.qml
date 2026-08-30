import QtQuick
import ee.ui

// Everything inside the chrome, in one place.
//
// Both chrome modes show the same thing -- spectrum, state report, mixer --
// and differ only in what is drawn around it. Keeping the composition here
// means a change to how the mixer shares space with the spectrum cannot land
// in one mode and not the other.
Item {
    id: surface

    property var points: []
    property int barWidth: 10
    property bool streamsVisible: false

    // Capability state, forwarded rather than interpreted. What each
    // combination means to a reader is StateReport's business.
    property bool audioServiceReady: true
    property bool processingReady: true
    property bool spectrumFlowing: true
    property int streamCount: 1

    readonly property alias streamPanel: panel

    // One gutter, stated once. It separates the spectrum from the divider and
    // the divider from the mixer, and the panel height is measured against it,
    // so three sites restating it is three chances to drift half a gutter.
    readonly property real gutter: Math.round(Theme.fontBaseSize * 0.5)

    Spectrum {
        id: spectrum

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: surface.streamsVisible ? divider.top : parent.bottom
        anchors.bottomMargin: surface.streamsVisible ? surface.gutter : 0

        points: surface.points
        barWidth: surface.barWidth
        gap: 2
    }

    StateReport {
        anchors.fill: spectrum

        audioServiceReady: surface.audioServiceReady
        processingReady: surface.processingReady
        spectrumFlowing: surface.spectrumFlowing
        streamCount: surface.streamCount
    }

    Rectangle {
        id: divider

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: panel.top
        anchors.bottomMargin: surface.gutter

        height: Theme.lineThickness
        color: Theme.withAlpha(Theme.foreground, Theme.controlBorderAlpha)
        visible: surface.streamsVisible
    }

    // The mixer takes the room it needs and no more, up to half the surface.
    // Below that the spectrum would stop being the resting surface.
    StreamPanel {
        id: panel

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: surface.streamsVisible ? Math.min(surface.height * 0.5 - divider.height - surface.gutter, Math.max(1, panel.count) * panel.rowHeight) : 0
        visible: surface.streamsVisible
    }
}
