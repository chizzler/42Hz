pragma ComponentBehavior: Bound

import QtQuick
import ee.ui

// The shipped audio profiles, written out along the top of the editor.
//
// A cycle key on its own kept the set hidden: the only way to learn which
// profiles existed was to press `p` until they repeated and read the toasts,
// and the only way to reach the last was to pass through everything before it.
// The names are the control now -- all of them on screen, the current one
// marked, any of them one click away -- and `p` steps along the same row it
// draws.
//
// This is the on-screen control `project.md` describes: an adjustment with a
// permanent value does not also announce itself, so while this row is drawn the
// legend drops `[p]rofile` and applying a profile raises no toast. Both come
// back at exactly the width and height where the row does not fit.
Item {
    id: bar

    // Which profile the curve currently is, or -1 when it is nobody's. Nothing
    // is marked in that case rather than the row saying so: a window with
    // nothing to report about the profile reports nothing.
    property int current: -1

    // Drawn back when the equalizer is passing audio through untouched, the
    // same way the curve is. The row is a control over something that is not
    // presently doing anything, and that should be visible at a glance rather
    // than only in a word.
    property bool dimmed: false

    signal picked(int index)

    // Each name carries the digit that selects it, in the accent, the way every
    // key hint in 42Hz is drawn -- and the reason the current name is marked
    // with a rule rather than with colour. The accent already means "this is a
    // key" one character to the left, and one colour cannot carry both meanings
    // in one row.
    //
    // The digits are why the row no longer carries a `[p]` of its own. A hint
    // for the cycle key beside nine hints for the keys that go straight there
    // would be advertising the slower route.
    function digitFor(index) {
        return index < 10 ? String(index) : "";
    }

    // Between a digit and the name it selects. Tighter than the gap between
    // entries, because the two are one control and the row has to read as nine
    // pairs rather than eighteen words.
    readonly property real tight: Math.round(Theme.fontBaseSize * 0.35)

    // What the row is. Without it the names are nine bare words along the top
    // edge with nothing saying what they are nine of -- readable once you know,
    // which is not the same as legible.
    //
    // A caption, not a control: no digit beside it and no hit area. Air alone
    // did not set it apart -- at a glance it read as a tenth entry that had
    // lost its number -- so a rule stands between it and the list. Drawn
    // geometrically and in the same border alpha as the group marks, because it
    // is the row's furniture and belongs with them rather than with the words.
    //
    // Not uppercase, which is the other obvious way to mark a label: nothing
    // else in this window shouts, and `PRESETS` over a row of lowercase names
    // would be the only capital letter on screen.
    readonly property string heading: "Presets"

    // Between the runs the table is grouped into. A separator rather than a
    // wider gap, because a gap in a row that wraps is indistinguishable from
    // the wrap.
    //
    // It *closes* its run rather than opening the next one. Either way it
    // travels with a name, so a wrap can never strand it alone on a line; but a
    // wrap that falls on a group boundary then breaks after the mark, which
    // reads as the run continuing, instead of starting the next line with a
    // mark, which reads as a bullet.
    readonly property string separator: "·"

    readonly property real gap: Math.round(Theme.fontBaseSize * 0.9)

    readonly property real lineHeight: Math.round(Theme.fontBaseSize * 1.6)

    FontMetrics {
        id: metrics

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
    }

    // What the row would take on one line. Measured through metrics.font, which
    // notifies, rather than by calling advanceWidth() alone -- a binding that
    // only calls it captures nothing and would keep the metrics of whatever
    // font was loaded at startup instead of following `omarchy display text
    // size`.
    //
    // Nothing decides visibility from this. It is here so the editor can say
    // how wide the row *wants* to be without asking the laid-out row, which is
    // the measurement that latches.
    readonly property real naturalWidth: {
        if (metrics.font.pixelSize <= 0)
            return 0;

        let w = metrics.advanceWidth(bar.heading) + bar.gap + Theme.lineThickness;

        for (let i = 0; i < AudioProfiles.list.length; i++) {
            const entry = AudioProfiles.list[i];
            const next = AudioProfiles.list[i + 1];
            const digit = bar.digitFor(i);

            w += bar.gap + metrics.advanceWidth(entry.name);

            if (digit.length > 0)
                w += metrics.advanceWidth(digit) + bar.tight;

            if (next !== undefined && next.group !== entry.group)
                w += bar.gap + metrics.advanceWidth(bar.separator);
        }

        return Math.ceil(w);
    }

    // How many lines the row actually took. Nine names do not fit one line at
    // every width the editor is usable at, and dropping the whole set the
    // moment it cannot be a single line would hide it at most window sizes --
    // so it wraps, and the editor decides how many lines it is willing to
    // spend on it.
    //
    // Read off the laid-out flow rather than derived from `naturalWidth`,
    // because the names are different lengths and a division cannot say where
    // the wrap actually fell. Safe to read, unlike a width: a positioner lays
    // its children out whether or not anything can see it, so this does not
    // collapse when the row is hidden and cannot latch.
    // The flow's spacing sits between lines as well as between words, so the
    // divisor is a line plus a gap and the height is one gap short of a whole
    // number of them.
    readonly property int lineCount: Math.max(1, Math.round((flow.implicitHeight + bar.gap) / (bar.lineHeight + bar.gap)))

    implicitHeight: flow.implicitHeight

    // A word on the row, and nothing more. It carries no hit area of its own:
    // an entry is a digit and a name pressed as one thing, so the hit area
    // belongs to the pair rather than to either half.
    //
    // It used to own one, and that was the bug. Two hit areas under one control
    // meant two independent answers to "is the pointer on this", and the colour
    // read only the name's -- so a name could be left holding a hover the
    // pointer had already given to the digit beside it.
    component Word: Item {
        id: word

        required property string text
        required property color shade

        property bool marked: false

        // Air carried on the item's right rather than added by the positioner,
        // so one word can stand further off its neighbour than the row's own
        // spacing without every other gap changing with it.
        property real padRight: 0

        width: label.implicitWidth + word.padRight
        height: bar.lineHeight

        Text {
            id: label

            anchors.left: parent.left
            anchors.top: parent.top

            text: word.text
            color: word.shade
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize
        }

        // The mark under the current profile. A rule rather than a colour, so
        // that it survives the bypassed case -- where the name goes muted along
        // with the curve and colour alone would have stopped saying which
        // profile the curve is.
        Rectangle {
            anchors.left: label.left
            anchors.right: label.right
            anchors.top: label.bottom
            anchors.topMargin: Math.round(Theme.fontBaseSize * 0.2)

            height: Theme.lineThickness
            color: label.color
            visible: word.marked
        }

    }

    Flow {
        id: flow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        spacing: bar.gap

        Word {
            text: bar.heading
            shade: Theme.muted
        }

        // The rule between the label and the list. An item in the flow rather
        // than a decoration anchored across it, so it takes its own place in
        // the wrap like everything else on the row.
        Item {
            width: Theme.lineThickness
            height: bar.lineHeight

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -Math.round(Theme.fontBaseSize * 0.15)

                width: Theme.lineThickness
                height: Math.round(Theme.fontBaseSize * 1.1)
                color: Theme.withAlpha(Theme.foreground, Theme.controlBorderAlpha)
            }
        }

        Repeater {
            model: AudioProfiles.list

            delegate: Row {
                id: entry

                required property int index
                required property var modelData

                readonly property bool selected: entry.index === bar.current

                readonly property var following: AudioProfiles.list[entry.index + 1]

                readonly property bool closesGroup: entry.following !== undefined
                    && entry.following.group !== entry.modelData.group

                spacing: bar.gap

                // The digit and the name are one control: one press, one
                // hover, one hit area over both, and no gap between them wide
                // enough to read as two things.
                Item {
                    id: choice

                    width: pair.implicitWidth
                    height: bar.lineHeight

                    Row {
                        id: pair

                        spacing: bar.tight

                        Word {
                            text: bar.digitFor(entry.index)
                            shade: Theme.accent

                            visible: text.length > 0
                        }

                        Word {
                            text: entry.modelData.name

                            // Muted at rest and brightened under the pointer,
                            // which is the mixer's rule for a word that is a
                            // control. The current one is exempt: it is stating
                            // a fact about the curve, not offering an action,
                            // and dimming it under hover would read as losing
                            // the selection.
                            //
                            // The hover is read before the branch, not inside
                            // one of them. `a ? b : c` does not read `c` while
                            // `a` is true, so written as a conditional this
                            // registered no dependency on the pointer while the
                            // entry was selected -- and an entry that lost the
                            // selection while the pointer was still on it kept
                            // the highlight it had no way to be told about. The
                            // same family as the timer the frame's withdrawal
                            // read only while it was already withdrawing.
                            shade: {
                                const hot = choiceHit.containsMouse;

                                if (entry.selected)
                                    return bar.dimmed ? Theme.muted : Theme.accent;

                                return hot ? Theme.foregroundBright : Theme.muted;
                            }

                            marked: entry.selected
                        }
                    }

                    MouseArea {
                        id: choiceHit

                        anchors.fill: parent

                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: bar.picked(entry.index)
                    }
                }

                Word {
                    text: bar.separator
                    shade: Theme.withAlpha(Theme.foreground, Theme.controlBorderAlpha)
                    visible: entry.closesGroup
                }
            }
        }
    }
}
