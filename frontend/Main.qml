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

    // Asking 60 times a second for a frame that cannot exist costs 60 round
    // trips into the core, each returning an empty list that still churns
    // every binding downstream of `points`. When there is no stream there is
    // nothing to draw, so the request stops and the last frame is cleared.
    Timer {
        interval: 1000 / 60
        running: root.audioServiceReady && root.streamCount > 0
        repeat: true
        onTriggered: StreamOutputEffects.requestSpectrumData()

        onRunningChanged: {
            if (!running)
                root.points = [];
        }
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
        running: root.audioServiceReady
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pipelineRate = StreamOutputEffects.getPipeLineRate()
    }

    // PwManager fills this in only once it has a live connection to the
    // server, so an empty string is the honest signal that there is none.
    readonly property bool audioServiceReady: PwManager.runtimeVersion.length > 0

    readonly property bool processingReady: root.pipelineRate > 0

    readonly property int streamCount: outputStreams.count

    // Scalars rather than one object: `points` is replaced on every frame, so
    // an object binding that reads it would be rebuilt 60 times a second and
    // notify downstream every time, having produced the same report. A bool
    // suppresses its own change signal when the value has not moved.
    readonly property bool spectrumFlowing: root.points.length > 0

    // ---- chrome ------------------------------------------------------------

    // Bare mode is the surface with nothing around it, so it is loaded
    // directly rather than through a wrapper that only forwards properties.
    readonly property var shells: [
        {
            "name": "bare",
            "file": "Surface.qml"
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

    // Reveal on intent: the mixer is not a mode the window is in, it is a
    // thing the user asked to see. Hiding it changes nothing in the graph.
    property bool streamsVisible: false

    Loader {
        id: shellLoader

        anchors.fill: parent
        source: root.shells[root.shellIndex].file

        onLoaded: {
            item.points = Qt.binding(() => root.points);
            item.barWidth = Qt.binding(() => root.barWidth);
            item.streamsVisible = Qt.binding(() => root.streamsVisible);
            item.audioServiceReady = Qt.binding(() => root.audioServiceReady);
            item.processingReady = Qt.binding(() => root.processingReady);
            item.spectrumFlowing = Qt.binding(() => root.spectrumFlowing);
            item.streamCount = Qt.binding(() => root.streamCount);
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

        // The mixer lives inside whichever chrome is loaded, but the window
        // owns the keyboard, so there is one place that decides what a key
        // means rather than two shells racing for focus.
        readonly property var streams: shellLoader.item ? shellLoader.item.streamPanel : null

        function setShell(index) {
            root.shellIndex = index;
            root.showToast(root.shells[index].name);
        }

        Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

            // While the mixer is up it takes the keys it needs; everything
            // else still falls through to the window.
            if (root.streamsVisible && keyLayer.streams !== null) {
                switch (event.key) {
                case Qt.Key_Up:
                    keyLayer.streams.moveSelection(-1);
                    event.accepted = true;
                    return;
                case Qt.Key_Down:
                    keyLayer.streams.moveSelection(1);
                    event.accepted = true;
                    return;
                case Qt.Key_Left:
                    keyLayer.streams.nudgeVolume(-0.05);
                    event.accepted = true;
                    return;
                case Qt.Key_Right:
                    keyLayer.streams.nudgeVolume(0.05);
                    event.accepted = true;
                    return;
                case Qt.Key_M:
                    keyLayer.streams.toggleMute();
                    event.accepted = true;
                    return;
                case Qt.Key_P:
                    keyLayer.streams.toggleProcessing();
                    event.accepted = true;
                    return;
                default:
                    break;
                }
            }

            switch (event.key) {
            case Qt.Key_S:
                root.streamsVisible = !root.streamsVisible;
                break;
            case Qt.Key_B:
                // Global bypass is already a setting the core acts on: DbMain
                // drives a coalescer that calls set_bypass() on both pipelines.
                // Nothing here decides what bypass means, only that it moved.
                DbMain.bypass = !DbMain.bypass;
                root.showToast(DbMain.bypass ? "bypassed" : "processing");
                break;
            case Qt.Key_F:
                keyLayer.setShell((root.shellIndex + 1) % root.shells.length);
                break;
            case Qt.Key_1:
            case Qt.Key_2:
                keyLayer.setShell(Math.min(root.shells.length - 1, event.key - Qt.Key_1));
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
                // Dismisses transient controls and nothing else. Hiding the
                // mixer must never touch the graph, and Escape must never
                // fall through to something that stops audio.
                root.streamsVisible = false;
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
