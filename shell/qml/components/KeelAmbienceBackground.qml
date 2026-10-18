import QtQuick
import Sailfish.Silica 1.0

// The ambience behind a Keel app. Under a host, Keel's ApplicationWindow
// leaves its background transparent and the host draws this, as Lipstick
// does; it is the same treatment Keel gives its own window off-host.
Item {
    id: root

    property string wallpaper
    property bool light: false
    // How much the tone dims the wallpaper; lower lets the ambience show.
    property real toneOpacity: light ? 0.45 : 0.62
    readonly property bool ready: image.status === Image.Ready || previous.visible

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

        // Another ambience's wallpaper cross-fades in, as Keel's own window
        // and Silica's wallpaper window do; a resize swaps in place.
        property url _shown
        property string _shownWallpaper
        onSourceChanged: {
            if (_shown.toString() !== "" && source.toString() !== "" && root.wallpaper !== _shownWallpaper) {
                previous.source = _shown;
                previous.opacity = 1;
                if (status === Image.Ready)
                    previousFade.restart();
            }
            _shown = source;
            _shownWallpaper = root.wallpaper;
        }
        onStatusChanged: {
            if (status === Image.Ready && previous.opacity > 0)
                previousFade.restart();
        }
    }

    Image {
        id: previous

        objectName: "previousWallpaper"
        anchors.fill: parent
        visible: opacity > 0 && status === Image.Ready
        opacity: 0
        smooth: true
        cache: true
        asynchronous: true

        NumberAnimation on opacity {
            id: previousFade

            running: false
            to: 0
            duration: 400
            easing.type: Easing.InOutQuad
            onFinished: previous.source = ""
        }
    }

    Rectangle {
        objectName: "tone"
        anchors.fill: parent
        visible: root.ready
        color: root.light ? "white" : "black"
        opacity: root.toneOpacity
    }

    Rectangle {
        objectName: "dimmer"
        anchors.fill: parent
        visible: root.ready && !root.light
        color: Theme.highlightDimmerColor
        opacity: 0.12
    }
}
