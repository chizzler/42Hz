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

    // Everything below is the same for every row, so it is derived once here
    // rather than once per delegate -- including the two theme colours, which
    // otherwise cross into C++ three times per row on every selection move.
    readonly property real rowHeight: Math.round(Theme.fontBaseSize * 1.9)
    readonly property real gap: Math.round(Theme.fontBaseSize * 0.8)
    readonly property real meterHeight: Math.max(2, Math.round(Theme.fontBaseSize * 0.28))

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

    readonly property real markerWidth: Math.ceil(metrics.advanceWidth("\u203a "))
    readonly property real readingWidth: Math.ceil(metrics.advanceWidth("100%"))

    // What a column needs before it is worth drawing at all. Ten characters is
    // where a stream name stops being a name and becomes a prefix.
    readonly property real minTextWidth: Math.ceil(metrics.advanceWidth("mmmmmmmmmm"))
    readonly property real meterWidth: Math.round(Theme.fontBaseSize * 4)

    // Both state words together are wider than a narrow row can spare beside a
    // readable name -- at 240 px they left the name 31 px, which elided to a
    // bare ellipsis. Neither giving way is acceptable: a state that stops being
    // reported is the failure the two-column split exists to prevent, and a
    // name elided to nothing is the failure the column widths exist to
    // prevent. So the words contract to their initials instead, and both
    // states stay on screen.
    readonly property real wideFlagsWidth: Math.ceil(metrics.advanceWidth("muted")) + Math.ceil(metrics.advanceWidth("bypassed"))

    // The space left over if the flags never contract. Every decision about
    // which columns exist is made against this rather than against the space
    // actually free, so that contracting the flags cannot hand back enough
    // room to reintroduce a column -- which made the layout non-monotonic:
    // widening 280 -> 340 px turned the flags back into words and took the
    // volume meter away again. A wider window must never show less.
    readonly property real flexAtWidestFlags: Math.max(0, panel.width - (markerWidth + readingWidth + wideFlagsWidth + 4 * gap))

    readonly property bool compactFlags: panel.flexAtWidestFlags < minTextWidth

    readonly property string muteText: panel.compactFlags ? "M" : "muted"
    readonly property string processText: panel.compactFlags ? "B" : "bypassed"

    readonly property real muteWidth: Math.ceil(metrics.advanceWidth(panel.muteText))
    readonly property real processWidth: Math.ceil(metrics.advanceWidth(panel.processText))

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
    readonly property bool showMeter: panel.flexAtWidestFlags >= panel.minTextWidth + panel.meterWidth + gap
    readonly property bool showMediaName: panel.showMeter
        && panel.flexAtWidestFlags >= 2 * panel.minTextWidth + panel.meterWidth + 2 * gap

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

    function moveSelection(delta) {
        if (list.count === 0)
            return;

        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + delta));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    function toggleMute() {
        const row = list.currentItem;
        if (row === null)
            return;

        PwManager.setNodeMute(row.serial, !row.mute);
    }

    function nudgeVolume(delta) {
        const row = list.currentItem;
        if (row === null || row.nVolumeChannels === 0)
            return;

        PwManager.setNodeVolume(row.serial, row.nVolumeChannels, Math.max(0, Math.min(1, row.volume + delta)));
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
        const row = list.currentItem;

        // An empty name would be appended to the blocklist as "", which then
        // matches every unnamed node.
        if (row === null || row.name.length === 0)
            return;

        row.model.isBlocklisted = !row.isBlocklisted;
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

            // The whole model row, so the processing toggle can write back
            // through Nodes::setData rather than restating its policy here.
            required property var model

            readonly property bool selected: ListView.isCurrentItem

            width: list.width
            height: panel.rowHeight

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
            Text {
                anchors.left: name.right
                anchors.leftMargin: panel.gap
                anchors.right: meter.left
                anchors.rightMargin: panel.showMeter ? panel.gap : 0
                anchors.verticalCenter: parent.verticalCenter

                elide: Text.ElideRight
                text: row.mediaName
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
                    width: parent.width * Math.max(0, Math.min(1, row.volume))
                    height: parent.height
                    color: row.mute ? Theme.muted : (row.selected ? Theme.accent : panel.idleMeter)
                }
            }

            Text {
                id: reading

                anchors.right: muteFlag.left
                anchors.rightMargin: muteFlag.width > 0 ? panel.gap : 0
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: panel.readingWidth
                text: Math.round(row.volume * 100) + "%"
                color: row.mute ? Theme.muted : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            // Two independent states get two columns. Sharing one would let
            // either hide the other, which is how a state stops being reported.
            Text {
                id: muteFlag

                anchors.right: processFlag.left
                anchors.rightMargin: processFlag.width > 0 ? panel.gap : 0
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: row.mute ? panel.muteWidth : 0
                text: row.mute ? panel.muteText : ""
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            Text {
                id: processFlag

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: row.connected ? 0 : panel.processWidth
                text: row.connected ? "" : panel.processText
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
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
