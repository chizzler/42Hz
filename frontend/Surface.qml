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
    property bool signalPresent: true
    property int streamCount: 1

    readonly property alias streamPanel: panel

    // The smallest window this surface can still do its job in: draw a
    // spectrum that reads as a spectrum, or name the state standing in for
    // one. Bare mode is this and nothing else, so this is also bare mode's
    // floor -- and it is deliberately low. Bare at 160x60 is a working
    // display, and a size check must not take that away.
    //
    // Width is set by the longest thing the state report has to say, since a
    // report too wide to read is the failure the report exists to prevent.
    //
    // `advanceWidth()` is a call, not a property, so a binding that only calls
    // it captures nothing and never re-runs -- the floor would keep the
    // metrics of whatever font was loaded at startup and stop following
    // `omarchy display text size`. Reading `surfaceFont.font`, which does
    // notify, declares the dependency and takes the measurement from the font
    // the change actually delivered rather than from whichever binding ran
    // first.
    readonly property real minimumWidth: surfaceFont.font.pixelSize > 0
        ? Math.ceil(surfaceFont.advanceWidth("no audio service") + Theme.fontBaseSize)
        : 0
    readonly property real minimumHeight: Math.round(Theme.fontBaseSize * 4)

    FontMetrics {
        id: surfaceFont

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
    }

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
        signalPresent: surface.signalPresent
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
