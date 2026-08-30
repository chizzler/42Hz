import QtQuick
import ee.ui

// What 42Hz has to say when the spectrum has nothing to show.
//
// An empty window is the one thing this must never be: silence, a dead
// PipeWire, a stopped pipeline and a crashed application all look identical
// when nothing is drawn. Each is reported here, in the middle of the space the
// signal would otherwise occupy, and reported differently.
//
// This owns both the diagnosis and its wording. It is handed capability
// booleans, not a message -- so adding a state means editing the component
// whose job is states, and the window never carries user-facing copy.
//
// It is deliberately quiet: muted, unboxed, one line and a qualifier. This is
// a resting state, not an alert.
Item {
    id: report

    property bool audioServiceReady: true
    property bool processingReady: true
    property bool spectrumFlowing: true
    property int streamCount: 1

    // The empty mixer says one thing and means it, so it borrows the same
    // presentation with the diagnosis switched off.
    property string overrideTitle: ""

    readonly property var state: {
        if (report.overrideTitle.length > 0)
            return {
                "title": report.overrideTitle,
                "detail": "",
                "error": false
            };

        if (!report.audioServiceReady)
            return {
                "title": "no audio service",
                "detail": "PipeWire is not reachable",
                "error": true
            };

        if (report.streamCount === 0)
            return {
                "title": "no audio",
                "detail": "nothing is playing through 42Hz",
                "error": false
            };

        if (!report.processingReady)
            return {
                "title": "processing stopped",
                "detail": "the output pipeline is not running",
                "error": true
            };

        if (!report.spectrumFlowing)
            return {
                "title": "no spectrum",
                "detail": "audio is playing but no frames are arriving",
                "error": true
            };

        return {
            "title": "",
            "detail": "",
            "error": false
        };
    }

    visible: report.state.title.length > 0

    Column {
        anchors.centerIn: parent

        spacing: Math.round(Theme.fontBaseSize * 0.4)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: report.state.title
            color: report.state.error ? Theme.error : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: report.state.detail
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
            visible: text.length > 0
        }
    }
}
