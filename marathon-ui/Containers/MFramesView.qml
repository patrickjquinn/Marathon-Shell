import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Active Frames view — the home surface.
//
// 2×2 grid of MActiveFrame tiles. Eventually paged (swipe between
// pages of frames) but the first iteration ships a single page; the
// pager is a follow-up commit once the visual works are settled.
//
// In BB10 lineage, Active Frames IS the task switcher. The two
// designer-drawn artboards (04 ActiveFramesHome and 07 TaskSwitcher)
// are one surface; this component is the implementation. The mode
// prop drives both per-frame chrome and the bottom dock's indicator
// state (handled by the parent home component).
//
// Caller provides a `frames` array — each entry:
//   { appId, iconName, appName, badge, widget, preview, iconTint }
// where `widget` and `preview` are Components.
Item {
    id: root

    property string mode: "home"             // "home" | "switcher"
    property var frames: []
    property int gridGap: 10
    property int outerMargin: 16

    signal frameActivated(string appId)
    signal frameClosed(string appId)

    readonly property int framesPerPage: 4

    Grid {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.outerMargin
        anchors.rightMargin: root.outerMargin
        columns: 2
        rowSpacing: root.gridGap
        columnSpacing: root.gridGap

        readonly property real cellWidth: (width - columnSpacing) / 2

        Repeater {
            model: Math.min(root.framesPerPage, root.frames.length)
            delegate: MActiveFrame {
                required property int index
                readonly property var frame: root.frames[index] || {}
                width: grid.cellWidth
                height: 158
                mode: root.mode
                iconName: frame.iconName || "square"
                appName: frame.appName || ""
                badge: frame.badge || ""
                iconTint: frame.iconTint !== undefined ? frame.iconTint : MColors.marathonTealBright
                onActivated: root.frameActivated(frame.appId || "")
                onClosed: root.frameClosed(frame.appId || "")

                Loader {
                    anchors.fill: parent
                    sourceComponent: root.mode === "switcher" ? frame.preview : frame.widget
                    active: sourceComponent !== null && sourceComponent !== undefined
                }
            }
        }
    }
}
