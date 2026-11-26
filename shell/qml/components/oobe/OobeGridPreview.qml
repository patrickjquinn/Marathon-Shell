import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import ".."
import "../../core/LauncherGrid.js" as LauncherGrid

// The real home grid on the chosen wallpaper, with the pill.
Item {
    id: root

    property alias grid: homeGrid
    property alias wallpaper: backdrop
    property int rows: 2
    // An icon cell's content: icon, gap, one line of label; the grid's row gap and top margin.
    readonly property real contentHeight: Silica.Theme.iconSizeLauncher + Math.round(10 * Constants.scaleFactor) + label.height
    readonly property real rowGap: Math.round(8 * Constants.scaleFactor)
    readonly property real gridTop: 10
    // Home's row: its page between the status and nav bars, less the dock, over its rows.
    readonly property real windowHeight: Window.contentItem && Window.contentItem.height > 0 ? Window.contentItem.height : Constants.screenHeight
    readonly property int homeRows: LauncherGrid.rows(windowHeight, Silica.Theme.iconSizeLauncher)
    readonly property real homeCell: Math.max(contentHeight, (windowHeight - Constants.statusBarHeight - Constants.navBarHeight - gridTop - Constants.bottomBarHeight - 12 - (homeRows - 1) * rowGap) / homeRows)
    // One whole row with the pill under it; below that the pill gives way.
    readonly property real oneRowHeight: gridTop + contentHeight + 2 * Silica.Theme.paddingMedium + pill.height
    readonly property bool showPill: height >= oneRowHeight
    readonly property real pillSpace: showPill ? 2 * Silica.Theme.paddingMedium + pill.height : 0
    readonly property real rowSpace: height - pillSpace - gridTop
    readonly property int fitRows: Math.max(1, Math.floor((rowSpace + rowGap) / (homeCell + rowGap)))
    // Home's pitch, squeezed only where a single row would not fit whole.
    readonly property real cellHeight: Math.max(contentHeight, Math.min(homeCell, (rowSpace - (rows - 1) * rowGap) / rows))

    clip: true

    FontMetrics {
        id: label

        font.pixelSize: Silica.Theme.fontSizeTiny
        font.family: Silica.Theme.fontFamily
    }

    WallpaperReveal {
        id: backdrop

        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.35
    }

    // The home grid keeps room below for the dock, which the preview leaves
    // out, and never squeezes a row shorter than its icon.
    MarathonAppGrid {
        id: homeGrid

        width: parent.width
        height: root.gridTop + root.rows * root.cellHeight + (root.rows - 1) * root.rowGap + Constants.bottomBarHeight + 12
        appModel: apps
        rows: root.rows
        enabled: false
    }

    FilteredAppModel {
        id: apps
    }

    Rectangle {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Silica.Theme.paddingMedium
        width: Silica.Theme.itemSizeLarge
        height: Math.max(2, Silica.Theme.paddingSmall / 2)
        radius: height / 2
        visible: root.showPill
        color: Silica.Theme.primaryColor
        opacity: Silica.Theme.opacityHigh
    }
}
