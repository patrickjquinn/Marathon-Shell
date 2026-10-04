import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Flathub icon in the DS tile: elev-3 square, black hairline, top-edge
// highlight. The glyph shows until the image is Ready, so a slow or failed
// fetch reads as a placeholder rather than an empty box.
Rectangle {
    id: tile

    property url source
    // Retried because a lookup can fail while the resolver settles after boot
    // or resume, and a pooled runner outlives that. Each retry changes only
    // the fragment: never sent to the server, but a new pixmap-cache key, so
    // Image refetches.
    property int attempt: 0

    onSourceChanged: attempt = 0
    radius: Math.max(MRadius.md, Math.round(width * 0.18))
    color: MColors.elev3
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.6)

    Image {
        id: img
        anchors.fill: parent
        anchors.margins: Math.round(parent.width * 0.12)
        source: tile.source.toString() === "" ? "" : tile.source + (tile.attempt > 0 ? "#retry" + tile.attempt : "")
        sourceSize: Qt.size(192, 192)
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
    Timer {
        interval: 3000 * (tile.attempt + 1)
        running: img.status === Image.Error && tile.attempt < 3
        onTriggered: tile.attempt++
    }
    Icon {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        name: "package"
        size: Math.round(parent.width * 0.42)
        color: MColors.textTertiary
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 1
        height: 1
        color: Qt.rgba(1, 1, 1, 0.12)
    }
}
