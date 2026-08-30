import QtQuick
import ee.ui

// What the window says when it is smaller than the loaded chrome can use.
//
// The alternative is worse than it sounds. Below its floor, framed chrome
// consumes the whole window -- title row, legend row and border air leave no
// interior -- so the spectrum is not drawn and nothing explains why. That is
// the failure `project.md` forbids: an empty window is not an acceptable
// report of anything, and "the chrome took the room" is a state like any
// other. It is named here rather than left to be inferred.
//
// The floor belongs to the chrome, not to the window: bare mode needs very
// little and keeps working well below the size at which framed mode gives up.
// So this reports the size the *current* mode wants, and points at the cheaper
// one when there is a cheaper one.
Rectangle {
    id: notice

    property int requiredWidth: 0
    property int requiredHeight: 0

    // Offered only when another chrome mode would fit here. A hint the user
    // cannot act on is noise.
    property string hint: ""

    // The darkest background level rather than a literal black: on a light
    // Omarchy theme a black panel would be the one surface in the application
    // that ignores the theme, and this is a message, not an alarm.
    color: Theme.backgroundDarker

    Column {
        id: message

        anchors.centerIn: parent
        width: parent.width - Theme.fontBaseSize * 2

        spacing: Math.round(Theme.fontBaseSize * 0.4)

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight

            text: "window too small"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
        }

        // The lines below are dropped rather than elided. A truncated
        // measurement is worse than no measurement: "resize to at least 18…"
        // reads as a number and is not one.
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter

            text: "needs " + notice.requiredWidth + " × " + notice.requiredHeight
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
            visible: implicitWidth <= width
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter

            text: notice.hint
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
            visible: text.length > 0 && implicitWidth <= width
        }
    }
}
