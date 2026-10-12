import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// A Flathub icon. The package glyph shows until the image is Ready, so a
// slow or failed fetch reads as a placeholder rather than an empty box.
Item {
    id: root

    property url source
    // Retried because a lookup can fail while the resolver settles after boot
    // or resume, and a pooled runner outlives that. Each retry changes only
    // the fragment: never sent to the server, but a new pixmap-cache key, so
    // Image refetches.
    property int attempt: 0

    onSourceChanged: attempt = 0

    Image {
        id: img
        anchors.fill: parent
        source: root.source.toString() === "" ? "" : root.source + (root.attempt > 0 ? "#retry" + root.attempt : "")
        sourceSize: Qt.size(192, 192)
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
    Timer {
        interval: 3000 * (root.attempt + 1)
        running: img.status === Image.Error && root.attempt < 3
        onTriggered: root.attempt++
    }
    Icon {
        anchors.centerIn: parent
        width: Math.min(parent.width, Theme.iconSizeMedium)
        height: width
        visible: img.status !== Image.Ready
        source: "image://theme/icon-m-package"
        color: Theme.secondaryColor
    }
}
