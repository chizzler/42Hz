import QtQuick
import ee.ui

// Geometric frame: the lines are drawn, not typed.
//
// btop's boxes look perfect, but not because btop draws them -- it is a
// terminal app and can only emit characters (its binary carries the whole
// U+2500 box-drawing set, rounded corners included). The terminal is what
// makes them look right: foot discards those glyphs and renders the lines
// itself by default (`box-drawings-uses-font-glyphs = no`), because font
// glyphs give dimmed antialiased endpoints, gaps between cells, off-centre
// lines, and ugly fallbacks in fonts missing the range.
//
// 42Hz is not a terminal, so it skips the round-trip and draws the frame
// directly. Nothing here depends on the font having box characters, or on the
// user's choice of font at all -- `omarchy font set` cannot break the border.
// Text stays text; lines stay lines.
Item {
    id: frame

    property color lineColor: Theme.withAlpha(Theme.foreground, 0.45)
    property color labelColor: Theme.muted
    property color accentColor: Theme.accent

    // What a key hint is drawn in, wherever one appears.
    property color keyColor: Theme.accent

    property string title: ""

    // The legend is a list of bindings, not a sentence. Given a string it can
    // only overflow: below the width the text needs it runs past the border,
    // is clipped mid-word, and takes the bottom edge with it, since the line
    // breaks around a label that is wider than the frame.
    //
    // Given the entries it can drop the least important ones instead. Order on
    // screen is declaration order; the order things are *given up* is
    // `priority`, lowest first -- so the legend shortens by losing its tail in
    // importance rather than in position.
    //
    // Each entry is { label: string, priority: number, short?: string,
    // keys?: array }. `short` is a second, shorter name for the same binding;
    // `keys` is what a click on the label reports back.
    property var legendItems: []

    // A binding the reader can point at as well as type. The legend is the
    // window's own documentation, and a documented action that cannot be
    // invoked from the thing documenting it is a caption, not a control.
    // Frame does not know what any of them mean -- it reports the keys and the
    // window decides, which is the same path the keyboard takes.
    signal legendActivated(var keys)

    // The one label the frame promises room for, and what a shell measures its
    // floor against.
    //
    // Told rather than picked out of `legendItems`, because the items change
    // when a panel is revealed: derived, the floor would rise as the mixer
    // opened and shift under a window already sitting on it. Same reason the
    // title floor is measured against the bypassed form rather than the
    // current one.
    property string legendFloorLabel: ""

    readonly property real legendAvailable: Math.max(0, width - labelInset - labelPad - radius - thickness)

    // Below this the legend cannot name even its most important binding, and a
    // frame with nothing to say on its bottom edge is a frame at a size the
    // window should be reporting rather than drawing.
    readonly property real minimumLegendWidth: legendFont.font.pixelSize > 0 && frame.legendFloorLabel.length > 0
        ? Math.ceil(frame.labelInset + legendFont.advanceWidth(frame.legendFloorLabel)
            + frame.labelPad + frame.radius + frame.thickness)
        : 0

    // What the legend can actually show, as entries rather than as a string:
    // the labels have to be positioned and hit-tested one at a time, and
    // re-splitting a joined string to do it would be re-deriving what this
    // already knows.
    //
    // Named so the binding re-runs when the theme changes the metric:
    // advanceWidth() is a call, not a property, and would not be tracked.
    //
    // The metrics object rather than Theme's own keys, because both are
    // bindings on the same signal and their order is not defined -- naming
    // `legendFont.font` reads the font the change actually delivered instead
    // of whichever of the two happened to run first.
    readonly property var legendShown: {
        if (legendFont.font.pixelSize <= 0)
            return [];

        const available = frame.legendAvailable;

        let shown = frame.legendItems.slice();

        while (shown.length > 0) {
            // Collapse before dropping. A binding named in its short form is
            // still named; a dropped one is not, and naming what the keyboard
            // can do is the whole job. This is not the stub `project.md`
            // forbids -- `[e]q` is a name the reader can act on, where `[e]qua…`
            // would be a word with its end cut off.
            //
            // All-or-nothing per pass rather than one label at a time: a row
            // mixing full and short forms reads as two kinds of thing, and
            // which label got shortened would depend on declaration order
            // rather than on anything visible.
            for (const collapsed of [false, true]) {
                const texts = shown.map(e => collapsed && e.short !== undefined ? e.short : e.label);

                if (legendFont.advanceWidth(texts.join(frame.legendSeparator)) <= available) {
                    return shown.map((e, i) => ({
                        "label": texts[i],
                        "keys": e.keys
                    }));
                }
            }

            let weakest = 0;
            for (let i = 1; i < shown.length; i++) {
                if (shown[i].priority < shown[weakest].priority)
                    weakest = i;
            }
            shown.splice(weakest, 1);
        }

        return [];
    }

    readonly property string legend: frame.legendShown.map(e => e.label).join(frame.legendSeparator)

    readonly property string legendSeparator: "   "

    // Where each label starts, measured from the font rather than laid out in a
    // Row. The border breaks around the legend using `legendMetrics`, and a
    // second measurement of the same row disagrees with the first by a fraction
    // of a pixel -- which is the line ending up against a glyph.
    //
    // A property and not a function, for the reason above: a delegate binding
    // that only *called* a measuring function would capture no dependency, so
    // the offsets would freeze at whatever font was loaded when the delegate
    // was created and stop following `omarchy display text size`.
    readonly property var legendOffsets: {
        const out = [];

        if (legendFont.font.pixelSize <= 0)
            return out;

        let prefix = "";

        for (const e of frame.legendShown) {
            out.push(prefix.length === 0 ? 0 : legendFont.advanceWidth(prefix));
            prefix += e.label + frame.legendSeparator;
        }

        return out;
    }

    // Each label with its key hint picked out, for rendering. Widths are still
    // measured on the plain strings above -- markup does not change what a
    // glyph is worth, and measuring the marked-up form would count the tags.
    //
    // The bracketed head of a label is the key: `[s]treams` is reached with
    // `s`. Colouring it is the whole of how a keyboard-first window teaches
    // itself, so it takes the accent while the word it heads stays quiet.
    readonly property var legendMarkups: {
        const key = frame.hex(frame.keyColor);

        return frame.legendShown.map(e => e.label.replace(/\[[^\]]*\]/g, m => '<font color="' + key + '">' + m + '</font>'));
    }

    // StyledText wants a colour it can parse, and a QColor stringifies with an
    // alpha channel that it cannot.
    function hex(c) {
        const byte = v => Math.round(v * 255).toString(16).padStart(2, "0");

        return "#" + byte(c.r) + byte(c.g) + byte(c.b);
    }

    // 42Hz's shared line weight, so a frame and a divider cannot end up
    // different thicknesses.
    property real thickness: Theme.lineThickness
    property real radius: 4

    // Where the labels sit along their edge, and how much line they displace.
    property real labelInset: 12
    property real labelPad: 7

    // Air between the content and the border.
    property real contentPad: 8

    // Whether the border and its labels are on screen at all.
    //
    // Not drawn, this is a plain pass-through: no line, no title, no legend, no
    // top-right controls, and none of the insets or padding they cost. That is
    // exactly bare chrome, which is why bare is this component with the drawing
    // switched off rather than a second component -- swapping between two would
    // destroy and rebuild the spectrum renderer underneath every time, which is
    // not something the resting surface should do because a pointer crossed the
    // window.
    //
    // The *values* stay live while it is off. `thickness`, `labelInset` and
    // `minimumLegendWidth` are what the framed floor is computed from, and a
    // window in bare chrome still has to be able to ask whether the frame would
    // fit before it discloses one.
    property bool drawn: true

    // What the border actually costs the layout, which is nothing when it is
    // not there.
    readonly property real edge: frame.drawn ? frame.thickness : 0
    readonly property real pad: frame.drawn ? frame.contentPad : 0

    // A label is centred on its edge, so half of it falls outside the border.
    // The border is pulled in by that half rather than relying on the parent
    // leaving room -- otherwise the bottom legend is clipped by the window,
    // which the top title survives only because a text box has slack above the
    // cap height and none below the descender.
    readonly property real topInset: titleLabel.visible ? Math.max(0, titleLabel.height / 2 - thickness / 2) : 0

    //
    // Measured from the font rather than from the label, which is both what
    // `project.md` asks of anything a layout decision rests on and now the
    // only option: the legend is a Repeater, and `childrenRect` on it would be
    // geometry read back off the thing being laid out.
    readonly property real bottomInset: frame.drawn && frame.legend.length > 0 ? Math.max(0, legendFont.height / 2 - thickness / 2) : 0

    // Children go inside the border.
    default property alias content: body.data

    // Sits on the top edge at the right, and the line breaks around it exactly
    // as it does around the title. The width is told rather than measured: a
    // shell that hides these controls sets it to zero, and a width read back
    // off hidden children would be zero anyway, which is how a fit test built
    // on it would latch.
    property alias topRightContent: topRight.data

    property real topRightWidth: 0

    TextMetrics {
        id: titleMetrics

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        text: frame.title

        onWidthChanged: border.requestPaint()
    }

    FontMetrics {
        id: legendFont

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
    }

    TextMetrics {
        id: legendMetrics

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        text: frame.legend

        onWidthChanged: border.requestPaint()
    }

    Canvas {
        id: border

        anchors.fill: parent
        visible: frame.drawn

        Connections {
            target: Theme
            function onChanged() {
                border.requestPaint();
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const t = frame.thickness;
            const h = t / 2;
            const x0 = h, y0 = h + frame.topInset;
            const x1 = width - h, y1 = height - h - frame.bottomInset;
            if (x1 <= x0 || y1 <= y0)
                return;

            const r = Math.max(0, Math.min(frame.radius, (x1 - x0) / 2, (y1 - y0) / 2));

            // Gaps in the top and bottom edges where the labels sit. The line
            // stops short and resumes, rather than the label painting over it.
            //
            // The top edge carries two: the title at the left and whatever the
            // shell put at the right. They are walked in order rather than
            // special-cased, so a third would cost nothing.
            const top = [];

            if (frame.title.length > 0) {
                top.push({
                    "a": frame.labelInset - frame.labelPad,
                    "b": frame.labelInset + titleMetrics.width + frame.labelPad
                });
            }

            if (topRight.width > 0) {
                top.push({
                    "a": frame.width - frame.labelInset - topRight.width - frame.labelPad,
                    "b": frame.width - frame.labelInset + frame.labelPad
                });
            }

            top.sort((p, q) => p.a - q.a);
            const bg = frame.legend.length > 0 ? {
                "a": frame.labelInset - frame.labelPad,
                "b": frame.labelInset + legendMetrics.width + frame.labelPad
            } : null;

            ctx.strokeStyle = frame.lineColor;
            ctx.lineWidth = t;
            ctx.lineCap = "butt";
            ctx.beginPath();

            // Top edge, broken around each label in turn. A gap that would
            // reach past the corner is dropped rather than drawn, since a
            // break with no line after it is just a missing edge.
            ctx.moveTo(x0 + r, y0);

            let cursor = x0 + r;

            for (const g of top) {
                if (g.b >= x1 - r)
                    continue;

                const a = Math.max(cursor, g.a);

                if (a > cursor)
                    ctx.lineTo(a, y0);

                ctx.moveTo(g.b, y0);
                cursor = g.b;
            }

            ctx.lineTo(x1 - r, y0);
            ctx.arcTo(x1, y0, x1, y0 + r, r);

            // Right edge.
            ctx.lineTo(x1, y1 - r);
            ctx.arcTo(x1, y1, x1 - r, y1, r);

            // Bottom edge, right to left, broken around the legend.
            if (bg && bg.b < x1 - r) {
                ctx.lineTo(bg.b, y1);
                ctx.moveTo(Math.max(x0 + r, bg.a), y1);
            }
            ctx.lineTo(x0 + r, y1);
            ctx.arcTo(x0, y1, x0, y1 - r, r);

            // Left edge.
            ctx.lineTo(x0, y0 + r);
            ctx.arcTo(x0, y0, x0 + r, y0, r);

            ctx.stroke();
        }
    }

    // Repaint whenever anything the path depends on moves.
    Connections {
        target: frame
        function onTitleChanged() { border.requestPaint(); }
        function onLegendChanged() { border.requestPaint(); }
        function onThicknessChanged() { border.requestPaint(); }
        function onRadiusChanged() { border.requestPaint(); }
        function onTopInsetChanged() { border.requestPaint(); }
        function onBottomInsetChanged() { border.requestPaint(); }
        function onLineColorChanged() { border.requestPaint(); }
        function onDrawnChanged() { border.requestPaint(); }
    }

    Item {
        id: topRight

        visible: frame.drawn

        x: frame.width - frame.labelInset - width
        y: frame.topInset + frame.thickness / 2 - height / 2

        width: frame.topRightWidth
        height: childrenRect.height

        onWidthChanged: border.requestPaint()
    }

    Text {
        id: titleLabel

        x: frame.labelInset
        y: frame.topInset + frame.thickness / 2 - height / 2
        text: frame.title
        color: frame.accentColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        visible: frame.drawn && frame.title.length > 0
    }

    // One label per entry rather than one Text for the row, so each carries its
    // own hit area. Positions come from `legendOffsets`, which measures the
    // same string the border breaks around.
    Repeater {
        model: frame.drawn ? frame.legendShown : []

        Text {
            id: label

            required property int index
            required property var modelData

            x: frame.labelInset + (frame.legendOffsets[index] !== undefined ? frame.legendOffsets[index] : 0)
            y: frame.height - frame.bottomInset - frame.thickness / 2 - height / 2

            text: frame.legendMarkups[index] !== undefined ? frame.legendMarkups[index] : ""
            textFormat: Text.StyledText

            // The word brightens under the pointer; the key hint keeps its
            // accent. The hint is an advertisement for the keyboard and is
            // coloured at rest -- taking it over for hover feedback would make
            // it say something different depending on where the mouse is.
            color: hit.containsMouse ? Theme.foregroundBright : frame.labelColor

            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBaseSize

            MouseArea {
                id: hit

                anchors.fill: parent

                // The hit area overhangs the glyphs. A label sits on the
                // border line with the separator's air on either side, so the
                // overhang costs no layout and makes a one-line target
                // something a pointer can actually land on.
                anchors.topMargin: -Math.round(Theme.fontBaseSize * 0.35)
                anchors.bottomMargin: -Math.round(Theme.fontBaseSize * 0.35)
                anchors.leftMargin: -Math.round(Theme.fontBaseSize * 0.2)
                anchors.rightMargin: -Math.round(Theme.fontBaseSize * 0.2)

                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                // Only where a click can mean one thing. `←/→ volume` names a
                // pair, and a pointer landing on the word between the arrows
                // has said nothing about which way -- picking one would be the
                // control guessing. Those labels stay captions: no pointer
                // cursor, no hover, and the keys still work.
                enabled: label.modelData.keys !== undefined && label.modelData.keys.length === 1

                onClicked: frame.legendActivated(label.modelData.keys)
            }
        }
    }

    Item {
        id: body

        anchors.fill: parent
        anchors.leftMargin: frame.edge + frame.pad
        anchors.rightMargin: frame.edge + frame.pad
        anchors.topMargin: frame.topInset * 2 + frame.edge + frame.pad
        anchors.bottomMargin: frame.bottomInset * 2 + frame.edge + frame.pad
    }
}
