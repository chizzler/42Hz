import QtQuick
import QtQuick.Window
import ee.ui

// Variant harness for milestone 2.
//
// This window owns nothing but the spectrum feed and a switch between shell
// designs. Press 1/2/3 or space to flip between them on the same live audio.
// The point is to decide what 42Hz feels like before committing project.md to
// a layout model -- so nothing here is a design, and all three are disposable.
Window {
    id: root

    // supplied via engine.setInitialProperties() in main.cpp
    property string applicationName: "42Hz"
    property string applicationId: "io.github.chizzler.42Hz"
    property bool canUseSysTray: false

    width: 640
    height: 260
    visible: true
    title: root.applicationName
    color: Theme.background

    // ---- live spectrum -----------------------------------------------------

    property var points: []

    Connections {
        target: StreamOutputEffects

        function onNewSpectrumData(newData) {
            root.points = newData;
        }
    }

    Timer {
        interval: 1000 / 60
        running: true
        repeat: true
        onTriggered: StreamOutputEffects.requestSpectrumData()
    }

    // ---- shell variants ----------------------------------------------------

    readonly property var shells: [
        {
            "name": "bare",
            "file": "ShellBare.qml",
            "blurb": "spectrum only, at any size"
        },
        {
            "name": "framed",
            "file": "ShellFramed.qml",
            "blurb": "btop-style frame and cells"
        }
    ]

    property int shellIndex: 1

    // Bar density, tuned live with [ and ] -- the whole point of the harness
    // is deciding this by eye rather than by argument.
    property int barWidth: 10

    property string toastText: ""

    function showToast(msg) {
        root.toastText = msg;
        toastAnim.restart();
    }

    onShellIndexChanged: root.showToast((root.shellIndex + 1) + "/" + root.shells.length + "  " + root.shells[root.shellIndex].name + "  ·  " + root.shells[root.shellIndex].blurb)

    Loader {
        id: shellLoader

        anchors.fill: parent
        source: root.shells[root.shellIndex].file
        onLoaded: {
            item.points = Qt.binding(() => root.points);
            item.barWidth = Qt.binding(() => root.barWidth);
        }
    }

    // Key handling sits on a focused Item rather than on Shortcut: Shortcut
    // never fired here under Hyprland, and this is the form that works.
    // The Item has no pointer handlers, so it does not shadow the hover
    // variant's HoverHandler underneath it.
    Item {
        id: keyLayer

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.text === "1")
                root.shellIndex = 0;
            else if (event.text === "2")
                root.shellIndex = 1;
            else if (event.text === "3")
                root.shellIndex = 2;
            else if (event.key === Qt.Key_Space || event.key === Qt.Key_Tab)
                root.shellIndex = (root.shellIndex + 1) % root.shells.length;
            else if (event.text === "[") {
                root.barWidth = Math.max(2, root.barWidth - 2);
                root.showToast(root.barWidth + "px bars");
            } else if (event.text === "]") {
                root.barWidth = Math.min(60, root.barWidth + 2);
                root.showToast(root.barWidth + "px bars");
            }
            else
                return;
            event.accepted = true;
        }
    }

    // HARNESS ONLY -- remove. Cycles variants so a screenshot pass can see
    // all three without injecting keystrokes.
    Timer {
        id: autoCycle

        interval: 3000
        running: false
        repeat: true
        onTriggered: root.shellIndex = (root.shellIndex + 1) % root.shells.length
    }

    // Which variant am I looking at. Fades out so it does not become part of
    // the thing being judged.
    Text {
        id: toast

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        text: root.toastText
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        opacity: 0
    }

    Component.onCompleted: root.showToast((root.shellIndex + 1) + "/" + root.shells.length + "  " + root.shells[root.shellIndex].name + "  ·  [ ] adjust bar width")

    SequentialAnimation {
        id: toastAnim

        running: false

        PropertyAction {
            target: toast
            property: "opacity"
            value: 1
        }

        PauseAnimation {
            duration: 1600
        }

        NumberAnimation {
            target: toast
            property: "opacity"
            to: 0
            duration: 400
        }
    }
}
