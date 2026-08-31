import QtQuick
import ee.ui

// The application mixer: every playback stream the session is running, with
// the three controls that matter per stream -- volume, mute, and whether it
// passes through 42Hz's processing.
//
// The third is the one that makes this a mixer for *42Hz* rather than a
// generic volume applet, and it is deliberately shown even when off: a stream
// bypassing processing is a state the user chose, not an absence.
//
// This panel owns no key handling. The window owns the keyboard and calls in,
// so there is one place that decides what a key means.
Item {
    id: panel

    readonly property int count: list.count

    // How many streams the panel is not currently showing.
    //
    // The list scrolls and the selection carries the view with it, so nothing
    // is unreachable -- but at a glance a mixer three rows tall in a two-row
    // space reports two streams and gives no sign of the third, which is the
    // same failure the column rules exist to prevent, one axis over. Surface
    // draws this on the divider.
    readonly property int hiddenCount: Math.max(0, list.count - Math.floor(panel.height / panel.rowHeight))

    // Everything below is the same for every row, so it is derived once here
    // rather than once per delegate -- including the two theme colours, which
    // otherwise cross into C++ three times per row on every selection move.
    readonly property real rowHeight: Math.round(Theme.fontBaseSize * 1.9)
    readonly property real gap: Math.round(Theme.fontBaseSize * 0.8)
    // Proportioned against the bar's new length. At a fixed 4 em the old 0.28 em
    // was a short thick-enough dash; several times longer it reads as a hairline
    // ruled across the row, so the weight goes up with the length.
    readonly property real meterHeight: Math.max(2, Math.round(Theme.fontBaseSize * 0.4))

    // Columns are measured, not guessed at in ems. The old multipliers were
    // close but not right -- `processWidth` was 4.6 em against a word needing
    // nearer 4.9, so "bypassed" was clipped in any font at any size -- and a
    // guess cannot follow `omarchy font set` into a font with different
    // metrics. FontMetrics knows the answer for the font actually in use.
    FontMetrics {
        id: metrics

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
    }

    // Every measurement below reads `metrics.font` before calling
    // advanceWidth().
    //
    // `advanceWidth()` is a call, not a property: a binding that only calls it
    // captures no dependency and never re-runs, so these columns kept the
    // metrics of whatever font was loaded at startup and stopped following
    // `omarchy display text size` -- the type moved and the columns did not.
    // `metrics.font` does notify, so reading it is what makes them live, and
    // reading it rather than Theme's own keys takes the measurement from the
    // font the change delivered instead of from whichever binding happened to
    // run first.
    //
    // Stated once per column rather than gathered into one object: an object
    // is undefined until its own binding has run, and the widths that read it
    // are not guaranteed to run second. That cost four `Cannot read property
    // of undefined` errors on the first pass -- invisible in a Release build,
    // for the reason recorded under *Upstream baseline* in `project.md`.
    readonly property real markerWidth: metrics.font.pixelSize > 0 ? Math.ceil(metrics.advanceWidth("\u203a ")) : 0
    readonly property real readingWidth: metrics.font.pixelSize > 0 ? Math.ceil(metrics.advanceWidth("100%")) : 0

    // What a column needs before it is worth drawing at all. Ten characters is
    // where a stream name stops being a name and becomes a prefix.
    readonly property real minTextWidth: metrics.font.pixelSize > 0 ? Math.ceil(metrics.advanceWidth("mmmmmmmmmm")) : 0

    // Both state words together are wider than a narrow row can spare beside a
    // readable name -- at 240 px they left the name 31 px, which elided to a
    // bare ellipsis. Neither giving way is acceptable: a state that stops being
    // reported is the failure the two-column split exists to prevent, and a
    // name elided to nothing is the failure the column widths exist to
    // prevent. So the words contract to their initials instead, and both
    // states stay on screen.
    readonly property real wideFlagsWidth: metrics.font.pixelSize > 0
        ? Math.ceil(metrics.advanceWidth("muted")) + Math.ceil(metrics.advanceWidth("bypassed"))
        : 0

    // What the meter is guaranteed, and the only meter figure the layout
    // *decisions* below are allowed to see. Those decide which columns exist at
    // all, and a column that grows must not be able to grow the layout out of
    // the state that admitted it -- that is how widening a window ends up
    // showing less.
    readonly property real meterMinWidth: Math.round(Theme.fontBaseSize * 4)

    // The space left over if the flags never contract. Every decision about
    // which columns exist is made against this rather than against the space
    // actually free, so that contracting the flags cannot hand back enough
    // room to reintroduce a column -- which made the layout non-monotonic:
    // widening 280 -> 340 px turned the flags back into words and took the
    // volume meter away again. A wider window must never show less.
    readonly property real flexAtWidestFlags: Math.max(0, panel.width - (markerWidth + readingWidth + wideFlagsWidth + 4 * gap))

    // What the meter actually gets: a share of the room, floored at the width
    // it was promised.
    //
    // A fixed 4 em was a hairline. The bar is the one control here read by
    // comparing lengths across rows rather than by reading a number, and at 4 em
    // in a 600 px panel it was 12% of the room the row had to spend, sitting
    // beside text columns with width going spare. A share reads at every size;
    // the floor keeps it honest at the sizes where there is nothing to share.
    //
    // Capped so the text columns keep what `showMeter` and `showMediaName`
    // guaranteed them -- the meter grows into slack, never into a name.
    readonly property real meterShare: 0.3

    readonly property real meterWidth: {
        if (!panel.showMeter)
            return 0;

        const columns = panel.showMediaName ? 2 : 1;
        const room = panel.flexWidth - columns * (panel.minTextWidth + panel.gap);

        return Math.max(panel.meterMinWidth, Math.min(Math.round(panel.flexWidth * panel.meterShare), room));
    }

    readonly property bool compactFlags: panel.flexAtWidestFlags < minTextWidth

    readonly property string muteText: panel.compactFlags ? "M" : "muted"
    readonly property string processText: panel.compactFlags ? "B" : "bypassed"

    readonly property real muteWidth: metrics.font.pixelSize > 0 ? Math.ceil(metrics.advanceWidth(panel.muteText)) : 0
    readonly property real processWidth: metrics.font.pixelSize > 0 ? Math.ceil(metrics.advanceWidth(panel.processText)) : 0

    // Reserved against both flags being present even when neither is, so a
    // stream being muted cannot reflow the row it is in. The flags themselves
    // size to their content, so an empty one costs nothing on screen -- this
    // is only the width the *decisions* below are made against.
    readonly property real fixedWidth: markerWidth + readingWidth + muteWidth + processWidth + 4 * gap

    // Columns are given up in order of what they add: the media name repeats
    // information the stream name already carries, and the meter restates the
    // percentage beside it. Name, volume, mute and processing state are the
    // row, and none of them is ever dropped -- a state that stops being
    // reported is the failure this panel's two-column split exists to avoid.
    readonly property real flexWidth: Math.max(0, panel.width - panel.fixedWidth)
    readonly property bool showMeter: panel.flexAtWidestFlags >= panel.minTextWidth + panel.meterMinWidth + gap
    readonly property bool showMediaName: panel.showMeter
        && panel.flexAtWidestFlags >= 2 * panel.minTextWidth + panel.meterMinWidth + 2 * gap

    // The name takes what is left, and shares it with the media name when
    // there is one. Below ~320 px the fixed proportions this replaced put the
    // volume meter straight through the stream name.
    readonly property real nameWidth: {
        const spare = panel.flexWidth - (panel.showMeter ? panel.meterWidth + gap : 0);
        return panel.showMediaName ? Math.max(panel.minTextWidth, Math.round(spare * 0.45)) : spare;
    }

    // The empty half of a meter is control chrome, so it takes the theme's
    // own control fill rather than a number invented here.
    readonly property color meterTrack: Theme.withAlpha(Theme.foreground, Theme.controlFillAlpha)

    // An unselected row is dimmer, not differently coloured.
    readonly property color idleName: Theme.foregroundDim
    readonly property color idleMeter: Theme.withAlpha(Theme.accent, 0.65)

    // The number on a row is not the node's volume.
    //
    // A PipeWire node carries linear amplitude, and everything else on this
    // desktop reports the cube root of it: `pactl`, `wpctl`, and therefore
    // Omarchy's own volume OSD, which reads `pactl`. A stream someone set to
    // 58% in any of those is 0.2 on the node, and this panel used to print
    // "20%" beside it. Two numbers for one stream, and the mixer's is the one
    // nothing else agrees with.
    //
    // So the row reads and writes in that scale: display it, step in it, and
    // cube on the way back to the node. The 5% step then means what it means
    // everywhere else, instead of being an even slice of amplitude that moves
    // a quiet stream inaudibly and a loud one across half its range.
    function shownVolume(linear) {
        return Math.cbrt(Math.max(0, linear));
    }

    function linearVolume(shown) {
        const v = Math.max(0, Math.min(1, shown));
        return v * v * v;
    }

    function moveSelection(delta) {
        if (list.count === 0)
            return;

        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + delta));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    // Every action takes the row it acts on, and the keyboard's version is the
    // one that supplies the selected row. A pointer acts where it was clicked
    // and a key acts on the selection, but neither gets its own copy of what
    // the action *is*.
    function toggleMute() {
        panel.muteRow(list.currentItem);
    }

    function muteRow(row) {
        if (row === null)
            return;

        PwManager.setNodeMute(row.serial, !row.mute);
    }

    // Selection follows the pointer into a row, so a click and then a key act
    // on the same stream rather than on two different ones.
    function select(index) {
        if (index < 0 || index >= list.count)
            return;

        list.currentIndex = index;
    }

    function nudgeVolume(delta) {
        const row = list.currentItem;
        if (row === null || row.nVolumeChannels === 0)
            return;

        PwManager.setNodeVolume(row.serial, row.nVolumeChannels,
                                panel.linearVolume(panel.shownVolume(row.volume) + delta));
    }

    // Processing inclusion is one write, and choosing the blocklist key here
    // was wrong twice over.
    //
    // The core matches an entry against the node name, the application id,
    // the process binary, and -- when blocklistUsesMediaName is set --
    // "name:media_name". Pushing row.name alone meant a stream blocked under
    // any other key still read as included, and toggling it appended a second
    // entry rather than clearing the first. Separately, a settings write from
    // here never moved the model's own is_blocklisted, which is what the node
    // manager consults before relinking, so the choice reached the graph only
    // by way of the link change and did not survive the stream being seen
    // again.
    //
    // Nodes::setData owns all of that: it picks the key the core will match,
    // honours blocklistUsesMediaName, and its blocklistChanged handler
    // reconciles every row and relinks the stream. The panel holds no policy.
    function toggleProcessing() {
        panel.processRow(list.currentItem);
    }

    function processRow(row) {
        // An empty name would be appended to the blocklist as "", which then
        // matches every unnamed node.
        if (row === null || row.name.length === 0)
            return;

        row.model.isBlocklisted = !row.isBlocklisted;
    }

    // Volume written straight from a pointer position, in the scale the row
    // displays. `nudgeVolume` steps the same value from the keyboard; both end
    // up in `linearVolume` because the node is the only thing that wants
    // amplitude.
    function setRowVolume(row, shown) {
        if (row === null || row.nVolumeChannels === 0)
            return;

        PwManager.setNodeVolume(row.serial, row.nVolumeChannels, panel.linearVolume(shown));
    }

    ListView {
        id: list

        anchors.fill: parent

        clip: true
        model: ModelNodes.outputStreams
        currentIndex: 0
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: row

            required property string appName
            required property string mediaName
            required property real volume
            required property bool mute
            required property bool connected
            required property int serial
            required property int nVolumeChannels
            required property string name
            required property bool isBlocklisted
            required property int index

            // The whole model row, so the processing toggle can write back
            // through Nodes::setData rather than restating its policy here.
            required property var model

            readonly property bool selected: ListView.isCurrentItem

            width: list.width
            height: panel.rowHeight

            // While a drag is live the row draws the pointer's value, not the
            // node's. The write goes out on every move, but what comes back is
            // the graph's answer a round trip later -- drawn, the bar trails
            // the pointer and the drag feels like it is fighting something.
            // Negative means "not dragging", since 0 is a real volume.
            property real dragShown: -1

            readonly property real shown: row.dragShown >= 0 ? row.dragShown : panel.shownVolume(row.volume)

            // Beneath everything: the controls below are declared after it and
            // take their presses first. A click that lands on none of them
            // still selects, so there is no dead ground in a row.
            MouseArea {
                anchors.fill: parent

                acceptedButtons: Qt.LeftButton

                onPressed: panel.select(row.index)
            }

            Text {
                id: marker

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                width: panel.markerWidth
                text: row.selected ? "›" : ""
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            Text {
                id: name

                anchors.left: marker.right
                anchors.verticalCenter: parent.verticalCenter

                width: Math.max(0, panel.nameWidth)
                elide: Text.ElideRight
                text: row.appName.length > 0 ? row.appName : "unnamed stream"
                color: row.selected ? Theme.foreground : panel.idleName
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            // Dropped rather than elided when narrow. Elided, this column
            // spent the width of a word to render "S\u2026", which reserves space
            // to say nothing.
            //
            // Blank when it only repeats the name. A game names its stream
            // after its binary and gives the media the same string, so N++
            // arrived as `N++.bin.x86_64  N++.bin.x86_64`. The column is not
            // dropped for that one row -- the widths are a decision for the
            // whole panel, and a row that laid itself out differently would
            // put its readings somewhere else -- but it has nothing to say
            // and says nothing.
            Text {
                anchors.left: name.right
                anchors.leftMargin: panel.gap
                anchors.right: meter.left
                anchors.rightMargin: panel.showMeter ? panel.gap : 0
                anchors.verticalCenter: parent.verticalCenter

                elide: Text.ElideRight
                text: row.mediaName === row.appName ? "" : row.mediaName
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
                visible: panel.showMediaName
            }

            // Volume as a bar rather than a number alone: the number is exact,
            // the bar is comparable at a glance across rows.
            Item {
                id: meter

                anchors.right: reading.left
                anchors.rightMargin: panel.showMeter ? panel.gap : 0
                anchors.verticalCenter: parent.verticalCenter

                width: panel.showMeter ? panel.meterWidth : 0
                height: panel.meterHeight
                visible: panel.showMeter

                Rectangle {
                    anchors.fill: parent
                    color: panel.meterTrack
                }

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, row.shown))
                    height: parent.height
                    color: row.mute ? Theme.muted : (row.selected || meterHit.containsMouse ? Theme.accent : panel.idleMeter)

                    // A keyboard step lands the bar somewhere new and the eye
                    // has to find it again; gliding carries it there. Off while
                    // a drag is live, where the bar is already following a
                    // pointer and easing towards it would read as lag.
                    Behavior on width {
                        enabled: row.dragShown < 0

                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Press or drag anywhere along the track sets the volume there.
                // There is no handle to catch: the bar is a few pixels tall, and
                // a control you have to hit exactly is not one a pointer enjoys.
                MouseArea {
                    id: meterHit

                    anchors.fill: parent

                    // The bar is thin; the target is the row. Extending the hit
                    // area rather than the bar keeps the drawn meter a reading
                    // and still gives the pointer something to land on.
                    anchors.topMargin: -(panel.rowHeight - panel.meterHeight) / 2
                    anchors.bottomMargin: -(panel.rowHeight - panel.meterHeight) / 2

                    hoverEnabled: true

                    // The gesture is horizontal, and the cursor says so. Same
                    // rule as the equalizer's bands, which show a vertical one.
                    cursorShape: Qt.SizeHorCursor

                    // The list is a Flickable, and without this it claims any
                    // press that moves far enough and turns a volume drag into
                    // a scroll halfway through.
                    preventStealing: true

                    // Not rounded to the keyboard's 5% step. The step exists so
                    // a key moves by the same amount the rest of the desktop
                    // does; a pointer is already saying exactly where it wants
                    // to be, and snapping it would be the control arguing.
                    function apply(x) {
                        const v = Math.max(0, Math.min(1, x / Math.max(1, meterHit.width)));

                        row.dragShown = v;
                        panel.setRowVolume(row, v);
                    }

                    onPressed: mouse => {
                        panel.select(row.index);
                        meterHit.apply(mouse.x);
                    }

                    onPositionChanged: mouse => {
                        if (meterHit.pressed)
                            meterHit.apply(mouse.x);
                    }

                    onReleased: row.dragShown = -1
                    onCanceled: row.dragShown = -1
                }
            }

            Text {
                id: reading

                anchors.right: muteFlag.left
                anchors.rightMargin: panel.gap
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: panel.readingWidth
                text: Math.round(row.shown * 100) + "%"
                color: row.mute ? Theme.muted : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            // Two independent states get two columns. Sharing one would let
            // either hide the other, which is how a state stops being reported.
            //
            // Each column holds its width whether or not its state is on. It
            // used to collapse to nothing, which cost two things: the row
            // reflowed the moment a stream muted, and a state that is off had
            // no place on screen for a pointer to press. The width was already
            // reserved in `fixedWidth` for every layout decision, so holding it
            // in the drawn row takes nothing from the columns beside it.
            //
            // Off and un-hovered, the column is still empty -- the flags report
            // states, and a permanent "not muted" on every row is noise. Under
            // the pointer it shows the word it would turn on, dimmed. That is a
            // hover-only affordance on purpose: it is telling a pointer what a
            // press would do, and whoever is reading it already has one. Key
            // hints are the opposite case and stay coloured at rest.
            component Flag: Text {
                id: flag

                required property bool on
                required property string word
                required property color tone

                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                text: flag.on || flagHit.containsMouse ? flag.word : ""
                color: flag.on ? flag.tone : Theme.withAlpha(flag.tone, 0.4)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize

                signal toggled

                MouseArea {
                    id: flagHit

                    anchors.fill: parent
                    anchors.topMargin: -(panel.rowHeight - parent.height) / 2
                    anchors.bottomMargin: -(panel.rowHeight - parent.height) / 2

                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        panel.select(row.index);
                        flag.toggled();
                    }
                }
            }

            Flag {
                id: muteFlag

                anchors.right: processFlag.left
                anchors.rightMargin: panel.gap

                width: panel.muteWidth
                on: row.mute
                word: panel.muteText
                tone: Theme.error

                onToggled: panel.muteRow(row)
            }

            Flag {
                id: processFlag

                anchors.right: parent.right

                width: panel.processWidth
                on: !row.connected
                word: panel.processText
                tone: Theme.muted

                onToggled: panel.processRow(row)
            }
        }
    }

    // "Nothing here" is a state, and there is already a component for saying
    // one quietly in the middle of the space it would have filled.
    StateReport {
        anchors.fill: parent

        overrideTitle: list.count === 0 ? "no application streams" : ""
    }
}
