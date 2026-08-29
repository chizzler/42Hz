import QtQuick
import ee.ui

// BARE: no chrome, ever. The window edge is the only boundary.
//
// The mouse does nothing and nothing decorative is drawn. State reporting and
// the mixer are not exceptions to that -- "nothing to draw" and "nothing to
// say" are different, and a window that reports nothing when the audio is gone
// is not minimal, it is broken.
Item {
    id: shell

    property var points: []
    property int barWidth: 10
    property var stateReport: ({})
    property bool streamsVisible: false

    readonly property alias streamPanel: surface.streamPanel

    Surface {
        id: surface

        anchors.fill: parent

        points: shell.points
        barWidth: shell.barWidth
        stateReport: shell.stateReport
        streamsVisible: shell.streamsVisible
    }
}
