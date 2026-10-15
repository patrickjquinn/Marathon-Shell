import QtQuick
import Sailfish.Silica as S

// The pinned accept/cancel band is see-through over a transparent app
// window; this backs it once content scrolls beneath.
Rectangle {
    property Item header
    readonly property Flickable _flickable: header ? header.flickable : null

    objectName: "dialogHeaderBackdrop"
    parent: _flickable ? _flickable.contentItem : null
    x: header ? header.x : 0
    y: _flickable ? Math.max(_flickable.contentY, _flickable.originY) : 0
    z: 9998
    width: header ? header.width : 0
    height: header ? header._overlayHeight : 0
    color: Qt.rgba(S.Theme.overlayBackgroundColor.r, S.Theme.overlayBackgroundColor.g, S.Theme.overlayBackgroundColor.b, 1)
    visible: _flickable !== null && _flickable.contentY > _flickable.originY
}
