import QtQuick
import Sailfish.Silica 1.0

// The ambience behind a Keel app. Under a host, Keel's ApplicationWindow
// leaves its background transparent and the host draws this, as Lipstick
// does; it is the same treatment Keel gives its own window off-host.
Item {
    id: root

    property string wallpaper
    property bool light: false
    readonly property bool ready: image.status === Image.Ready

    layer.enabled: ready

    Rectangle {
        anchors.fill: parent
        color: root.light ? "#e9eff2" : "#060b12"
    }

    Image {
        id: image

        objectName: "wallpaper"
        anchors.fill: parent
        smooth: true
        cache: true
        asynchronous: true
        source: root.visible && root.wallpaper !== "" && width > 0 && height > 0 ? "image://keelambience/" + encodeURIComponent(root.wallpaper) + "?w=" + Math.round(width) + "&h=" + Math.round(height) : ""
    }

    Rectangle {
        objectName: "tone"
        anchors.fill: parent
        visible: root.ready
        color: root.light ? "white" : "black"
        opacity: root.light ? 0.45 : 0.62
    }

    Rectangle {
        objectName: "dimmer"
        anchors.fill: parent
        visible: root.ready && !root.light
        color: Theme.highlightDimmerColor
        opacity: 0.12
    }
}
