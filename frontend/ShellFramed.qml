import QtQuick
import ee.ui

// FRAMED: the spectrum inside a drawn border carrying pinned labels.
//
// The border is drawn geometrically (see Frame.qml), so it does not depend on
// the font carrying box-drawing glyphs and cannot be broken by
// `omarchy font set`. Only the labels are text.
//
// Horizontal inset is larger than vertical on purpose: side air is what makes
// a frame read as a frame, while top and bottom air only costs signal.
Item {
    id: shell

    property var points: []
    property int barWidth: 10
    property var stateReport: ({})

    Frame {
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        title: "42Hz"

        // Only bindings that actually exist are advertised.
        legend: "[f]rame   [-/+] density   [q]uit"

        Spectrum {
            anchors.fill: parent

            points: shell.points
            barWidth: shell.barWidth
            gap: 2
        }

        StateReport {
            anchors.fill: parent

            title: shell.stateReport.title ?? ""
            detail: shell.stateReport.detail ?? ""
            isError: shell.stateReport.error ?? false
        }
    }
}
