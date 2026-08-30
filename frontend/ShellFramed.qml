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
    property bool signalPresent: true
    property int streamCount: 1

    // The legend is handed down as data. See Main: the same table drives the
    // key handler, so a binding cannot change without the legend changing with
    // it.
    property var legendItems: []

    readonly property alias streamPanel: surface.streamPanel

    // Horizontal inset is larger than vertical on purpose -- see above. Named
    // because the minimum size has to account for them, and two statements of
    // the same inset is one chance for the floor to disagree with the layout.
    readonly property real insetX: 16
    readonly property real insetY: 6

    // Framed chrome costs a title row, a legend row and the border's air on
    // every edge, and none of that shrinks with the window. Below this the
    // frame would consume the signal it exists to surround -- at 160x60 it
    // consumed all of it, and the window drew no spectrum at all.
    //
    // Measured against the *bypassed* title rather than the current one, so
    // that pressing `b` cannot move the floor under a window already sitting
    // near it.
    readonly property real minimumWidth: 2 * insetX + Math.max(
        surface.minimumWidth + 2 * (frame.thickness + frame.contentPad),
        frame.labelInset + shell.titleWidth + frame.labelPad + frame.radius + frame.thickness)

    // Measured through `titleFont.font` rather than by calling advanceWidth()
    // alone: the call captures no dependency, so the floor would stop
    // following `omarchy display text size` -- see Surface.
    readonly property real titleWidth: titleFont.font.pixelSize > 0 ? titleFont.advanceWidth(shell.bypassTitle) : 0

    // Measured from the font, not from the Frame's own labels. Reading
    // frame.topInset here made the floor depend on whether the label was
    // visible -- and QML propagates visibility to children, so hiding the
    // shell because the window was too small collapsed the insets, lowered the
    // floor, and made the window large enough again. The window latched
    // between the two, reporting a size it already had.
    //
    // A frame's vertical cost is two half-label heights per labelled edge plus
    // the border and its air, and none of that depends on what is on screen.
    readonly property real labelHalfHeight: Math.max(0, titleFont.height / 2 - frame.thickness / 2)

    readonly property real minimumHeight: 2 * insetY + surface.minimumHeight
        + 2 * (frame.thickness + frame.contentPad) + 4 * labelHalfHeight

    // Both forms, so the widest is measurable without restating it.
    readonly property string idleTitle: "42Hz"
    readonly property string bypassTitle: "42Hz  ·  bypassed"

    FontMetrics {
        id: titleFont

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
    }

    Frame {
        id: frame

        anchors.fill: parent
        anchors.topMargin: shell.insetY
        anchors.bottomMargin: shell.insetY
        anchors.leftMargin: shell.insetX
        anchors.rightMargin: shell.insetX

        // Top left is identity and state, and global bypass is state: with the
        // pipelines in passthrough the spectrum looks exactly as it does with
        // them working, so nothing else in the window would say so.
        //
        // Bare mode draws none of this, by construction. That is the mode's
        // whole commitment, and the toast on the keypress is what reports it
        // there.
        title: DbMain.bypass ? shell.bypassTitle : shell.idleTitle

        legendItems: shell.legendItems

        Surface {
            id: surface

            anchors.fill: parent

            points: shell.points
            barWidth: shell.barWidth
            streamsVisible: shell.streamsVisible
            audioServiceReady: shell.audioServiceReady
            processingReady: shell.processingReady
            spectrumFlowing: shell.spectrumFlowing
            signalPresent: shell.signalPresent
            streamCount: shell.streamCount
        }
    }
}
