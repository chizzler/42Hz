import QtQuick
import ee.ui

// Variant 1 -- BARE.
//
// The spectrum and nothing else, at any size, ever. The mouse does nothing.
// When there is no audio the window is empty, deliberately: this variant is
// the argument that a control surface should be silent when there is nothing
// to say, and it should be judged on how that actually feels.
Item {
    id: shell

    property var points: []
    property int barWidth: 10

    Spectrum {
        anchors.fill: parent
        points: shell.points
        barWidth: shell.barWidth
        gap: 2
    }
}
