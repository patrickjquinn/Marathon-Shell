import QtQuick
import Sailfish.Silica as S

// The pinned accept/cancel band is see-through over a transparent app
// window; this backs it once content scrolls beneath, with the slice of
// the host's ambience (KeelAmbienceBackground) that sits behind it.
Rectangle {
    id: root

    property Item header
    property string wallpaper: S.Theme._backgroundImage
    readonly property Flickable _flickable: header ? header.flickable : null
    readonly property bool _light: S.Theme.colorScheme === S.Theme.DarkOnLight
    // The band is pinned to contentY, so its window position only moves
    // with the header or the page.
    readonly property point _windowPos: {
        x;
        y;
        return Window.window ? mapToItem(null, 0, 0) : Qt.point(0, 0);
    }

    objectName: "dialogHeaderBackdrop"
    parent: _flickable ? _flickable.contentItem : null
    x: header ? header.x : 0
    y: _flickable ? Math.max(_flickable.contentY, _flickable.originY) : 0
    z: 9998
    width: header ? header.width : 0
    height: header ? header._overlayHeight : 0
    color: _light ? "#e9eff2" : "#060b12"
    clip: true
    visible: _flickable !== null && _flickable.contentY > _flickable.originY

    Image {
        id: image

        objectName: "dialogHeaderWallpaper"
        x: -root._windowPos.x
        y: -root._windowPos.y
        width: root.Window.width
        height: root.Window.height
        smooth: true
        cache: true
        asynchronous: true
        // Same request as the host's, so the blur matches what is around the band.
        source: root.visible && root.wallpaper !== "" && width > 0 && height > 0 ? "image://keelambience/" + encodeURIComponent(root.wallpaper) + "?w=" + Math.round(width) + "&h=" + Math.round(height) : ""
    }

    Rectangle {
        anchors.fill: parent
        visible: image.status === Image.Ready
        color: root._light ? "white" : "black"
        opacity: root._light ? 0.45 : 0.62
    }

    Rectangle {
        anchors.fill: parent
        visible: image.status === Image.Ready && !root._light
        color: S.Theme.highlightDimmerColor
        opacity: 0.12
    }
}
