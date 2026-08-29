import QtQuick
import ee.ui

// What 42Hz has to say when the spectrum has nothing to show.
//
// An empty window is the one thing this must never be: silence, a dead
// PipeWire, a stopped pipeline and a crashed application all look identical
// when nothing is drawn. Each of those is reported here, in the middle of the
// space the signal would otherwise occupy, and reported differently.
//
// It is deliberately quiet -- muted, unboxed, one line and a qualifier. This
// is a resting state, not an alert.
Item {
    id: report

    property string title: ""
    property string detail: ""

    // Errors read in the theme's error colour; an ordinary idle state does not.
    property bool isError: false

    visible: report.title.length > 0

    Column {
        anchors.centerIn: parent

        spacing: Math.round(Theme.fontBaseSize * 0.4)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: report.title
            color: report.isError ? Theme.error : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: report.detail
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
            visible: report.detail.length > 0
        }
    }
}
