import QtQuick
import Sailfish.Silica as S

S.DialogHeader {
    id: root

    objectName: "dialogHeader"
    Accessible.role: Accessible.Heading
    Accessible.name: title

    // The pinned accept/cancel band is see-through over a transparent app
    // window; back it once content scrolls beneath.
    Rectangle {
        objectName: "dialogHeaderBackdrop"
        parent: root.flickable ? root.flickable.contentItem : root
        x: root.flickable ? root.x : 0
        y: root.flickable ? Math.max(root.flickable.contentY, root.flickable.originY) : 0
        z: 9998
        width: root.width
        height: root._overlayHeight
        color: Qt.rgba(S.Theme.overlayBackgroundColor.r, S.Theme.overlayBackgroundColor.g, S.Theme.overlayBackgroundColor.b, 1)
        visible: root.flickable !== null && root.flickable.contentY > root.flickable.originY
    }
}
