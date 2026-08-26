import re, pathlib, sys
root = pathlib.Path("/tmp/claude-1000/-home-chee-Work-42Hz/3098ccf0-1dff-4961-b532-c84719de4a63/scratchpad/spike-42hz")

def edit(p, fn):
    f = root / p
    s = f.read_text()
    s2 = fn(s)
    f.write_text(s2)
    print(f"  patched {p} ({len(s)} -> {len(s2)} bytes)")

# ---- top-level CMakeLists: drop KDE UI + QtGraphs components ----
def top(s):
    for comp in ["Kirigami", "KirigamiAddons", "QQC2DesktopStyle", "IconThemes", "ColorScheme"]:
        s = re.sub(rf"^\s*{comp}\s*$\n", "", s, flags=re.M)
    s = re.sub(r"^\s*Graphs\s*$\n", "", s, flags=re.M)
    s = re.sub(r"^ecm_find_qmlmodule\(org\.kde\.kirigami REQUIRED\)\s*$\n", "", s, flags=re.M)
    return s
edit("CMakeLists.txt", top)

# ---- src/CMakeLists: replace QML_FILES list, drop kcolor_manager + KDE UI links ----
def src(s):
    lines = s.split("\n")
    start = next(i for i,l in enumerate(lines) if l.strip() == "QML_FILES")
    end   = next(i for i,l in enumerate(lines) if i > start and l.startswith(")"))
    lines[start:end] = ["    QML_FILES", "        contents/ui/Main.qml"]
    s = "\n".join(lines)
    s = re.sub(r"^\s*kcolor_manager\.cpp\s*$\n", "", s, flags=re.M)
    for lib in ["KF6::ColorScheme", "KF6::IconThemes", "Qt::Graphs"]:
        s = re.sub(rf"^\s*{re.escape(lib)}\s*$\n", "", s, flags=re.M)
    return s
edit("src/CMakeLists.txt", src)

# ---- main.cpp: strip KDE theming ----
def main(s):
    for inc in ["#include <KColorSchemeManager>", "#include <KIconTheme>",
                '#include "kcolor_manager.hpp"']:
        s = s.replace(inc + "\n", "")
    s = s.replace("  KIconTheme::initTheme();\n", "")
    s = s.replace("  KColorSchemeManager::instance();\n", "")
    s = s.replace("  auto color_manager = std::make_unique<KColorManager>();\n", "")
    # drop breeze style + kde desktop QQC2 style blocks
    s = re.sub(r"\n  if \(DbMain::forceBreezeTheme\(\)\) \{\n.*?\n  \}\n", "\n", s, flags=re.S)
    s = re.sub(r"\n  if \(qEnvironmentVariableIsEmpty\(\"QT_QUICK_CONTROLS_STYLE\"\)\) \{\n.*?\n  \}\n", "\n", s, flags=re.S)
    return s
edit("src/main.cpp", main)

for f in ["src/kcolor_manager.cpp", "src/kcolor_manager.hpp"]:
    (root / f).unlink()
    print(f"  removed {f}")

# ---- minimal plain-QtQuick frontend ----
ui = root / "src/contents/ui"
for q in ui.glob("*.qml"):
    q.unlink()
(ui / "Main.qml").write_text('''import QtQuick
import QtQuick.Window
import ee.ui

Window {
    id: root
    // supplied via engine.setInitialProperties() in main.cpp
    property string applicationName: "42Hz"
    property string applicationId: "io.omarchy.42hz"
    property bool canUseSysTray: false

    width: 480; height: 200
    visible: true
    title: root.applicationName
    color: "#111c18"                       // Omarchy: theme background

    property var points: []

    Connections {
        target: StreamOutputEffects
        function onNewSpectrumData(newData) {
            root.points = newData
            canvas.requestPaint()
        }
    }

    Timer {
        interval: 1000 / 60; running: true; repeat: true
        onTriggered: StreamOutputEffects.requestSpectrumData()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 8
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const pts = root.points
            const n = pts.length
            if (n === 0) return

            let lo = Infinity, hi = -Infinity
            for (let i = 0; i < n; i++) {
                const v = pts[i].y
                if (v < lo) lo = v
                if (v > hi) hi = v
            }
            const span = (hi - lo) > 1e-6 ? (hi - lo) : 1

            const bw = width / n
            ctx.fillStyle = "#509475"      // Omarchy: theme accent
            for (let i = 0; i < n; i++) {
                const norm = (pts[i].y - lo) / span
                const h = norm * height
                ctx.fillRect(i * bw, height - h, Math.max(1, bw - 1), h)
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.points.length === 0
        text: "no signal"
        color: "#53685B"                   // Omarchy: theme muted
        font.family: "JetBrainsMono Nerd Font"
    }
}
''')
print("  wrote minimal src/contents/ui/Main.qml (plain QtQuick, no Kirigami)")
