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
    property string spectrumStyle: "bars"
    property bool streamsVisible: false
    property bool eqVisible: false

    property var eqPluginDB: null
    property bool eqInstalled: true
    property int eqRevision: 0
    property var eqLeftDB: null
    property var eqRightDB: null

    property string toastText: ""
    property int toastSeq: 0

    // Only while they are actually on screen. Below the width that holds them
    // they are dropped, and the window goes back to announcing changes -- the
    // readout and the announcement are two ways of saying one thing, and
    // exactly one of them should be saying it.
    readonly property bool showsSpectrumControls: shell.spectrumControlsFit

    // Air between the title and the controls. Without it they meet, and at
    // 200 px the top edge read `42Hz10px +`.
    readonly property real titleGap: Theme.fontBaseSize

    readonly property real controlsWidth: density.naturalWidth + style.naturalWidth + controls.spacing

    // What the top edge has left once the title, the corner and the border's
    // own insets have taken theirs.
    readonly property real topEdgeFree: Math.max(0, frame.width - frame.labelInset - shell.titleWidth
        - frame.labelPad - shell.titleGap - frame.labelInset - frame.radius - frame.thickness)

    // Chrome yields before signal, and a component that will not fit is dropped
    // whole rather than shrunk to a stub. Both go together or neither does:
    // keeping one would leave the other's value unreported while the window
    // still looked as though it were showing them.
    readonly property bool spectrumControlsFit: shell.topEdgeFree >= shell.controlsWidth

    signal densityStepped(int delta)
    signal styleStepped(int delta)

    property bool audioServiceReady: true
    property bool processingReady: true
    property bool spectrumFlowing: true
    property bool signalPresent: true
    // Whether the equalizer is currently passing audio through untouched.
    // Handed down rather than read from a settings singleton here: the
    // window owns the plugin, and a shell reading DbMain.bypass would be
    // reporting a different flag from the one the key now moves.
    property bool bypassed: false
    property int streamCount: 1

    // The legend is handed down as data. See Main: the same table drives the
    // key handler, so a binding cannot change without the legend changing with
    // it.
    property var legendItems: []

    // See Frame: the label the bottom edge promises room for, and what the
    // floor below is measured against.
    property string legendFloorLabel: ""

    // Raised when a legend label is clicked. Forwarded rather than acted on:
    // the shell reports what was pressed and the window decides what it means,
    // exactly as the steppers do.
    signal legendActivated(var keys)

    readonly property alias streamPanel: surface.streamPanel
    readonly property alias eqPanel: surface.eqPanel

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
        frame.labelInset + shell.titleWidth + frame.labelPad + frame.radius + frame.thickness,
        frame.minimumLegendWidth)

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
        title: shell.bypassed ? shell.bypassTitle : shell.idleTitle

        legendItems: shell.legendItems
        legendFloorLabel: shell.legendFloorLabel

        onLegendActivated: keys => shell.legendActivated(keys)

        // Top right, on the line, btop-style. These are the spectrum's own
        // adjustments rather than actions on the audio, which is why they sit
        // apart from the legend and carry a value instead of a key hint.
        topRightWidth: shell.spectrumControlsFit ? shell.controlsWidth : 0

        topRightContent: Row {
            id: controls

            visible: shell.spectrumControlsFit
            spacing: Math.round(Theme.fontBaseSize * 1.2)

            Stepper {
                id: density

                value: shell.barWidth + "px"
                values: ["60px"]

                onDecremented: shell.densityStepped(-1)
                onIncremented: shell.densityStepped(1)
            }

            Stepper {
                id: style

                value: shell.spectrumStyle
                values: ["bars", "cells", "dots"]

                decrementGlyph: "["
                incrementGlyph: "]"

                onDecremented: shell.styleStepped(-1)
                onIncremented: shell.styleStepped(1)
            }
        }

        Surface {
            id: surface

            anchors.fill: parent

            // The border has already stood this whole surface back from the
            // window, so the mixer needs no edge inset of its own.
            contentInset: 0

            points: shell.points
            barWidth: shell.barWidth
            spectrumStyle: shell.spectrumStyle
            streamsVisible: shell.streamsVisible
            eqVisible: shell.eqVisible
            eqPluginDB: shell.eqPluginDB
            eqInstalled: shell.eqInstalled
            eqRevision: shell.eqRevision
            eqLeftDB: shell.eqLeftDB
            eqRightDB: shell.eqRightDB
            toastText: shell.toastText
            toastSeq: shell.toastSeq
            audioServiceReady: shell.audioServiceReady
            processingReady: shell.processingReady
            spectrumFlowing: shell.spectrumFlowing
            signalPresent: shell.signalPresent
            streamCount: shell.streamCount
        }
    }
}
