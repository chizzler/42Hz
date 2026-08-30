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
    property bool signalPresent: true
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

        // Frames are arriving and every one of them is at the floor. Since the
        // spectrum became truthful about level this draws an empty window
        // rather than a full-height picture of the noise floor, so the state
        // has to be named. It is not a fault: a stream that is open and quiet
        // is a normal thing for a stream to be.
        if (!report.signalPresent)
            return {
                "title": "silent",
                "detail": "a stream is open but nothing is playing",
                "error": false
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
        width: parent.width

        spacing: Math.round(Theme.fontBaseSize * 0.4)

        // The title is the diagnosis and always shows. It is short by
        // construction, and the window has a floor below which it is replaced
        // wholesale, so it is never asked to fit somewhere it cannot.
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter

            text: report.state.title
            color: report.state.error ? Theme.error : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
        }

        // The qualifier is dropped when it does not fit, not elided. It is a
        // sentence, and half a sentence centred under a diagnosis reads as
        // damage rather than as brevity -- at 200 px this line was rendering
        // as "thing is playing through 42", overflowing both edges.
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter

            text: report.state.detail
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
            visible: text.length > 0 && implicitWidth <= width
        }
    }
}
