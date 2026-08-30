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

    // Nothing reads this yet, and it still has to exist: main.cpp injects it
    // with the other two, and setInitialProperties() fails on a key the root
    // object does not declare -- silently, in a Release build. Removing it is
    // a change to the patch inventory, not to this file.
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

            // The spectrum draws nothing below its floor, so a stream that is
            // open and silent would leave an empty window -- the state
            // `project.md` forbids, arrived at from a direction the capability
            // booleans do not cover. What is watched is therefore the frame's
            // peak, against the same floor the renderer uses, so the report
            // appears exactly when there would be nothing left to draw.
            let peak = -Infinity;
            for (let i = 0; i < newData.length; i++) {
                if (newData[i].y > peak)
                    peak = newData[i].y;
            }

            if (peak > SpectrumScale.floorDb) {
                root.signalPresent = true;
                silenceHold.restart();
            }
        }
    }

    // Held rather than instantaneous. Music has rests, tracks have gaps, and a
    // report that blinks on every one of them is noise rather than
    // information. Any frame above the floor clears it and starts the count
    // again.
    property bool signalPresent: false

    Timer {
        id: silenceHold

        interval: 1500
        onTriggered: root.signalPresent = false
    }

    // Asking 60 times a second for a frame that cannot exist costs 60 round
    // trips into the core, each returning an empty list that still churns
    // every binding downstream of `points`. When there is no stream there is
    // nothing to draw, so the request stops and the last frame is cleared.
    Timer {
        interval: 1000 / Math.max(1, DbSpectrum.spectrumFpsCap)
        running: root.audioServiceReady && root.streamCount > 0 && !root.tooSmall
        repeat: true
        onTriggered: StreamOutputEffects.requestSpectrumData()

        onRunningChanged: {
            if (!running) {
                root.points = [];

                // Nothing is being asked for, so nothing can be reported about
                // the signal. Leaving these set would have the window claim a
                // silence it stopped listening for.
                root.signalPresent = false;
                silenceHold.stop();
            }
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

    // The rate is polled, and the poll stops when the service goes away, so
    // the last reading outlives the pipeline it measured. Naming the service
    // here is what keeps `[b]ypass` from being advertised against a pipeline
    // that is no longer there; the poll refreshes immediately if it returns.
    readonly property bool processingReady: root.audioServiceReady && root.pipelineRate > 0

    readonly property int streamCount: outputStreams.count

    // Scalars rather than one object: `points` is replaced on every frame, so
    // an object binding that reads it would be rebuilt 60 times a second and
    // notify downstream every time, having produced the same report. A bool
    // suppresses its own change signal when the value has not moved.
    readonly property bool spectrumFlowing: root.points.length > 0

    // Whether there is anything for bypass to bypass.
    //
    // The spectrum and the level meter are linked into the output chain
    // unconditionally; bypass substitutes an empty plugin list for
    // DbStreamOutputs.plugins and nothing else. With that list empty, both
    // branches are the same list, so the graph it rebuilds is identical to the
    // one it tore down -- an interruption, a title claiming a state that does
    // not exist, and no change to a single sample.
    //
    // This lights up on its own when milestone 4 puts the equalizer in the
    // list, which is what makes it the right test rather than a hardcoded off.
    readonly property bool effectsPresent: DbStreamOutputs.plugins.length > 0

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

    // How the spectrum is drawn. Two genuinely different pictures rather than
    // variations on one: filled pixel bars, and a character grid built from the
    // U+2581..U+2588 block elements, which follows `omarchy font set`. Both
    // read the same fixed dB window, so switching cannot look like the signal
    // changing.
    readonly property var spectrumStyles: ["bars", "cells"]

    property int spectrumStyleIndex: 0

    readonly property string spectrumStyle: root.spectrumStyles[root.spectrumStyleIndex]

    // Reveal on intent: the mixer is not a mode the window is in, it is a
    // thing the user asked to see. Hiding it changes nothing in the graph.
    property bool streamsVisible: false

    // The floor is the chrome's, not the window's. Framed mode pays for a
    // title row, a legend row and border air that do not shrink; bare mode
    // pays for none of it and stays useful far smaller. Asking the loaded
    // shell what it needs is what keeps a size check from taking away a bare
    // window that was working.
    readonly property bool tooSmall: shellLoader.item !== null
        && (root.width < shellLoader.item.minimumWidth || root.height < shellLoader.item.minimumHeight)

    Loader {
        id: shellLoader

        anchors.fill: parent
        source: root.shells[root.shellIndex].file
        visible: !root.tooSmall

        onLoaded: {
            item.points = Qt.binding(() => root.points);
            item.barWidth = Qt.binding(() => root.barWidth);
            item.streamsVisible = Qt.binding(() => root.streamsVisible);
            item.audioServiceReady = Qt.binding(() => root.audioServiceReady);
            item.processingReady = Qt.binding(() => root.processingReady);
            item.spectrumFlowing = Qt.binding(() => root.spectrumFlowing);
            item.signalPresent = Qt.binding(() => root.signalPresent);
            item.spectrumStyle = Qt.binding(() => root.spectrumStyle);
            item.toastText = Qt.binding(() => root.toastText);
            item.toastSeq = Qt.binding(() => root.toastSeq);
            item.streamCount = Qt.binding(() => root.streamCount);

            // Bare mode draws no legend and no title, and declares neither
            // property. Reading an absent one is undefined; writing it is an
            // error.
            if (item.legendItems !== undefined)
                item.legendItems = Qt.binding(() => root.legendItems);

            if (item.effectsPresent !== undefined)
                item.effectsPresent = Qt.binding(() => root.effectsPresent);

            // The controls and the keys are one path. A shell that draws
            // steppers reports what was pressed; deciding what a step means
            // stays with the window, which is where the keyboard decides it.
            if (item.densityStepped !== undefined)
                item.densityStepped.connect(keyLayer.stepDensity);

            if (item.styleStepped !== undefined)
                item.styleStepped.connect(keyLayer.stepStyle);
        }
    }

    TooSmall {
        anchors.fill: parent

        visible: root.tooSmall
        requiredWidth: shellLoader.item !== null ? Math.ceil(shellLoader.item.minimumWidth) : 0
        requiredHeight: shellLoader.item !== null ? Math.ceil(shellLoader.item.minimumHeight) : 0

        // Bare chrome always has the lower floor, so it is worth offering
        // whenever it is not already loaded. Every binding still works here,
        // this one included -- the window keeps its keyboard at any size.
        hint: root.shellIndex !== 0 ? "[1] for bare chrome" : ""
    }

    // ---- keyboard ----------------------------------------------------------

    // One table, two readers: the handler below dispatches from it, and the
    // framed legend is rendered from it. They used to be a switch statement in
    // here and a string literal in ShellFramed, which meant adding `b` was two
    // edits and forgetting the second left the window advertising a keymap it
    // no longer had.
    //
    // `label` is what the legend shows; an entry without one is a working key
    // that is simply not advertised, which is how alternates like Ctrl+W live
    // alongside the key they duplicate. `priority` is the order entries are
    // given up as the window narrows, lowest first -- see Frame.
    //
    // `advertised` gates the legend and nothing else. `project.md` asks that
    // only bindings backed by a live capability be *advertised*, and that
    // every action stay reachable by key at every size; a key that silently
    // stops working is a different and worse thing than one that stops being
    // mentioned.
    //
    // `action` receives the key that matched, so one entry can cover a
    // direction pair without splitting into two rows that each advertise half
    // a label.
    readonly property var windowBindings: [
        {
            "keys": [Qt.Key_S],
            "label": "[s]treams",
            "priority": 100,
            "advertised": root.audioServiceReady,
            "action": key => {
                root.streamsVisible = !root.streamsVisible;
            }
        },
        {
            // Global bypass is already a setting the core acts on: DbMain
            // drives a coalescer that calls set_bypass() on both pipelines.
            // Nothing here decides what bypass means, only that it moved.
            "keys": [Qt.Key_B],
            "label": "[b]ypass",
            "priority": 90,

            // Gated on there being effects, not on the pipeline running.
            // `project.md` asks that only bindings backed by a live capability
            // be advertised, and the capability behind bypass is not "is the
            // pipeline up" -- it is "is there anything in it to switch off".
            "advertised": root.effectsPresent,

            "action": key => {
                // Answering rather than acting. set_bypass() runs
                // disconnect_filters() then connect_filters(), so toggling
                // this with an empty chain rebuilds the whole output path,
                // spectrum included, to arrive back where it started.
                if (!root.effectsPresent) {
                    root.showToast("no effects to bypass");
                    return;
                }

                DbMain.bypass = !DbMain.bypass;
                root.showToast(DbMain.bypass ? "bypassed" : "processing");
            }
        },
        {
            // A tweak, and weighted as one. The mixer and the equalizer are
            // what this window is for; which chrome it wears is not, so it is
            // the first thing the legend gives up as the window narrows.
            "keys": [Qt.Key_F, Qt.Key_1, Qt.Key_2],
            "label": "[f]rame",
            "priority": 30,
            "advertised": true,
            "action": key => keyLayer.setShell(key === Qt.Key_F ? (root.shellIndex + 1) % root.shells.length : Math.min(root.shells.length - 1, key - Qt.Key_1))
        },
        {
            // Not advertised, because framed chrome draws it as a control with
            // its value on screen. A legend entry would restate a number the
            // window is already showing, and `project.md` gives up restated
            // values before anything else.
            "keys": [Qt.Key_Minus, Qt.Key_Plus, Qt.Key_Equal],
            "priority": 0,
            "advertised": false,
            "action": key => keyLayer.stepDensity(key === Qt.Key_Minus ? -1 : 1)
        },
        {
            // Bracket keys, beside the density pair on the keyboard, because
            // they are the same kind of adjustment. They used to be aliases for
            // density itself, which spent two keys saying one thing.
            "keys": [Qt.Key_BracketLeft, Qt.Key_BracketRight],
            "priority": 0,
            "advertised": false,
            "action": key => keyLayer.stepStyle(key === Qt.Key_BracketLeft ? -1 : 1)
        },
        {
            "keys": [Qt.Key_Q],
            "label": "[q]uit",
            "priority": 50,
            "advertised": true,
            "action": key => Qt.quit()
        },
        {
            // Dismisses transient controls and nothing else. Escape must never
            // fall through to something that stops audio.
            "keys": [Qt.Key_Escape],
            "priority": 0,
            "advertised": false,
            "action": key => {
                root.streamsVisible = false;
            }
        },
        {
            "keys": [Qt.Key_W],
            "modifiers": Qt.ControlModifier,
            "priority": 0,
            "advertised": false,
            "action": key => Qt.quit()
        }
    ]

    // While the mixer is up it takes the keys it needs; everything else still
    // falls through to the window table.
    readonly property var mixerBindings: [
        {
            "keys": [Qt.Key_M],
            "label": "[m]ute",
            "priority": 100,
            "advertised": root.streamCount > 0,
            "action": key => keyLayer.streams.toggleMute()
        },
        {
            "keys": [Qt.Key_P],
            "label": "[p]rocess",
            "priority": 90,
            "advertised": root.streamCount > 0,
            "action": key => keyLayer.streams.toggleProcessing()
        },
        {
            "keys": [Qt.Key_Left, Qt.Key_Right],
            "label": "←/→ volume",
            "priority": 80,
            "advertised": root.streamCount > 0,
            "action": key => keyLayer.streams.nudgeVolume(key === Qt.Key_Left ? -0.05 : 0.05)
        },
        {
            "keys": [Qt.Key_Escape],
            "label": "[Esc] close",
            "priority": 70,
            "advertised": true,
            "action": key => {
                root.streamsVisible = false;
            }
        },
        {
            "keys": [Qt.Key_Up, Qt.Key_Down],
            "priority": 0,
            "advertised": false,
            "action": key => keyLayer.streams.moveSelection(key === Qt.Key_Up ? -1 : 1)
        }
    ]

    // What the chrome may advertise, in declaration order. Deliberately free
    // of anything that changes per frame: this rebuilds when a capability or
    // the stream count moves, not when the spectrum does.
    readonly property var legendItems: (root.streamsVisible ? root.mixerBindings : root.windowBindings).filter(b => b.advertised && b.label !== undefined).map(b => ({
                "label": b.label,
                "priority": b.priority
            }))

    // Key handling sits on a focused Item rather than on Shortcut: Shortcut
    // never fired here under Hyprland, and this is the form that works.
    Item {
        id: keyLayer

        anchors.fill: parent
        focus: true

        // Announced only where nothing shows it. Framed chrome draws both
        // values permanently, so a toast there would restate what is on screen;
        // bare chrome draws neither, so it still needs telling.
        function announceAdjustment(msg) {
            if (shellLoader.item === null || !shellLoader.item.showsSpectrumControls)
                root.showToast(msg);
        }

        function stepDensity(delta) {
            root.barWidth = Math.max(2, Math.min(60, root.barWidth + delta * 2));
            keyLayer.announceAdjustment(root.barWidth + "px");
        }

        function stepStyle(delta) {
            const n = root.spectrumStyles.length;

            root.spectrumStyleIndex = (root.spectrumStyleIndex + delta + n) % n;
            keyLayer.announceAdjustment(root.spectrumStyle);
        }

        // The mixer lives inside whichever chrome is loaded, but the window
        // owns the keyboard, so there is one place that decides what a key
        // means rather than two shells racing for focus.
        readonly property var streams: shellLoader.item ? shellLoader.item.streamPanel : null

        function setShell(index) {
            root.shellIndex = index;
            root.showToast(root.shells[index].name);
        }

        function dispatch(table, event) {
            for (let i = 0; i < table.length; i++) {
                const binding = table[i];

                if (binding.keys.indexOf(event.key) < 0)
                    continue;

                // An entry naming modifiers requires them; one that does not
                // is indifferent to them, which is how `q` has always behaved.
                if (binding.modifiers !== undefined && (event.modifiers & binding.modifiers) !== binding.modifiers)
                    continue;

                binding.action(event.key);
                event.accepted = true;
                return true;
            }

            return false;
        }

        Keys.onPressed: event => {
            if (root.streamsVisible && keyLayer.streams !== null && keyLayer.dispatch(root.mixerBindings, event))
                return;

            keyLayer.dispatch(root.windowBindings, event);
        }
    }

    // ---- transient mode indicator ------------------------------------------

    property string toastText: ""

    // Bumped on every announcement, because the surface that draws it cannot
    // watch the text: raising the same message twice running must show it
    // twice, and an unchanged property emits no signal.
    property int toastSeq: 0

    function showToast(msg) {
        root.toastText = msg;
        root.toastSeq++;
    }
}
