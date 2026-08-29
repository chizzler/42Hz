import QtQuick
import QtQml
import QtQuick.Window
import ee.ui

// The window. It owns the spectrum feed, the runtime state it reports, and the
// keyboard; whichever chrome mode it is wearing owns everything visual.
//
// Two chrome modes ship, and both are permanent: BARE draws the spectrum and
// nothing else, FRAMED puts it inside a drawn border with pinned labels. They
// are not sizes or breakpoints -- the user picks one, and the layout inside it
// responds to the window.
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

    // ---- runtime state -----------------------------------------------------

    // Application streams the core is actually processing. The model is a
    // QAbstractItemModel, so its row count reaches QML through an Instantiator
    // -- which counts what it has built, hence the empty delegate. Without one
    // it builds nothing and reports zero forever.
    Instantiator {
        id: outputStreams

        model: ModelNodes.outputStreams

        delegate: QtObject {}
    }

    // Non-zero only while the output pipeline is running. Q_INVOKABLE rather
    // than a property, so it is polled rather than bound -- once a second is
    // plenty for something that changes when a stream appears or leaves.
    property int pipelineRate: 0

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pipelineRate = StreamOutputEffects.getPipeLineRate()
    }

    // PwManager fills this in only once it has a live connection to the
    // server, so an empty string is the honest signal that there is none.
    readonly property bool audioServiceReady: PwManager.runtimeVersion.length > 0

    readonly property bool processingReady: root.pipelineRate > 0

    // Distinct causes, distinct reports. The failure this exists to prevent is
    // a blank window that could equally mean silence or a dead process.
    readonly property var stateReport: {
        if (!root.audioServiceReady)
            return {
                "title": "no audio service",
                "detail": "PipeWire is not reachable",
                "error": true
            };

        if (outputStreams.count === 0)
            return {
                "title": "no audio",
                "detail": "nothing is playing through 42Hz",
                "error": false
            };

        if (!root.processingReady)
            return {
                "title": "processing stopped",
                "detail": "the output pipeline is not running",
                "error": true
            };

        if (root.points.length === 0)
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

    // ---- chrome ------------------------------------------------------------

    readonly property var shells: [
        {
            "name": "bare",
            "file": "ShellBare.qml"
        },
        {
            "name": "framed",
            "file": "ShellFramed.qml"
        }
    ]

    property int shellIndex: 1

    // Target width of one bar. The spectrum resamples to however many fit, so
    // this is signal density rather than zoom.
    property int barWidth: 10

    Loader {
        id: shellLoader

        anchors.fill: parent
        source: root.shells[root.shellIndex].file

        onLoaded: {
            item.points = Qt.binding(() => root.points);
            item.barWidth = Qt.binding(() => root.barWidth);
            item.stateReport = Qt.binding(() => root.stateReport);
        }
    }

    // ---- keyboard ----------------------------------------------------------

    // Key handling sits on a focused Item rather than on Shortcut: Shortcut
    // never fired here under Hyprland, and this is the form that works.
    Item {
        id: keyLayer

        anchors.fill: parent
        focus: true

        function setBarWidth(px) {
            root.barWidth = Math.max(2, Math.min(60, px));
            root.showToast(root.barWidth + " px bars");
        }

        function setShell(index) {
            root.shellIndex = index;
            root.showToast(root.shells[index].name);
        }

        Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

            switch (event.key) {
            case Qt.Key_F:
                keyLayer.setShell((root.shellIndex + 1) % root.shells.length);
                break;
            case Qt.Key_1:
                keyLayer.setShell(0);
                break;
            case Qt.Key_2:
                keyLayer.setShell(1);
                break;
            case Qt.Key_Minus:
            case Qt.Key_BracketLeft:
                keyLayer.setBarWidth(root.barWidth - 2);
                break;
            case Qt.Key_Plus:
            case Qt.Key_Equal:
            case Qt.Key_BracketRight:
                keyLayer.setBarWidth(root.barWidth + 2);
                break;
            case Qt.Key_Escape:
                // Reserved: dismisses transient controls once there are any.
                // It must never stop audio, so it does nothing here rather
                // than falling through to something that would.
                break;
            case Qt.Key_Q:
                Qt.quit();
                break;
            case Qt.Key_W:
                if (!ctrl)
                    return;
                Qt.quit();
                break;
            default:
                return;
            }

            event.accepted = true;
        }
    }

    // ---- transient mode indicator ------------------------------------------

    property string toastText: ""

    function showToast(msg) {
        root.toastText = msg;
        toastAnim.restart();
    }

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

    SequentialAnimation {
        id: toastAnim

        running: false

        PropertyAction {
            target: toast
            property: "opacity"
            value: 1
        }

        PauseAnimation {
            duration: 1200
        }

        NumberAnimation {
            target: toast
            property: "opacity"
            to: 0
            duration: 400
        }
    }
}
