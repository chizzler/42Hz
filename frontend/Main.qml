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

    // Whether the equalizer is passing audio through untouched. Read from the
    // plugin's own flag, which is what `b` moves.
    readonly property bool eqBypassed: root.eqReady && root.eqPluginDB.bypass

    // ---- the equalizer -----------------------------------------------------

    // 42Hz ships one effect, and it is in the chain from startup and stays
    // there.
    //
    // "On demand" in milestone 4 is the *editor*, not the plugin. Adding and
    // removing the plugin as the editor is shown and hidden would rebuild the
    // output path on every keypress, which is exactly the interruption the
    // milestone forbids -- so the graph is built once and the editor is pure
    // interface over settings the core is already acting on.
    //
    // There is no plugin management here and there will not be: the chain is
    // this one entry. Writing it on every start also repairs a settings file
    // that lost it.
    readonly property string eqInstance: "equalizer#0"

    // How many bands the graphic EQ offers. calculateFrequencies() divides
    // 20 Hz - 20 kHz logarithmically into exactly this many, so it is the
    // resolution of the curve rather than a count of controls to manage.
    readonly property int eqBandCount: 10

    // Bumped whenever the band layout underneath the editor changes.
    //
    // The panel caches each band's frequency, because a profile is a curve that
    // has to be resolved against the frequencies the bands actually have. Those
    // are written by calculateFrequencies(), and setting numBands is what makes
    // the panel notice a change -- so on a fresh settings file the panel reads
    // the frequencies of the *previous* band count, one step before the new
    // ones are written, and every profile then lands on the wrong curve. It
    // showed up as band 0 reading 22 Hz, which is the 32-band centre.
    //
    // Nothing about the frequency properties notifies, so the window says so
    // explicitly rather than the panel trying to observe it.
    property int eqRevision: 0

    property var eqBackend: null
    property var eqPluginDB: null
    property var eqLeftDB: null
    property var eqRightDB: null

    readonly property bool eqReady: root.eqBackend !== null && root.eqPluginDB !== null

    // Available, as distinct from present. The LV2 provider may be missing --
    // the core reports that honestly and passes audio through, having still
    // created the filter node -- and a window offering an editor for a plugin
    // that is not doing anything would be the dishonest case `project.md`
    // names for the bypass key.
    readonly property bool eqInstalled: root.eqReady && root.eqBackend.packageInstalled

    function ensureEqualizer() {
        if (!root.audioServiceReady)
            return;

        if (DbStreamOutputs.plugins.indexOf(root.eqInstance) < 0)
            DbStreamOutputs.plugins = [root.eqInstance];
    }

    // The instance does not exist the moment the setting is written -- the
    // core builds it in response -- so this is retried rather than read once.
    function resolveEqualizer() {
        if (root.eqReady || !root.audioServiceReady)
            return;

        const backend = StreamOutputEffects.getPluginInstance(root.eqInstance);
        if (!backend)
            return;

        const db = DatabaseManager.soePluginsDB[root.eqInstance];
        if (!db)
            return;

        root.eqBackend = backend;
        root.eqPluginDB = db;
        root.eqLeftDB = DatabaseManager.soePluginsDB[root.eqInstance + "#left"] ?? null;
        root.eqRightDB = DatabaseManager.soePluginsDB[root.eqInstance + "#right"] ?? null;

        // Stated every time rather than once on first run. numBands is the
        // only thing that decides where the bands sit, and a settings file
        // written by a different count -- an older 42Hz, a hand edit -- would
        // otherwise leave frequencies that do not match the curve on screen.
        root.eqPluginDB.numBands = root.eqBandCount;
        root.eqBackend.calculateFrequencies();
        root.eqRevision++;

        // Type, mode, slope and width already default to what a graphic EQ
        // wants: band type 1 is Bell, mode 0 is RLC (BT), slope 0 is x1, and
        // calculateFrequencies() resets width. Nothing to set.
    }

    Timer {
        interval: 250
        running: root.audioServiceReady && !root.eqReady
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            root.ensureEqualizer();
            root.resolveEqualizer();
        }
    }

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

    // How the spectrum is drawn. Three genuinely different pictures rather than
    // variations on one: filled pixel bars; a character grid built from the
    // U+2581..U+2588 block elements, which follows `omarchy font set`; and a
    // painted dot matrix on a lattice of its own. All three read the same fixed
    // dB window, so switching cannot look like the signal changing.
    readonly property var spectrumStyles: ["bars", "cells", "dots"]

    property int spectrumStyleIndex: 0

    readonly property string spectrumStyle: root.spectrumStyles[root.spectrumStyleIndex]

    // Reveal on intent: neither of these is a mode the window is in, they are
    // things the user asked to see. Hiding either changes nothing in the graph
    // -- the equalizer goes on equalising with its editor closed.
    //
    // They are mutually exclusive. Both want the bottom of the surface and
    // both want the arrow keys, and a window showing two revealed panels at
    // once has stopped being a spectrum with things available from it.
    property bool streamsVisible: false
    property bool eqVisible: false

    function reveal(what) {
        root.streamsVisible = what === "streams" ? !root.streamsVisible : false;
        root.eqVisible = what === "eq" ? !root.eqVisible : false;
    }

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
            item.eqVisible = Qt.binding(() => root.eqVisible);
            item.eqPluginDB = Qt.binding(() => root.eqPluginDB);
            item.eqInstalled = Qt.binding(() => root.eqInstalled);
            item.eqRevision = Qt.binding(() => root.eqRevision);
            item.eqLeftDB = Qt.binding(() => root.eqLeftDB);
            item.eqRightDB = Qt.binding(() => root.eqRightDB);
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

            if (item.bypassed !== undefined)
                item.bypassed = Qt.binding(() => root.eqBypassed);

            // The controls and the keys are one path. A shell that draws
            // steppers reports what was pressed; deciding what a step means
            // stays with the window, which is where the keyboard decides it.
            if (item.densityStepped !== undefined)
                item.densityStepped.connect(keyLayer.stepDensity);

            if (item.styleStepped !== undefined)
                item.styleStepped.connect(keyLayer.stepStyle);

            if (item.legendActivated !== undefined)
                item.legendActivated.connect(keyLayer.activate);

            if (item.legendFloorLabel !== undefined)
                item.legendFloorLabel = Qt.binding(() => root.legendFloorLabel);

            if (item.eqPanel !== undefined && item.eqPanel !== null)
                item.eqPanel.changed.connect(root.showToast);
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
            "action": key => root.reveal("streams")
        },
        {
            // The equalizer editor, and the second thing this window is for.
            "keys": [Qt.Key_E],
            "label": "[e]qualizer",

            // Named in full where there is room and shortened where there is
            // not, rather than abbreviated everywhere. `[e]q` next to a
            // spelled-out `[s]treams` taught the reader that this window has
            // an "eq" in it, which is not what anything else in 42Hz calls it.
            "short": "[e]q",
            "priority": 90,

            // Backed by the plugin working, not merely existing. The core
            // creates the filter node whether or not the LV2 provider is
            // installed, so `ready` alone would advertise an editor for
            // something that moves no samples.
            "advertised": root.eqInstalled,
            "action": key => {
                if (!root.eqReady) {
                    root.showToast("no equalizer");
                    return;
                }

                if (!root.eqInstalled) {
                    root.showToast("equalizer plugin not installed");
                    return;
                }

                root.reveal("eq");
            }
        },
        {
            // Bypass, on the equalizer's own flag rather than DbMain's.
            //
            // DbMain.bypass runs disconnect_filters() then connect_filters(),
            // which tears the whole output path down and rebuilds it -- the
            // spectrum with it -- on every toggle. The plugin's own bypass is
            // an atomic tested at the top of Equalizer::process(), so the
            // buffer passes through untouched and the graph never moves. With
            // one effect in the chain those two mean the same thing to a
            // listener, and only one of them is free.
            //
            // Not advertised: the editor draws this as a state, and the legend
            // gives up restated values before anything else. The key still
            // works at every size, as every key does.
            "keys": [Qt.Key_B],
            "priority": 0,
            "advertised": false,
            "action": key => {
                if (!root.eqReady) {
                    root.showToast("nothing to bypass");
                    return;
                }

                root.eqPluginDB.bypass = !root.eqPluginDB.bypass;
                root.showToast(root.eqPluginDB.bypass ? "eq bypassed" : "eq active");
            }
        },
        {
            // Not advertised. The legend is for what this window is for --
            // the mixer and the equalizer -- and which chrome it wears is not
            // that. The key works at every size, as every key does; it is
            // simply documented rather than displayed, and the space it used
            // to take belongs to `[e]q`.
            "keys": [Qt.Key_F, Qt.Key_1, Qt.Key_2],
            "label": "[f]rame",
            "priority": 30,
            "advertised": false,
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

            // The strongest, so it is the last label standing as the window
            // narrows -- and the one the framed floor is measured against. A
            // window too small to say how to leave it is a window too small,
            // which is the report rather than the drawing.
            "priority": 200,
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
                root.eqVisible = false;
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

    // While the editor is up it takes the arrow keys; everything else still
    // falls through to the window table, `b` included -- which is what keeps
    // bypass reachable from inside the panel that shows its state.
    readonly property var eqBindings: [
        {
            "keys": [Qt.Key_Up, Qt.Key_Down],
            "label": "↑/↓ gain",
            "priority": 100,
            "advertised": root.eqReady,
            "action": key => keyLayer.eq.nudgeGain(key === Qt.Key_Up ? 1 : -1)
        },
        {
            "keys": [Qt.Key_Left, Qt.Key_Right],
            "label": "←/→ band",
            "priority": 90,
            "advertised": root.eqReady,
            "action": key => keyLayer.eq.moveSelection(key === Qt.Key_Left ? -1 : 1)
        },
        {
            "keys": [Qt.Key_P],
            "label": "[p]rofile",
            "priority": 85,
            "advertised": root.eqReady,
            "action": key => keyLayer.eq.cycleProfile(1)
        },
        {
            "keys": [Qt.Key_0],
            "label": "[0] flat",
            "priority": 80,
            "advertised": root.eqReady,
            "action": key => keyLayer.eq.flatten()
        },
        {
            "keys": [Qt.Key_Escape],
            "label": "[Esc] close",
            "priority": 70,
            "advertised": true,
            "action": key => {
                root.eqVisible = false;
            }
        }
    ]

    // What the chrome may advertise, in declaration order. Deliberately free
    // of anything that changes per frame: this rebuilds when a capability or
    // the stream count moves, not when the spectrum does.
    readonly property var legendItems: root.activeBindings.filter(b => b.advertised && b.label !== undefined).map(b => ({
                "label": b.label,
                "short": b.short,
                "priority": b.priority,
                "keys": b.keys
            }))

    // Which table the keyboard and the legend are both looking at. One
    // expression rather than the same three-way choice written out twice: a
    // legend advertising one table while the keys ran another is exactly the
    // drift the shared table exists to prevent.
    readonly property var activeBindings: root.streamsVisible ? root.mixerBindings
        : root.eqVisible ? root.eqBindings
        : root.windowBindings

    // The label the framed floor is measured against: the strongest binding in
    // the resting legend, in whatever form it would actually be drawn.
    //
    // Read off the table rather than restated, so renaming `[q]uit` cannot
    // leave the floor measuring a string the window no longer shows. Taken
    // from the window's own table and not from `activeBindings`, because a
    // revealed panel must not move the floor under a window sitting on it.
    readonly property string legendFloorLabel: {
        let strongest = null;

        for (const b of root.windowBindings) {
            if (b.label === undefined || !b.advertised)
                continue;

            if (strongest === null || b.priority > strongest.priority)
                strongest = b;
        }

        if (strongest === null)
            return "";

        return strongest.short !== undefined ? strongest.short : strongest.label;
    }

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

        readonly property var eq: shellLoader.item ? shellLoader.item.eqPanel : null

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

        // One route for a binding, whatever raised it. A revealed panel is
        // asked first, because it holds the arrow keys the window would
        // otherwise take.
        function route(event) {
            if (root.streamsVisible && keyLayer.streams !== null && keyLayer.dispatch(root.mixerBindings, event))
                return;

            if (root.eqVisible && keyLayer.eq !== null && keyLayer.dispatch(root.eqBindings, event))
                return;

            keyLayer.dispatch(root.windowBindings, event);
        }

        // A click on a legend label runs the binding the label names, down the
        // same route a keypress takes rather than calling the action directly.
        // A pointer must not be able to reach anything a key could not, and a
        // second copy of the panel-first order is one chance for the two to
        // disagree about which table owns a key.
        function activate(keys) {
            if (keys === undefined || keys.length === 0)
                return;

            keyLayer.route({
                "key": keys[0],
                "modifiers": Qt.NoModifier,
                "accepted": false
            });
        }

        Keys.onPressed: event => keyLayer.route(event)
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
