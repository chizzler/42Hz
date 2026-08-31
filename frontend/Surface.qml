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
    property string spectrumStyle: "bars"
    property bool streamsVisible: false

    // The equalizer editor. Mutually exclusive with the mixer -- both want the
    // bottom of the surface and the arrow keys, and a window showing two
    // reveal-on-intent panels at once is not the resting surface this is
    // supposed to be.
    property bool eqVisible: false

    property var eqPluginDB: null
    property bool eqInstalled: true
    property int eqRevision: 0
    property var eqLeftDB: null
    property var eqRightDB: null

    readonly property alias eqPanel: eq

    // One flag for "something is revealed below the spectrum", so the divider
    // and the spectrum's bottom edge do not have to know which.
    readonly property bool panelVisible: surface.streamsVisible || surface.eqVisible

    // Announcements. The window raises these; they are drawn here so that in
    // framed chrome they land inside the border rather than across it -- the
    // toast used to be anchored to the window and wrote over the linework.
    property string toastText: ""
    property int toastSeq: 0

    // Bare chrome is this surface and nothing else, so it draws no controls --
    // which is why the window still announces density and style changes here.
    readonly property bool showsSpectrumControls: false

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

    // How far the mixer stands back from the surface's own left and right
    // edges.
    //
    // The spectrum goes edge to edge in bare chrome deliberately -- that is
    // what bare chrome is -- but the mixer has content hard against both
    // margins, and in bare chrome the surface's edge is the window's. The
    // selection marker lost its left half to it and every reading lost the
    // `%` off its right. Framed chrome sets this to zero: there the border
    // has already stood the whole surface back from the window.
    property real contentInset: surface.gutter

    // One renderer at a time rather than two with one hidden: both write
    // DbSpectrum.nPoints, and two of them would fight over how many points the
    // core resamples to.
    Loader {
        id: spectrum

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: surface.panelVisible ? divider.top : parent.bottom
        anchors.bottomMargin: surface.panelVisible ? surface.gutter : 0

        sourceComponent: surface.spectrumStyle === "cells" ? cellsStyle : barsStyle

        onLoaded: item.points = Qt.binding(() => surface.points)
    }

    Component {
        id: barsStyle

        Spectrum {
            barWidth: surface.barWidth
            gap: 2
        }
    }

    Component {
        id: cellsStyle

        SpectrumCells {
            barWidth: surface.barWidth
        }
    }

    StateReport {
        anchors.fill: spectrum

        audioServiceReady: surface.audioServiceReady
        processingReady: surface.processingReady
        spectrumFlowing: surface.spectrumFlowing
        signalPresent: surface.signalPresent
        streamCount: surface.streamCount
    }

    // The count of streams the mixer has no room to draw, set into the divider
    // the way the frame sets its title into the border. On the rule rather
    // than in a row, because a row spent saying a row is missing is a poor
    // trade and would itself be the row that gets clipped next.
    Text {
        id: hidden

        anchors.right: parent.right
        anchors.rightMargin: surface.contentInset
        anchors.verticalCenter: divider.verticalCenter

        text: "+" + panel.hiddenCount
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        visible: surface.streamsVisible && panel.hiddenCount > 0
    }

    Rectangle {
        id: divider

        anchors.left: parent.left
        anchors.leftMargin: surface.contentInset
        anchors.right: hidden.visible ? hidden.left : parent.right
        anchors.rightMargin: hidden.visible ? surface.gutter : surface.contentInset
        anchors.bottom: surface.eqVisible ? eq.top : panel.top
        anchors.bottomMargin: surface.gutter

        height: Theme.lineThickness
        color: Theme.withAlpha(Theme.foreground, Theme.controlBorderAlpha)
        visible: surface.panelVisible
    }

    // The mixer takes the room it needs and no more, up to half the surface.
    // Below that the spectrum would stop being the resting surface.
    // Top right of the body, clear of the border and of the controls that sit
    // on it. Dropped rather than shrunk when the surface is too narrow to hold
    // it: a truncated announcement is not an announcement.
    Text {
        id: toast

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Math.round(Theme.fontBaseSize * 0.4)

        text: surface.toastText
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        opacity: 0
        visible: implicitWidth <= surface.width

        // Driven by a counter, not by the text: raising the same message twice
        // running must show it twice, and an unchanged property emits nothing.
        Connections {
            target: surface

            function onToastSeqChanged() {
                toastAnim.restart();
            }
        }

        SequentialAnimation {
            id: toastAnim

            running: false

            PropertyAction {
                target: toast
                property: "opacity"
                value: 1
            }

            PauseAnimation {
                duration: 1200
            }

            NumberAnimation {
                target: toast
                property: "opacity"
                to: 0
                duration: 400
            }
        }
    }

    StreamPanel {
        id: panel

        anchors.left: parent.left
        anchors.leftMargin: surface.contentInset
        anchors.right: parent.right
        anchors.rightMargin: surface.contentInset
        anchors.bottom: parent.bottom

        height: surface.streamsVisible ? Math.min(surface.height * 0.5 - divider.height - surface.gutter, Math.max(1, panel.count) * panel.rowHeight) : 0
        visible: surface.streamsVisible
    }

    // Same allowance as the mixer, and it asks for less than that: a curve is
    // as readable at four rows as at twenty, so spending the whole allowance
    // on it would buy empty air above a flat response and take the room from
    // the spectrum.
    EqPanel {
        id: eq

        anchors.left: parent.left
        anchors.leftMargin: surface.contentInset
        anchors.right: parent.right
        anchors.rightMargin: surface.contentInset
        anchors.bottom: parent.bottom

        height: surface.eqVisible ? Math.min(surface.height * 0.5 - divider.height - surface.gutter, eq.preferredHeight) : 0
        visible: surface.eqVisible

        pluginDB: surface.eqPluginDB
        installed: surface.eqInstalled
        revision: surface.eqRevision
        leftDB: surface.eqLeftDB
        rightDB: surface.eqRightDB
    }
}
