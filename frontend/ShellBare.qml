import QtQuick
import ee.ui

// BARE: the spectrum and nothing else, at any size.
//
// The mouse does nothing and no chrome is ever drawn. The one exception is the
// state report, because "nothing to draw" and "nothing to say" are not the
// same thing -- a window that reports nothing when audio is gone is not
// minimal, it is broken.
Item {
    id: shell

    property var points: []
    property int barWidth: 10
    property var stateReport: ({})

    Spectrum {
        anchors.fill: parent

        points: shell.points
        barWidth: shell.barWidth
        gap: 2
    }

    StateReport {
        anchors.fill: parent

        title: shell.stateReport.title ?? ""
        detail: shell.stateReport.detail ?? ""
        isError: shell.stateReport.error ?? false
    }
}
