import MarathonOS.Shell
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

    // On the phone the window is the screen: sized so from the start, the
    // shell isn't laid out (and its wallpaper decoded) at 390×844 first.
    readonly property bool fullScreen: Qt.platform.pluginName === "eglfs" || Qt.platform.pluginName === "linuxfb"

    width: fullScreen ? Screen.width : 390
    height: fullScreen ? Screen.height : 844
    visible: true
    title: "Marathon OS - Bandit"  // i18n: not user-facing
    color: MColors.eink ? MColors.background : "#000000"

    MarathonShell {
        anchors.fill: parent
        focus: true
    }
}
