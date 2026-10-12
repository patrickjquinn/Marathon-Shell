import QtQuick
import Sailfish.Silica as S

// The visible keyboard-focus indicator, in the ambience's highlight colour.
Rectangle {
    property bool showing: parent && parent.activeFocus

    objectName: "focusFrame"
    anchors.fill: parent
    z: 1000
    visible: showing
    color: "transparent"
    radius: S.Theme.paddingSmall
    border.width: Math.max(2, Math.round(S.Theme.pixelRatio * 2))
    border.color: S.Theme.highlightColor
}
