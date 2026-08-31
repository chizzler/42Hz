import QtQuick
import ee.ui

// The output equalizer: one gain per band, drawn under the part of the
// spectrum it moves.
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
// scales line up without either being told about the other.
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

    readonly property int bandCount: panel.ready ? panel.pluginDB.numBands : 0

    property int selected: 0

    // Which shipped profile the current curve is, or -1 for none. Applying one
    // sets it; nudging any band clears it, because the window has left the
    // profile at that point and a name that outlived the curve it described
    // would be the same failure as a spectrum that always fills.
    property int profileIndex: -1

    readonly property string profileName: AudioProfiles.nameAt(panel.profileIndex)

    // Whether the name is actually on screen. Set by the readout row, which is
    // the thing that knows whether it fits.
    property bool showsProfileName: false

    // Where calculateFrequencies() actually put the bands. A profile is a
    // curve, and this is what it gets resolved against.
    property var frequencies: []

    // What the sliders travel over. The settings allow ±36 dB, which is a
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

    function nudgeGain(delta) {
        if (!panel.ready || panel.bandCount === 0)
            return;

        const i = panel.selected;
        const value = Math.max(-panel.gainLimit, Math.min(panel.gainLimit, panel.gains[i] + delta));

        panel.writeBand(i, value);

        const next = panel.gains.slice();
        next[i] = value;
        panel.gains = next;

        panel.profileIndex = -1;
    }

    // Applying one writes the same band gains the editor writes. There is no
    // second mechanism and no mode a profile puts the window into: it is a
    // starting point, and everything after it is ordinary editing.
    function applyProfile(index) {
        if (!panel.ready || panel.bandCount === 0)
            return;

        const curve = AudioProfiles.curveFor(index, panel.frequencies);

        for (let i = 0; i < curve.length; i++)
            panel.writeBand(i, curve[i]);

        panel.gains = curve;
        panel.profileIndex = index;

        // Announced only where it is not already drawn. The readout row shows
        // the name permanently, so a toast there restates what is on screen --
        // the same rule the density and style steppers follow. The row is
        // dropped at small heights and narrow widths, and the announcement
        // comes back at exactly that moment.
        if (!panel.showsProfileName)
            panel.changed(AudioProfiles.nameAt(index));
    }

    function cycleProfile(delta) {
        if (!panel.ready)
            return;

        const n = AudioProfiles.list.length;

        // From a curve that is not a profile, the first press lands on the
        // first profile rather than somewhere unpredictable in the middle.
        const from = panel.profileIndex < 0 ? -1 : panel.profileIndex;
        panel.applyProfile(((from + delta) % n + n) % n);
    }

    // [0] and the `flat` profile are the same result, so they are the same
    // thing: the key is the direct route to an entry the cycle also reaches.
    function flatten() {
        panel.applyProfile(AudioProfiles.flatIndex);
    }

    onReadyChanged: panel.reload()
    onBandCountChanged: panel.reload()

    FontMetrics {
        id: metrics

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
    }

    readonly property real rowHeight: Math.round(Theme.fontBaseSize * 1.4)

    // What the editor asks for, so the surface can give it that and no more.
    //
    // A curve has no natural size the way a list of streams does -- it is as
    // readable at four rows as at twenty -- so taking the whole half-surface
    // allowance spends the spectrum's room on empty air above a flat response.
    // Four rows of travel is enough to read a +/-12 dB curve and leaves the
    // spectrum the resting surface it is supposed to be.
    readonly property real preferredHeight: panel.rowHeight * 4 + panel.rowHeight

    // The readout costs a row. Below the height where the sliders would be
    // shorter than the type beside them there is nothing left to read, so it
    // goes and the sliders keep the space.
    readonly property bool showReading: panel.height >= panel.rowHeight * 3

    readonly property real trackTop: 0
    readonly property real trackHeight: Math.max(1, panel.height - (panel.showReading ? panel.rowHeight : 0))

    // The zero axis takes the theme's control *border* alpha, not its fill.
    // Fill is what sits behind a control; this is a line, and at the fill
    // alpha it was drawn and invisible, which left the bars reading as ten
    // loose dashes with nothing to be measured from.
    readonly property color railColor: Theme.withAlpha(Theme.foreground, Theme.controlBorderAlpha)
    readonly property color idleBand: Theme.withAlpha(Theme.accent, 0.55)

    // Bypassed, the curve is still drawn -- it is the setting, and hiding it
    // would make the panel look empty rather than switched off -- but in the
    // muted role, so the state is visible at a glance rather than only in a
    // word.
    readonly property color activeBand: panel.ready && panel.pluginDB.bypass ? Theme.muted : Theme.accent

    StateReport {
        anchors.fill: parent

        overrideTitle: !panel.ready ? "no equalizer"
            : !panel.installed ? "equalizer plugin not installed" : ""
    }

    Item {
        id: bands

        anchors.fill: parent
        visible: panel.ready && panel.installed && panel.bandCount > 0

        // Zero, as one rule across the panel. Drawn per band it came out as ten
        // separate dashes, which reads as ten things rather than as the axis
        // the bars are measured from.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right

            y: panel.trackTop + panel.trackHeight / 2
            height: Theme.lineThickness
            color: panel.railColor
        }

        Repeater {
            model: panel.bandCount

            delegate: Item {
                id: band

                required property int index

                readonly property bool selected: band.index === panel.selected

                // (n + 0.5) / N across the width. The spectrum's axis is
                // logarithmic over the same 20 Hz - 20 kHz that
                // calculateFrequencies() divides, so this lands the control
                // under the frequencies it moves.
                readonly property real slot: panel.width / Math.max(1, panel.bandCount)

                readonly property real gain: panel.gains.length > band.index ? panel.gains[band.index] : 0

                x: band.index * band.slot
                y: panel.trackTop
                width: band.slot
                height: panel.trackHeight

                // Gain as a bar growing out of the centre. A slider handle
                // would need a track it does not have room for at ten bands in
                // 200 px, and the bar is the shape of the curve anyway.
                Rectangle {
                    readonly property real span: (band.height / 2) * Math.max(-1, Math.min(1, band.gain / panel.gainLimit))

                    anchors.horizontalCenter: parent.horizontalCenter

                    width: Math.max(1, Math.round(band.slot * 0.55))

                    // Nothing at all at 0 dB. A minimum-height bar there drew
                    // a tick per band on top of the axis, so a flat response
                    // looked like ten controls rather than one flat line.
                    height: Math.abs(span)
                    visible: height >= 1
                    y: span >= 0 ? band.height / 2 - height : band.height / 2
                    color: band.selected ? panel.activeBand : panel.idleBand
                }

                // Selection is marked on the zero line under the band itself.
                // A marker along the bottom of the panel sat a long way from
                // the band it named and read as a row of its own; on the axis
                // it is unmistakably part of the control.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter

                    y: band.height / 2 - height / 2
                    width: Math.max(1, Math.round(band.slot * 0.55))
                    height: Theme.lineThickness * 2
                    color: Theme.accent
                    visible: band.selected
                }
            }
        }
    }

    // What the selected band is, and what it is set to. One line, because the
    // curve above already says what every other band is doing.
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: panel.rowHeight
        visible: panel.showReading && panel.ready && panel.installed && panel.bandCount > 0

        // The profile on the left, the selected band on the right. They are two
        // separate facts -- what the whole curve is, and what one band of it is
        // worth -- so they do not share a column.
        //
        // Empty when the curve is nobody's profile, rather than saying so. A
        // window with nothing to report about the profile reports nothing.
        Text {
            id: profile

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            text: panel.profileName
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize

            // Dropped before the band readout when the row cannot hold both:
            // the band is what the arrow keys are moving.
            visible: panel.showReading && panel.ready && panel.installed
                && panel.width >= implicitWidth + bandReading.implicitWidth + panel.rowHeight

            onVisibleChanged: panel.showsProfileName = visible
            Component.onCompleted: panel.showsProfileName = visible
        }

        Text {
            id: bandReading

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            horizontalAlignment: Text.AlignRight
            text: {
                if (!panel.ready || panel.bandCount === 0 || panel.gains.length <= panel.selected)
                    return "";

                const hz = panel.frequencies.length > panel.selected ? panel.frequencies[panel.selected] : 0;
                const label = hz >= 1000 ? (hz / 1000).toFixed(hz >= 10000 ? 0 : 1) + " kHz" : Math.round(hz) + " Hz";
                const g = panel.gains[panel.selected];

                return label + "   " + (g > 0 ? "+" : "") + g.toFixed(1) + " dB";
            }
            color: panel.ready && panel.pluginDB.bypass ? Theme.muted : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
        }

    }
}
