import QtQuick
import ee.ui

// A btop-style inline control: a value with a minus on its left and a plus on
// its right.
//
// It sits on the frame's top edge, which is why it is text rather than a
// widget. The line breaks around it the way it breaks around the title, so the
// control costs no signal height and reads as part of the chrome.
//
// It is also the readout. Density and style used to announce themselves with a
// transient toast, which meant the only way to learn the current value was to
// change it. A permanent value makes that toast redundant in framed chrome --
// bare chrome, which draws none of this, still gets one.
Row {
    id: stepper

    property string value: ""

    // Every value this control can show, so the widest can be reserved.
    property var values: []

    signal decremented
    signal incremented

    spacing: Math.round(Theme.fontBaseSize * 0.4)

    FontMetrics {
        id: metrics

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
    }

    // Reserved against the widest value rather than sized to the current one.
    // Stepping through values would otherwise shuffle the controls beside it,
    // and resize the gap the border breaks for them -- repainting the frame on
    // every keypress.
    //
    // Measured through metrics.font so it follows `omarchy display text size`;
    // advanceWidth() alone is a call and captures no dependency.
    readonly property real reservedWidth: {
        if (metrics.font.pixelSize <= 0)
            return 0;

        let widest = 0;

        for (let i = 0; i < stepper.values.length; i++)
            widest = Math.max(widest, metrics.advanceWidth(stepper.values[i]));

        return Math.ceil(widest);
    }

    // Pointer as well as keyboard: `project.md` asks for both at every size,
    // and a control drawn as a pair of buttons that cannot be clicked is a lie
    // about what it is. The hit area overhangs the glyph, since one character
    // is a small target and the overhang costs no layout width.
    component Arrow: Text {
        required property string glyph

        signal pressed

        text: glyph
        color: hit.containsMouse ? Theme.accent : Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize

        MouseArea {
            id: hit

            anchors.fill: parent
            anchors.margins: -Math.round(Theme.fontBaseSize * 0.35)

            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: parent.pressed()
        }
    }

    Arrow {
        glyph: "-"

        onPressed: stepper.decremented()
    }

    Text {
        text: stepper.value
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize

        width: Math.max(implicitWidth, stepper.reservedWidth)
        horizontalAlignment: Text.AlignHCenter
    }

    Arrow {
        glyph: "+"

        onPressed: stepper.incremented()
    }
}
