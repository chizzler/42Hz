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
    readonly property real markerWidth: Math.round(Theme.fontBaseSize)
    readonly property real nameWidth: Math.round(panel.width * 0.32)
    readonly property real meterWidth: Math.round(panel.width * 0.22)
    readonly property real meterHeight: Math.max(2, Math.round(Theme.fontBaseSize * 0.28))
    readonly property real readingWidth: Math.round(Theme.fontBaseSize * 2.6)
    readonly property real muteWidth: Math.round(Theme.fontBaseSize * 3.4)
    readonly property real processWidth: Math.round(Theme.fontBaseSize * 4.6)

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

    // Processing inclusion is two things at once, and doing only one of them
    // looks like a control that does not work.
    //
    // The link change is immediate but not durable: the core links every new
    // output stream to its sink unless the node is blocklisted, so a bare
    // disconnect is undone the moment the stream is seen again -- and for a
    // client that pins its own target it never takes effect at all. The
    // blocklist is what makes the choice stick; the link change is what makes
    // it happen now.
    function toggleProcessing() {
        const row = list.currentItem;
        if (row === null || row.name.length === 0)
            return;

        const blocked = DbStreamOutputs.blocklist.slice();
        const at = blocked.indexOf(row.name);

        if (row.connected) {
            if (at === -1)
                blocked.push(row.name);

            DbStreamOutputs.blocklist = blocked;

            PwManager.disconnectStream(row.id);
        } else {
            if (at !== -1)
                blocked.splice(at, 1);

            DbStreamOutputs.blocklist = blocked;

            PwManager.connectStreamOutput(row.id);
        }
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
            required property int id
            required property int nVolumeChannels
            required property string name

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

                width: panel.nameWidth
                elide: Text.ElideRight
                text: row.appName.length > 0 ? row.appName : "unnamed stream"
                color: row.selected ? Theme.foreground : panel.idleName
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            Text {
                anchors.left: name.right
                anchors.right: meter.left
                anchors.rightMargin: panel.gap
                anchors.verticalCenter: parent.verticalCenter

                elide: Text.ElideRight
                text: row.mediaName
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            // Volume as a bar rather than a number alone: the number is exact,
            // the bar is comparable at a glance across rows.
            Item {
                id: meter

                anchors.right: reading.left
                anchors.rightMargin: panel.gap
                anchors.verticalCenter: parent.verticalCenter

                width: panel.meterWidth
                height: panel.meterHeight

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
                anchors.rightMargin: panel.gap
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
                anchors.rightMargin: panel.gap
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: panel.muteWidth
                text: row.mute ? "muted" : ""
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            Text {
                id: processFlag

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: panel.processWidth
                text: row.connected ? "" : "bypassed"
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
