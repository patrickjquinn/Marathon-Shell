import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import ".."

// The real home grid on the chosen wallpaper, with the pill.
Item {
    id: root

    property alias grid: homeGrid
    property alias wallpaper: backdrop
    property int rows: 2

    clip: true

    WallpaperReveal {
        id: backdrop

        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.35
    }

    MarathonAppGrid {
        id: homeGrid

        anchors.fill: parent
        appModel: apps
        rows: root.rows
        enabled: false
    }

    FilteredAppModel {
        id: apps
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Silica.Theme.paddingMedium
        width: Silica.Theme.itemSizeLarge
        height: Math.max(2, Silica.Theme.paddingSmall / 2)
        radius: height / 2
        color: Silica.Theme.primaryColor
        opacity: Silica.Theme.opacityHigh
    }
}
