import QtQuick
import ee.ui

// Character-cell spectrum, the way cava and btop draw one: each column is a
// text cell, and the block elements U+2581..U+2588 give eight sub-steps of
// vertical resolution inside it. The font is whatever Omarchy's `monospace`
// alias resolves to, so this follows `omarchy font set` like everything else.
//
// Cell size is measured rather than assumed. That is the price of a character
// grid: the user can change the font underneath us at any time.
//
// The cells are drawn apart rather than flush. Block elements tile seamlessly
// by design, so a grid drawn at the font's own advance and line height reads
// as a filled silhouette -- the cells are there but nothing on screen says so.
// A cell is given air on all four sides instead, which costs a little of the
// glyph's tiling and buys the thing this style exists for: a picture visibly
// made of discrete elements.
//
// Heights are absolute, from the same fixed dB window the bar renderer uses.
// The two styles have to agree about what a given level looks like, or
// switching between them would read as the signal changing.
Item {
    id: grid

    property var points: []

    // Target column width in pixels, the same control the bar renderer takes.
    // A character grid cannot honour it exactly -- a column is a whole number
    // of cells or it is not a character grid -- so it rounds to the nearest
    // cell and the steps are coarse. Coarse is the honest answer here; ignoring
    // the control while still showing its value would not be.
    property int barWidth: 10
    property color lowColor: Theme.spectrumLow
    property color highColor: Theme.spectrumHigh
    property int fontSize: Theme.fontBaseSize

    // Measured through fm.font, not by calling advanceWidth() alone.
    //
    // advanceWidth() is a call and captures no dependency, so this froze at
    // whatever the default font measured before Theme had been applied -- 10.8
    // px against a real 7.2 -- and never re-evaluated. The grid asked for two
    // thirds of the columns that fit and drew a spectrum that stopped short of
    // the right edge, which read as missing signal rather than as a bug.
    readonly property real glyphWidth: fm.font.pixelSize > 0 ? fm.advanceWidth("█") : 1
    readonly property real glyphHeight: fm.height

    // The least air a division can be drawn in, taken from the glyph rather
    // than fixed in pixels so it holds its proportion through `omarchy display
    // text size`. Floored at one pixel: a division rounded to zero is no
    // division. It is a minimum and not the answer -- the pitches below stretch
    // past it.
    readonly property real minSpacingX: Math.max(1, Math.round(grid.glyphWidth * 0.22))
    readonly property real minLeadingY: Math.max(1, Math.round(grid.glyphHeight * 0.16))

    // How many cells fit at the tightest spacing. Counted against glyph plus
    // minimum air rather than against the bare advance, or the row would ask
    // for more cells than the width can hold and overrun it by exactly the
    // spacing.
    readonly property int cellsPerColumn: Math.max(1, Math.round(grid.barWidth / Math.max(1, grid.glyphWidth + grid.minSpacingX)))

    readonly property int cols: Math.max(2, Math.floor(width / Math.max(1, (grid.glyphWidth + grid.minSpacingX) * grid.cellsPerColumn)))
    readonly property int rows: Math.max(1, Math.floor(height / Math.max(1, grid.glyphHeight + grid.minLeadingY)))

    // The divisions absorb the remainder, so the grid lands exactly on the
    // item's edges.
    //
    // A whole number of cells divides the width and the height with something
    // left over, and parking that leftover at an edge is what put this style
    // out of agreement with the bars. Vertically it cost real accuracy: the
    // unused strip sat above the spectrum, every level was drawn into a
    // shorter box than the one the bars use, and a -20 dB tone read 150 px
    // tall against the bar renderer's 167. Two styles disagreeing about what a
    // level looks like is the one thing `project.md` says they may not do.
    //
    // Stretching the air instead makes the top row's ink start at 0 and the
    // bottom row's finish at `height`, which is the box the bars draw in --
    // and a slightly looser grid is no worse to look at than a tight one held
    // off its own floor.
    //
    // The horizontal division is drawn by letterSpacing rather than by spending
    // a whole cell on a gap. At the default density a column is a single cell
    // wide, so a spacer cell would halve the number of columns the window can
    // hold -- paying for the divisions in signal, which is the wrong currency.
    readonly property real cellPitchX: grid.cols > 0 && grid.cellsPerColumn > 0 ? width / (grid.cols * grid.cellsPerColumn) : grid.glyphWidth
    readonly property real cellSpacing: Math.max(0, grid.cellPitchX - grid.glyphWidth)

    // One row cannot have a pitch -- there is no second row to be spaced from
    // -- so it is placed on the floor directly and the whole remainder goes
    // above it, where the bars would leave it too.
    readonly property real cellPitchY: grid.rows > 1 ? (height - grid.glyphHeight) / (grid.rows - 1) : 0
    readonly property real gridTop: grid.rows > 1 ? 0 : Math.max(0, height - grid.glyphHeight)

    property var lines: []

    FontMetrics {
        id: fm

        font.family: Theme.fontFamily
        font.pixelSize: grid.fontSize
    }

    // One column per point, so the core resamples to exactly the number of
    // cells we can draw. This is the whole of "responsive resampling" -- it
    // writes through to 42Hz's own settings, which is why it is a real
    // binding and not a render-time trick.
    onColsChanged: {
        DbSpectrum.nPoints = grid.cols;
        grid.rebuild();
    }

    onCellsPerColumnChanged: grid.rebuild()

    Component.onCompleted: DbSpectrum.nPoints = grid.cols

    onPointsChanged: grid.rebuild()
    onRowsChanged: grid.rebuild()

    function rebuild() {
        const pts = grid.points;
        const n = pts.length;
        const cols = grid.cols;
        const rows = grid.rows;

        if (n === 0 || cols <= 0 || rows <= 0) {
            grid.lines = [];
            return;
        }

        // Column heights, in eighths of a cell.
        const eighths = new Array(cols);
        for (let c = 0; c < cols; c++) {
            const i = Math.min(n - 1, Math.floor(c * n / cols));
            eighths[c] = Math.round(SpectrumScale.normalize(pts[i].y) * rows * 8);
        }

        const BLOCKS = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"];
        const out = [];
        for (let r = 0; r < rows; r++) {
            const floorOfRow = (rows - 1 - r) * 8;
            let s = "";
            for (let c = 0; c < cols; c++) {
                const e = eighths[c] - floorOfRow;
                s += (e >= 8 ? "█" : (e <= 0 ? " " : BLOCKS[e])).repeat(grid.cellsPerColumn);
            }
            out.push(s);
        }
        grid.lines = out;
    }

    Repeater {
        model: grid.rows

        Text {
            required property int index

            // Rows near the top are peaks, so they take the top of the ramp.
            readonly property real ramp: grid.rows > 1 ? 1 - (index / (grid.rows - 1)) : 1

            x: 0
            y: grid.gridTop + index * grid.cellPitchY
            text: grid.lines[index] !== undefined ? grid.lines[index] : ""
            color: Qt.rgba(grid.lowColor.r + (grid.highColor.r - grid.lowColor.r) * ramp, grid.lowColor.g + (grid.highColor.g - grid.lowColor.g) * ramp, grid.lowColor.b + (grid.highColor.b - grid.lowColor.b) * ramp, 1)
            font.family: Theme.fontFamily
            font.pixelSize: grid.fontSize
            font.letterSpacing: grid.cellSpacing
        }
    }
}
