import QtQuick
import ee.ui

// Variant 3 -- FRAMED.
//
// btop's economy without btop's constraint. The border is drawn geometrically
// (see Frame.qml), so it does not depend on the font carrying box-drawing
// glyphs and cannot be broken by `omarchy font set`. Only the labels are text.
Item {
    id: shell

    property var points: []
    property int barWidth: 10

    Frame {
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        title: "42Hz"
        legend: "[s]treams   [e]q   [b]ypass"

        Spectrum {
            anchors.fill: parent
            points: shell.points
            barWidth: shell.barWidth
            gap: 2
        }
    }
}
