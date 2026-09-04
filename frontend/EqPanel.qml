import QtQuick
import ee.ui

// The output equalizer: one gain per band, drawn as a curve over the spectrum
// it shapes.
//
// The derived core runs one output chain, so this is an *output* EQ and there
// is nothing per-stream to configure here -- a stream is included in
// processing or it is not, and that control is in the mixer. See *Mixing is
// central* in project.md.
//
// It is a graphic EQ, not upstream's 32-band parametric. The core gives every
// band a type, mode, slope, Q and width; exposing those would be EasyEffects'
// surface rather than an ultra-minimal one, and the defaults are already what
// a graphic EQ wants -- band type is Bell, and calculateFrequencies() spreads
// the bands logarithmically from 20 Hz to 20 kHz.
//
// That last part is why the layout works: DbSpectrum draws the same 20 Hz to
// 20 kHz on a logarithmic axis, so band n of N sits at (n + 0.5) / N across
// the width, directly under the region of the picture it affects. The two
// scales line up without either being told about the other -- and because the
// editor is drawn over the spectrum rather than beside it, a boost lifts the
// part of the picture it applies to while the handle is still under the hand.
//
// The band is a handle on a continuous curve, not a bar in a row. Ten bars
// growing out of a centre line drew ten separate objects and left the reader to
// imagine the response between them; one curve is the object the reader is
// actually adjusting, and pulling any handle bends its neighbourhood the way
// the filters overlapping there actually behave.
//
// The drawn curve is a spline through the band gains, not a computed filter
// response. Every graphic EQ draws it that way and it is close: with Bell
// filters at these Qs the true response between two bands is very near the
// interpolation of their gains. It is a picture of the setting, and the
// spectrum behind it -- which is downstream of the plugin -- is the measurement.
//
// This panel owns no key handling. The window owns the keyboard and calls in.
Item {
    id: panel

    // The equalizer's own settings object and its left/right channel pair,
    // handed down by the window -- which is what waits for the core to build
    // the plugin instance. Null until then.
    property var pluginDB: null
    property var leftDB: null
    property var rightDB: null

    readonly property bool ready: panel.pluginDB !== null && panel.leftDB !== null

    // Instantiated is not the same as working. With the LV2 provider missing
    // the core still creates the filter node and passes audio through, so a
    // panel that only checked `ready` would draw a curve that moves nothing --
    // the dishonest case project.md names for a capability the binding does
    // not have.
    property bool installed: true

    // Bumped by the window when the band layout has been rewritten. See Main.
    property int revision: 0

    // Capability state, forwarded so that this panel's own report can carry it.
    // The editor covers the whole surface, so the report that normally sits on
    // the spectrum would land under the curve; there is one report while the
    // editor is up, and it is this one.
    property bool audioServiceReady: true
    property bool processingReady: true
    property bool globalBypassed: false
    property bool spectrumFlowing: true
    property bool signalPresent: true
    property int streamCount: 1

    readonly property int bandCount: panel.ready ? panel.pluginDB.numBands : 0

    readonly property bool bypassed: panel.globalBypassed || (panel.ready && panel.pluginDB.bypass)

    // Whether a band is being dragged. A drag keeps its pointer grab after the
    // pointer has left the window, so the chrome has to know one is live before
    // it withdraws a disclosed frame and resizes the track out from under the
    // hand.
    readonly property bool dragging: curve.held >= 0

    property int selected: 0

    // Which shipped profile the current curve is, or -1 for none. Applying one
    // sets it; nudging any band clears it, because the window has left the
    // profile at that point and a name that outlived the curve it described
    // would be the same failure as a spectrum that always fills.
    property int profileIndex: -1

    // What the current profile is for, in the fewest words that say it. Empty
    // when the curve is nobody's profile, which is the same silence the row
    // keeps in that case.
    readonly property string profileNote: AudioProfiles.noteAt(panel.profileIndex)

    // Whether the profile row is actually on screen. The toast and the legend
    // entry both key off it: exactly one of the row and the announcement says
    // the profile at any width.
    //
    // The editor's own visibility is part of the question. A digit selects a
    // profile from anywhere, editor open or not, and `profiles.visible` keeps
    // its own binding while an ancestor is hidden -- so without this the row
    // would claim to be saying the name from behind a closed editor and the
    // change would land in silence.
    readonly property bool showsProfileName: panel.visible && profiles.visible

    // Where calculateFrequencies() actually put the bands. A profile is a
    // curve, and this is what it gets resolved against.
    property var frequencies: []

    // What the curve travels over. The settings allow ±36 dB, which is a
    // repair range rather than a listening one: at that scale every ordinary
    // adjustment is a few pixels from centre and the control stops being
    // readable. ±12 is the range a graphic EQ is actually used across, and a
    // value from outside it -- an imported preset, a hand-edited file -- draws
    // at the rail rather than outside the panel.
    readonly property real gainLimit: 12

    // The gains, held here rather than read from the settings object per band.
    //
    // Band values are flat properties -- band0Gain, band1Gain, ... band31Gain
    // -- so a delegate over an index has to reach them as leftDB["band" + i +
    // "Gain"]. That reads the current value and captures no dependency, so it
    // never updates again: the same trap as calling advanceWidth() in a
    // binding, and as the columns object that returned undefined. There is no
    // dynamic form of it that notifies.
    //
    // So the array is the source of truth for what is drawn, seeded from the
    // settings on load and written through on every change. It is replaced
    // rather than mutated, because assigning an element of a var array emits
    // nothing.
    property var gains: []

    signal changed(string message)

    function bandKey(i, suffix) {
        return "band" + i + suffix;
    }

    function reload() {
        if (!panel.ready) {
            panel.gains = [];
            return;
        }

        const next = [];
        const freqs = [];
        for (let i = 0; i < panel.bandCount; i++) {
            next.push(panel.leftDB[panel.bandKey(i, "Gain")]);
            freqs.push(panel.leftDB[panel.bandKey(i, "Frequency")]);
        }

        panel.gains = next;
        panel.frequencies = freqs;
        panel.selected = Math.max(0, Math.min(panel.bandCount - 1, panel.selected));

        // A curve restored from settings is still whichever profile it is.
        // Without this a restart would present an applied profile as somebody's
        // custom edit.
        panel.profileIndex = AudioProfiles.match(next, freqs);
    }

    // Both channels, always. Split channels is a capability the core has and
    // this interface does not offer: one curve is what a minimal EQ means, and
    // a panel drawing one curve while the graph ran two would be lying.
    function writeBand(i, value) {
        panel.leftDB[panel.bandKey(i, "Gain")] = value;
        if (panel.rightDB !== null)
            panel.rightDB[panel.bandKey(i, "Gain")] = value;
    }

    function moveSelection(delta) {
        if (panel.bandCount === 0)
            return;

        panel.selected = Math.max(0, Math.min(panel.bandCount - 1, panel.selected + delta));
    }

    // One band to one value, whatever moved it. The keyboard steps from where
    // the band is; a pointer says where it should be; the wheel does either
    // depending on the modifier. All of them land here, so none gets its own
    // copy of the clamp or of the rule that editing a band leaves the profile.
    function setGain(i, value) {
        if (!panel.ready || i < 0 || i >= panel.bandCount || panel.gains.length <= i)
            return;

        // Rounded to the resolution the readout shows and the profiles are
        // stored at. Without it a drag writes values whose tenth is invisible,
        // and a curve one hundredth of a dB off a profile stops matching it.
        const v = Math.round(Math.max(-panel.gainLimit, Math.min(panel.gainLimit, value)) * 10) / 10;

        if (v === panel.gains[i])
            return;

        panel.writeBand(i, v);

        const next = panel.gains.slice();
        next[i] = v;
        panel.gains = next;

        panel.profileIndex = -1;
    }

    function nudgeGain(delta) {
        if (!panel.ready || panel.bandCount === 0 || panel.gains.length <= panel.selected)
            return;

        panel.setGain(panel.selected, panel.gains[panel.selected] + delta);
    }

    // One band back to the response everything else is measured against,
    // without disturbing the rest of the curve. `[0]` flattens the whole thing,
    // which is a different intention and a much larger one; before this the
    // only way to undo a single band was to arrow it back and count.
    function zeroBand(i) {
        panel.setGain(i, 0);
    }

    // Applying one writes the same band gains the editor writes. There is no
    // second mechanism and no mode a profile puts the window into: it is a
    // starting point, and everything after it is ordinary editing.
    function applyProfile(index) {
        if (!panel.ready || panel.bandCount === 0)
            return;

        // A digit with no profile behind it does nothing. Ten keys are bound
        // and there are nine profiles, and without this `9` would resolve an
        // absent entry to a curve of zeros -- flattening the equalizer and then
        // claiming a profile with no name.
        if (index < 0 || index >= AudioProfiles.list.length)
            return;

        const curve = AudioProfiles.curveFor(index, panel.frequencies);

        // The frequencies are cached and the band layout is written by the
        // core, so a curve resolved against a stale cache would be the wrong
        // length. Reload rather than write a short curve and leave the rest of
        // the bands reading zero.
        if (curve.length !== panel.bandCount) {
            panel.reload();
            return;
        }

        // Clamped to the travel the editor draws. The shipped anchors are all
        // inside it, and this is what keeps that true of anything added later:
        // a band written past the rail would draw pinned to it with no way to
        // see how far past the setting actually went.
        const bounded = curve.map(g => Math.max(-panel.gainLimit, Math.min(panel.gainLimit, g)));

        for (let i = 0; i < bounded.length; i++)
            panel.writeBand(i, bounded[i]);

        panel.gains = bounded;
        panel.profileIndex = index;

        // Announced only where it is not already drawn. The profile row shows
        // every name permanently and marks the current one, so a toast there
        // restates what is on screen -- the same rule the density and style
        // steppers follow. The row is dropped at small heights and narrow
        // widths, and the announcement comes back at exactly that moment.
        if (!panel.showsProfileName)
            panel.changed(AudioProfiles.nameAt(index));
    }

    function cycleProfile(delta) {
        if (!panel.ready)
            return;

        const n = AudioProfiles.list.length;

        // From a curve that is not a profile, a forward press lands on the
        // first profile rather than somewhere unpredictable in the middle, and
        // a backward press lands on the last.
        const from = panel.profileIndex < 0 ? (delta > 0 ? -1 : 0) : panel.profileIndex;
        panel.applyProfile(((from + delta) % n + n) % n);
    }

    // [0] and the `flat` profile are the same result, so they are the same
    // thing: the key is the direct route to an entry the row also offers.
    function flatten() {
        panel.applyProfile(AudioProfiles.flatIndex);
    }

    onReadyChanged: panel.reload()
    onBandCountChanged: panel.reload()
    onRevisionChanged: panel.reload()

    readonly property real rowHeight: Math.round(Theme.fontBaseSize * 1.6)

    // ---- what fits ---------------------------------------------------------
    //
    // The editor now covers the whole surface, so at ordinary sizes everything
    // fits and these only matter at the floor. They are still decided from
    // metrics rather than from the items' own geometry, for the reason
    // ProfileBar states.

    // How many lines of profile names the editor will spend. Nine names do not
    // fit one line at every usable width, and dropping the set the moment it
    // stops being a single line would hide it at most window sizes -- so it
    // wraps, up to here. Past that it is a paragraph rather than a row, and the
    // curve is what the window is for.
    readonly property int profileLineBudget: 2

    // The row goes before the readout does. A curve with no room left is still
    // a curve you can pull; a row of profile names with two rows of travel
    // under it is a menu with a control attached.
    readonly property bool showProfiles: profiles.lineCount <= panel.profileLineBudget
        && panel.height >= panel.rowHeight * 3 + profiles.implicitHeight

    readonly property real profilesHeight: panel.showProfiles ? profiles.implicitHeight : 0

    readonly property bool showReading: panel.height - panel.profilesHeight >= panel.rowHeight * 3

    readonly property real trackTop: panel.profilesHeight
    readonly property real trackHeight: Math.max(1, panel.height - panel.trackTop - (panel.showReading ? panel.rowHeight : 0))

    // ---- palette -----------------------------------------------------------

    // The zero axis takes the theme's control *border* alpha, not its fill.
    // Fill is what sits behind a control; this is a line, and at the fill alpha
    // it was drawn and invisible, which left nothing for the curve to be
    // measured from.
    readonly property color railColor: Theme.withAlpha(Theme.foreground, Theme.controlBorderAlpha)

    // The rails at the travel limits are quieter than zero. They are the edge
    // of the instrument; zero is the fact it reports.
    readonly property color limitColor: Theme.withAlpha(Theme.foreground, Theme.controlBorderAlpha * 0.5)

    // Bypassed, the curve is still drawn -- it is the setting, and hiding it
    // would make the panel look empty rather than switched off -- but in the
    // muted role, so the state is visible at a glance rather than only in a
    // word.
    readonly property color curveColor: panel.bypassed ? Theme.muted : Theme.accent

    // Gain to a y inside the track. The pointer's coordinate runs to
    // height - 1, not height, so the scale is measured over that: mapping over
    // the full height put the lower rail one pixel past anywhere the pointer
    // could land, and full cut was unreachable while full boost was not.
    function yForGain(g) {
        const half = Math.max(1, (panel.trackHeight - 1) / 2);

        return half - Math.max(-1, Math.min(1, g / panel.gainLimit)) * half;
    }

    function labelForHz(hz) {
        return hz >= 1000 ? (hz / 1000).toFixed(hz >= 10000 ? 0 : 1) + " kHz" : Math.round(hz) + " Hz";
    }

    // ---- the profile row ---------------------------------------------------

    ProfileBar {
        id: profiles

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        height: profiles.implicitHeight
        visible: panel.showProfiles && panel.ready && panel.installed && panel.bandCount > 0

        current: panel.profileIndex
        dimmed: panel.bypassed

        onPicked: index => panel.applyProfile(index)
    }

    // ---- the curve ---------------------------------------------------------

    Item {
        id: track

        anchors.left: parent.left
        anchors.right: parent.right

        y: panel.trackTop
        height: panel.trackHeight

        visible: panel.ready && panel.installed && panel.bandCount > 0

        // Zero, as one rule across the panel. Drawn per band it came out as a
        // row of separate dashes, which reads as ten things rather than as the
        // axis the curve is measured from.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right

            y: panel.yForGain(0)
            height: Theme.lineThickness
            color: panel.railColor
        }

        // The travel limits, marked and labelled. Without them a curve's height
        // was worth nothing until you selected the band and read the number:
        // the reader could see a shape and not what it cost.
        Repeater {
            model: [panel.gainLimit, -panel.gainLimit]

            delegate: Item {
                required property int index
                required property real modelData

                anchors.left: parent.left
                anchors.right: parent.right

                y: panel.yForGain(modelData)
                height: Theme.lineThickness

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: rail.left
                    anchors.rightMargin: Math.round(Theme.fontBaseSize * 0.4)

                    height: parent.height
                    color: panel.limitColor
                }

                Text {
                    id: rail

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    // Pushed inward off its own line rather than centred on it.
                    // These rails are the ends of the travel, so a label
                    // straddling one has half of itself outside the track --
                    // which put `-12` through the readout row underneath.
                    anchors.verticalCenterOffset: (modelData > 0 ? 1 : -1) * rail.height / 2

                    text: (modelData > 0 ? "+" : "") + modelData
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBaseSize

                    // Dropped rather than crowded when the track is too short
                    // to set the two rails apart. At three rows they were ten
                    // pixels from each other and read as one smudged number.
                    visible: panel.trackHeight >= panel.rowHeight * 4
                }
            }
        }

        // The curve itself. Canvas rather than Shapes, which is the idiom the
        // dot spectrum already uses and costs the build no new Qt module.
        //
        // It is traced through the handles' live positions rather than through
        // the gain array, so a keyed step -- which glides -- carries the curve
        // with it instead of snapping while the handle eases. The handles are
        // the geometry; this draws what they are doing.
        Canvas {
            id: sheet

            anchors.fill: parent

            function trace(ctx, path) {
                ctx.moveTo(path[0].x, path[0].y);

                // Catmull-Rom through the points, converted to cubic Beziers.
                // The overshoot it gives between two bands pulled hard in
                // opposite directions is the point rather than an artefact:
                // that is what the filters do there, and a curve that only ever
                // ran between its handles would be a polyline with rounded
                // corners.
                for (let i = 0; i < path.length - 1; i++) {
                    const p0 = path[Math.max(0, i - 1)];
                    const p1 = path[i];
                    const p2 = path[i + 1];
                    const p3 = path[Math.min(path.length - 1, i + 2)];

                    ctx.bezierCurveTo(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6,
                                      p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6,
                                      p2.x, p2.y);
                }
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();

                const n = panel.bandCount;
                if (n === 0)
                    return;

                const path = [];
                for (let i = 0; i < n; i++) {
                    const item = handles.itemAt(i);
                    if (item === null)
                        return;

                    path.push({ "x": item.x, "y": item.y });
                }

                // Held to the end value outside the outermost band rather than
                // extrapolated -- the same rule the profile anchors follow, and
                // for the same reason: below 20 Hz and above 20 kHz the band
                // is a shelf, not a slope heading for nothing.
                path.unshift({ "x": 0, "y": path[0].y });
                path.push({ "x": width, "y": path[path.length - 1].y });

                const zeroY = panel.yForGain(0);
                const c = panel.curveColor;

                ctx.beginPath();
                sheet.trace(ctx, path);
                ctx.lineTo(width, zeroY);
                ctx.lineTo(0, zeroY);
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.14);
                ctx.fill();

                ctx.beginPath();
                sheet.trace(ctx, path);
                ctx.strokeStyle = c;
                ctx.lineWidth = Math.max(1.5, Theme.lineThickness * 1.5);
                ctx.lineJoin = "round";
                ctx.stroke();
            }

            onWidthChanged: sheet.requestPaint()
            onHeightChanged: sheet.requestPaint()

            // The colour is read inside onPaint rather than bound to anything,
            // so a change to it has to be pushed. Without this the handles and
            // the readout went muted on bypass while the curve they belong to
            // stayed in the accent -- one control drawn in two states.
            Connections {
                target: panel

                function onCurveColorChanged() {
                    sheet.requestPaint();
                }
            }

            // Repaint on a theme change as well, or the curve keeps the old
            // palette until something else moves a handle -- which, on a
            // settled curve, is never.
            Connections {
                target: Theme

                function onChanged() {
                    sheet.requestPaint();
                }
            }
        }

        Repeater {
            id: handles

            model: panel.bandCount

            // A point, not a box: the item is the band's position on the curve
            // and everything it draws is centred on it. That is what lets the
            // canvas trace the path straight through x and y without knowing
            // how big a handle happens to be.
            delegate: Item {
                id: handle

                required property int index

                readonly property bool selected: handle.index === panel.selected
                readonly property bool hovered: handle.index === curve.hovered

                readonly property real gain: panel.gains.length > handle.index ? panel.gains[handle.index] : 0
                readonly property real slot: track.width / Math.max(1, panel.bandCount)

                readonly property real radius: Math.max(3, Math.min(7, Math.round(handle.slot * 0.16)))

                x: (handle.index + 0.5) * handle.slot
                y: panel.yForGain(handle.gain)

                // A dragged handle follows the pointer; a stepped one glides.
                // Same rule as the mixer's volume bar, and the same reason:
                // easing towards a pointer reads as the control lagging behind
                // the hand.
                Behavior on y {
                    enabled: curve.held < 0

                    NumberAnimation {
                        duration: 110
                        easing.type: Easing.OutCubic
                    }
                }

                // The canvas traces the handles, so every frame of that glide
                // has to reach it.
                onYChanged: sheet.requestPaint()
                onXChanged: sheet.requestPaint()
                Component.onCompleted: sheet.requestPaint()

                // A stem down to the axis, on the band being touched only. It
                // is what ties a handle to the slice of spectrum behind it; on
                // every band at once it was a picket fence across the picture.
                Rectangle {
                    x: -width / 2
                    y: Math.min(0, panel.yForGain(0) - handle.y)

                    width: Theme.lineThickness
                    height: Math.abs(panel.yForGain(0) - handle.y)
                    color: Theme.withAlpha(panel.curveColor, 0.45)
                    visible: handle.selected || handle.hovered
                }

                // The focus ring. Only the selected band gets one, so which
                // band the arrow keys are on is readable from across the room
                // and is never confused with which one the pointer is over.
                Rectangle {
                    anchors.centerIn: parent

                    width: handle.radius * 4
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Theme.lineThickness
                    border.color: Theme.withAlpha(panel.curveColor, 0.35)
                    visible: handle.selected

                    Behavior on width {
                        NumberAnimation {
                            duration: 110
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent

                    width: 2 * handle.radius * (handle.selected ? 1.5 : handle.hovered ? 1.25 : 1)
                    height: width
                    radius: width / 2

                    color: handle.selected || handle.hovered ? panel.curveColor
                        : Theme.withAlpha(panel.curveColor, 0.6)

                    // Painted over the curve rather than punched out of it: the
                    // ring is the theme's background, so the handle reads as a
                    // bead on the line at every palette instead of as a blob
                    // the line disappears into.
                    border.width: Theme.lineThickness
                    border.color: Theme.background

                    Behavior on width {
                        NumberAnimation {
                            duration: 110
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }

        // One surface over the whole track rather than a hit area per handle.
        // A handle is a few pixels across and vanishes under the pointer that
        // is reaching for it; the slot is the control and the handle is what it
        // draws. Pressing anywhere in a band's column grabs that band.
        MouseArea {
            id: curve

            anchors.fill: parent

            hoverEnabled: true

            // The gesture is vertical, and the cursor says so. Same rule as the
            // mixer's volume bar, which shows a horizontal one.
            cursorShape: Qt.SizeVerCursor

            // The band captured on press, and -1 when nothing is held.
            property int held: -1
            property int hovered: -1

            // Captured on press and kept for the whole drag. Following x would
            // let the pointer paint across neighbours, which is a fine gesture
            // to offer deliberately and a poor one to hand somebody who only
            // drifted sideways while dragging a band up.
            function bandAt(x) {
                const slot = curve.width / Math.max(1, panel.bandCount);

                return Math.max(0, Math.min(panel.bandCount - 1, Math.floor(x / Math.max(1, slot))));
            }

            // Centre is 0 dB, the rails are the panel's own limit -- the same
            // scale the handles are placed on, so a band lands where the
            // pointer is rather than where a second mapping put it.
            function gainAt(y) {
                const half = Math.max(1, (curve.height - 1) / 2);
                const g = panel.gainLimit * (half - y) / half;

                // Zero is a real position on this control, not just a number
                // between two others: it is the response the whole curve is
                // measured against. Landing on it by hand within a fraction of
                // a dB is luck, so the last fraction is given.
                //
                // A detent at a meaningful value, not the quantising the volume
                // bar refuses. Rounding a whole range to steps overrides what
                // the pointer said; a detent gives it the one value it was
                // obviously reaching for.
                return Math.abs(g) < 0.4 ? 0 : g;
            }

            onPressed: mouse => {
                curve.held = curve.bandAt(mouse.x);
                panel.selected = curve.held;
                panel.setGain(curve.held, curve.gainAt(mouse.y));
            }

            onPositionChanged: mouse => {
                curve.hovered = curve.bandAt(mouse.x);

                if (curve.pressed && curve.held >= 0)
                    panel.setGain(curve.held, curve.gainAt(mouse.y));
            }

            // Back to zero without arrowing there and counting. The press that
            // opens the double-click has already moved the band, so this reads
            // as a grab that changed its mind -- which is what it is.
            onDoubleClicked: mouse => panel.zeroBand(curve.bandAt(mouse.x))

            // The wheel steps the band under the pointer, coarse by default and
            // fine with Shift -- the same pair of steps the arrow keys take, so
            // the two input devices reach the same values.
            onWheel: wheel => {
                if (wheel.angleDelta.y === 0 || panel.gains.length <= 0)
                    return;

                const i = curve.bandAt(wheel.x);
                const step = (wheel.modifiers & Qt.ShiftModifier) ? 0.1 : 1;

                panel.selected = i;
                panel.setGain(i, panel.gains[i] + (wheel.angleDelta.y > 0 ? step : -step));
            }

            onReleased: curve.held = -1
            onCanceled: curve.held = -1
            onExited: curve.hovered = -1
        }
    }

    // ---- what one band is worth --------------------------------------------

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: panel.rowHeight
        visible: panel.showReading && panel.ready && panel.installed && panel.bandCount > 0

        // The left of this row answers "what is the whole curve", the right
        // answers "what is this one band worth". Two separate facts, so they do
        // not share a column.
        //
        // Bypass outranks the profile note. It has no legend entry and no
        // control of its own -- the editor is where it is drawn as a state --
        // and a window that is not processing has something more urgent to say
        // about the curve than what the curve was chosen for.
        Text {
            id: standing

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            // The note rather than the name: the name is already on screen,
            // marked, a few rows up, and restating it here would be the
            // duplication the row was drawn to remove. What the row cannot say
            // in one word is what the profile is *for*.
            text: panel.bypassed ? "[b]ypassed" : panel.profileNote

            // Lifted out of the muted role, which the spectrum yielding
            // behind this row is what pays for. Bypassed it goes back down with
            // everything else: the whole control reads as switched off, and one
            // part of it staying bright would be the exception that makes the
            // state ambiguous.
            color: panel.bypassed ? Theme.muted : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize

            // Dropped rather than elided when the band reading needs the room.
            // Half a phrase is not a shorter phrase, and the band is what the
            // arrow keys are moving.
            visible: standing.text.length > 0
                && panel.width >= standing.implicitWidth + bandReading.implicitWidth + panel.rowHeight
        }

        // The selected band, always -- never the hovered one.
        //
        // Following the pointer was tried and is wrong here. The editor covers
        // the whole window now, so the pointer is resting somewhere over it
        // most of the time, and a readout that preferred hover sat on whatever
        // band the cursor had been left on while the arrow keys moved a
        // different one: press up, watch a number that is not yours not move.
        // Hover highlights the handle, which says what a press would grab;
        // what a band is worth is a question about the selection, and a press
        // is what moves that.
        Text {
            id: bandReading

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            horizontalAlignment: Text.AlignRight
            text: {
                const i = panel.selected;

                if (!panel.ready || panel.bandCount === 0 || panel.gains.length <= i)
                    return "";

                const hz = panel.frequencies.length > i ? panel.frequencies[i] : 0;
                const g = panel.gains[i];

                return panel.labelForHz(hz) + "   " + (g > 0 ? "+" : "") + g.toFixed(1) + " dB";
            }
            color: panel.bypassed ? Theme.muted : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
        }
    }

    // The whole surface belongs to the editor while it is up, so this carries
    // every state the spectrum's own report would have -- placed in the upper
    // half rather than dead centre, where the zero line and the curve are.
    StateReport {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.verticalCenter

        audioServiceReady: panel.audioServiceReady
        processingReady: panel.processingReady
        spectrumFlowing: panel.spectrumFlowing
        signalPresent: panel.signalPresent
        streamCount: panel.streamCount
        globalBypassed: panel.globalBypassed

        // The equalizer's own faults outrank the signal's: an editor for a
        // plugin that is not there has nothing to say about whether audio is
        // playing.
        overrideTitle: !panel.ready ? "no equalizer"
            : !panel.installed ? "equalizer plugin not installed" : ""
    }
}
