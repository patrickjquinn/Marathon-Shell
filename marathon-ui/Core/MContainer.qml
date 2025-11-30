import QtQuick
import MarathonUI.Theme

Item {
    id: root

    property bool fluid: false
    property alias content: contentItem.data
    property real maxWidth: 1280
    property real paddingHorizontal: MSpacing.xl

    property MResponsive responsive: MResponsive {
        screenWidth: root.width
    }

    implicitWidth: parent ? parent.width : 800
    implicitHeight: contentItem.height

    Item {
        id: contentItem
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.fluid ? parent.width - (root.paddingHorizontal * 2) : Math.min(parent.width - (root.paddingHorizontal * 2), root.maxWidth)
        height: childrenRect.height
    }
}
