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
    // Each entry is { label: string, priority: number }.
    property var legendItems: []

    readonly property real legendAvailable: Math.max(0, width - labelInset - labelPad - radius - thickness)

    readonly property string legend: {
        // Named so the binding re-runs when the theme changes the metric:
        // advanceWidth() is a call, not a property, and would not be tracked.
        const family = Theme.fontFamily;
        const size = Theme.fontBaseSize;
        const available = frame.legendAvailable;

        let shown = frame.legendItems.slice();

        while (shown.length > 0) {
            const text = shown.map(e => e.label).join(frame.legendSeparator);
            if (legendFont.advanceWidth(text) <= available)
                return text;

            let weakest = 0;
            for (let i = 1; i < shown.length; i++) {
                if (shown[i].priority < shown[weakest].priority)
                    weakest = i;
            }
            shown.splice(weakest, 1);
        }

        return "";
    }

    readonly property string legendSeparator: "   "

    // 42Hz's shared line weight, so a frame and a divider cannot end up
    // different thicknesses.
    property real thickness: Theme.lineThickness
    property real radius: 4

    // Where the labels sit along their edge, and how much line they displace.
    property real labelInset: 12
    property real labelPad: 7

    // Air between the content and the border.
    property real contentPad: 8

    // A label is centred on its edge, so half of it falls outside the border.
    // The border is pulled in by that half rather than relying on the parent
    // leaving room -- otherwise the bottom legend is clipped by the window,
    // which the top title survives only because a text box has slack above the
    // cap height and none below the descender.
    readonly property real topInset: titleLabel.visible ? Math.max(0, titleLabel.height / 2 - thickness / 2) : 0
    readonly property real bottomInset: legendLabel.visible ? Math.max(0, legendLabel.height / 2 - thickness / 2) : 0

    // Children go inside the border.
    default property alias content: body.data

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
            const tg = frame.title.length > 0 ? {
                "a": frame.labelInset - frame.labelPad,
                "b": frame.labelInset + titleMetrics.width + frame.labelPad
            } : null;
            const bg = frame.legend.length > 0 ? {
                "a": frame.labelInset - frame.labelPad,
                "b": frame.labelInset + legendMetrics.width + frame.labelPad
            } : null;

            ctx.strokeStyle = frame.lineColor;
            ctx.lineWidth = t;
            ctx.lineCap = "butt";
            ctx.beginPath();

            // Top edge, broken around the title.
            ctx.moveTo(x0 + r, y0);
            if (tg && tg.b < x1 - r) {
                ctx.lineTo(Math.max(x0 + r, tg.a), y0);
                ctx.moveTo(tg.b, y0);
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
    }

    Text {
        id: titleLabel

        x: frame.labelInset
        y: frame.topInset + frame.thickness / 2 - height / 2
        text: frame.title
        color: frame.accentColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        visible: frame.title.length > 0
    }

    Text {
        id: legendLabel

        x: frame.labelInset
        y: frame.height - frame.bottomInset - frame.thickness / 2 - height / 2
        text: frame.legend
        color: frame.labelColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBaseSize
        visible: frame.legend.length > 0
    }

    Item {
        id: body

        anchors.fill: parent
        anchors.leftMargin: frame.thickness + frame.contentPad
        anchors.rightMargin: frame.thickness + frame.contentPad
        anchors.topMargin: frame.topInset * 2 + frame.thickness + frame.contentPad
        anchors.bottomMargin: frame.bottomInset * 2 + frame.thickness + frame.contentPad
    }
}
