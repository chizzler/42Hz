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
    readonly property var current: list.currentItem

    // Rows are sized from the type scale, so the panel follows text scaling.
    readonly property real rowHeight: Math.round(Theme.fontBaseSize * 1.9)

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

        PwManager.setNodeMute(row.serial, !row.muted);
    }

    function nudgeVolume(delta) {
        const row = list.currentItem;
        if (row === null || row.volumeChannels === 0)
            return;

        PwManager.setNodeVolume(row.serial, row.volumeChannels, Math.max(0, Math.min(1, row.volume + delta)));
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
        if (row === null || row.nodeName.length === 0)
            return;

        const blocked = DbStreamOutputs.blocklist.slice();
        const at = blocked.indexOf(row.nodeName);

        if (row.processed) {
            if (at === -1)
                blocked.push(row.nodeName);

            DbStreamOutputs.blocklist = blocked;

            PwManager.disconnectStream(row.nodeId);
        } else {
            if (at !== -1)
                blocked.splice(at, 1);

            DbStreamOutputs.blocklist = blocked;

            PwManager.connectStreamOutput(row.nodeId);
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

            required property int index
            required property string appName
            required property string mediaName
            required property real volume
            required property bool mute
            required property bool connected
            required property int serial
            required property int id
            required property int nVolumeChannels
            required property string name

            // The delegate's own names, so callers are not writing model role
            // spellings into control logic.
            readonly property bool muted: row.mute
            readonly property bool processed: row.connected
            readonly property int nodeId: row.id
            readonly property int volumeChannels: row.nVolumeChannels
            readonly property string nodeName: row.name

            readonly property bool selected: ListView.isCurrentItem

            width: list.width
            height: panel.rowHeight

            Text {
                id: marker

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                width: Math.round(Theme.fontBaseSize)
                text: row.selected ? "›" : ""
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            Text {
                id: name

                anchors.left: marker.right
                anchors.verticalCenter: parent.verticalCenter

                width: Math.round(parent.width * 0.32)
                elide: Text.ElideRight
                text: row.appName.length > 0 ? row.appName : "unnamed stream"
                color: row.selected ? Theme.foreground : Theme.withAlpha(Theme.foreground, 0.8)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            Text {
                anchors.left: name.right
                anchors.right: meter.left
                anchors.rightMargin: Theme.fontBaseSize
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
                anchors.rightMargin: Math.round(Theme.fontBaseSize * 0.6)
                anchors.verticalCenter: parent.verticalCenter

                width: Math.round(parent.width * 0.22)
                height: Math.max(2, Math.round(Theme.fontBaseSize * 0.28))

                Rectangle {
                    anchors.fill: parent
                    color: Theme.withAlpha(Theme.foreground, 0.12)
                }

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, row.volume))
                    height: parent.height
                    color: row.muted ? Theme.muted : (row.selected ? Theme.accent : Theme.withAlpha(Theme.accent, 0.65))
                }
            }

            Text {
                id: reading

                anchors.right: muteFlag.left
                anchors.rightMargin: Math.round(Theme.fontBaseSize * 0.8)
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: Math.round(Theme.fontBaseSize * 2.6)
                text: Math.round(row.volume * 100) + "%"
                color: row.muted ? Theme.muted : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            // Two independent states get two columns. Sharing one would let
            // either hide the other, which is how a state stops being reported.
            Text {
                id: muteFlag

                anchors.right: processFlag.left
                anchors.rightMargin: Math.round(Theme.fontBaseSize * 0.8)
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: Math.round(Theme.fontBaseSize * 3.4)
                text: row.muted ? "muted" : ""
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }

            Text {
                id: processFlag

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                horizontalAlignment: Text.AlignRight
                width: Math.round(Theme.fontBaseSize * 4.6)
                text: row.processed ? "" : "bypassed"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBaseSize
            }
        }
    }

    // The mixer is the one surface where "nothing here" is genuinely the whole
    // story, so it says so rather than showing an empty box.
    Text {
        anchors.centerIn: parent

        text: "no application streams"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        visible: list.count === 0
    }
}
