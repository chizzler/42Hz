import QtQuick
import ee.ui

// FRAMED: the same surface inside a drawn border carrying pinned labels.
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
    property bool streamsVisible: false

    property bool audioServiceReady: true
    property bool processingReady: true
    property bool spectrumFlowing: true
    property int streamCount: 1

    readonly property alias streamPanel: surface.streamPanel

    Frame {
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        // Top left is identity and state, and global bypass is state: with the
        // pipelines in passthrough the spectrum looks exactly as it does with
        // them working, so nothing else in the window would say so.
        //
        // Bare mode draws none of this, by construction. That is the mode's
        // whole commitment, and the toast on the keypress is what reports it
        // there.
        title: DbMain.bypass ? "42Hz  ·  bypassed" : "42Hz"

        // Only bindings that exist are advertised, and the legend follows what
        // the keyboard will actually do next.
        legend: shell.streamsVisible ? "[m]ute   [p]rocess   ←/→ volume   [Esc] close" : "[s]treams   [b]ypass   [f]rame   [-/+] density   [q]uit"

        Surface {
            id: surface

            anchors.fill: parent

            points: shell.points
            barWidth: shell.barWidth
            streamsVisible: shell.streamsVisible
            audioServiceReady: shell.audioServiceReady
            processingReady: shell.processingReady
            spectrumFlowing: shell.spectrumFlowing
            streamCount: shell.streamCount
        }
    }
}
