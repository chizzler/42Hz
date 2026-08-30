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
    readonly property real cellWidth: fm.font.pixelSize > 0 ? fm.advanceWidth("█") : 1
    readonly property real cellHeight: fm.height
    readonly property int cellsPerColumn: Math.max(1, Math.round(grid.barWidth / Math.max(1, grid.cellWidth)))

    readonly property int cols: Math.max(2, Math.floor(width / Math.max(1, cellWidth * cellsPerColumn)))
    readonly property int rows: Math.max(1, Math.floor(height / Math.max(1, cellHeight)))

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
            y: index * grid.cellHeight
            text: grid.lines[index] !== undefined ? grid.lines[index] : ""
            color: Qt.rgba(grid.lowColor.r + (grid.highColor.r - grid.lowColor.r) * ramp, grid.lowColor.g + (grid.highColor.g - grid.lowColor.g) * ramp, grid.lowColor.b + (grid.highColor.b - grid.lowColor.b) * ramp, 1)
            font.family: Theme.fontFamily
            font.pixelSize: grid.fontSize
        }
    }
}
