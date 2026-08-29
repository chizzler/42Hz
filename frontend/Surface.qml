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
    property var stateReport: ({})
    property bool streamsVisible: false

    readonly property alias streamPanel: panel

    // The mixer takes the room it needs and no more, up to half the surface.
    // Below that the spectrum would stop being the resting surface.
    readonly property real panelHeight: Math.min(surface.height * 0.5, Math.max(panel.rowHeight, panel.count * panel.rowHeight) + divider.height + Math.round(Theme.fontBaseSize * 0.8))

    Spectrum {
        id: spectrum

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: surface.streamsVisible ? divider.top : parent.bottom
        anchors.bottomMargin: surface.streamsVisible ? Math.round(Theme.fontBaseSize * 0.5) : 0

        points: surface.points
        barWidth: surface.barWidth
        gap: 2
    }

    StateReport {
        anchors.fill: spectrum

        title: surface.stateReport.title ?? ""
        detail: surface.stateReport.detail ?? ""
        isError: surface.stateReport.error ?? false
    }

    Rectangle {
        id: divider

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: panel.top
        anchors.bottomMargin: Math.round(Theme.fontBaseSize * 0.5)

        height: Math.max(1, Math.round(Theme.fontBaseSize * 0.09))
        color: Theme.withAlpha(Theme.foreground, 0.2)
        visible: surface.streamsVisible
    }

    StreamPanel {
        id: panel

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: surface.streamsVisible ? surface.panelHeight - divider.height - Math.round(Theme.fontBaseSize * 0.5) : 0
        visible: surface.streamsVisible
    }
}
