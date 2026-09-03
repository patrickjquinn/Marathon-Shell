import QtQuick
import QtQuick.Window

// Local-launch canvas. Pinned to the DS canonical phone artboard
// (marathon-tokens.css .phone: 390×844 = iPhone 14 Pro scaled). With
// MARATHON_FORCE_DPI=160 the shell renders 1:1 with the design — every
// design-px token in the JSX reference == one window-px on screen, so
// visual diffs are pixel-faithful. On QEMU (720×1440) and real phones,
// ScreenMetrics + scaleFactor stretch the design up; the canvas stays
// the reference frame.
Window {
    id: window

    width: 390
    height: 844
    visible: true
    title: "Marathon OS - Bandit"
    color: "#000000"

    MarathonShell {
        anchors.fill: parent
        focus: true
    }
}
