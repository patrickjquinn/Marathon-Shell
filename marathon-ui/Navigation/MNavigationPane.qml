pragma ComponentBehavior: Bound

import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property int selectedIndex: 0
    property var items: []
    property bool expanded: false

    signal itemSelected(int index, var item)

    width: Math.round(300 * scaleFactor)
    height: parent ? parent.height : 600
    color: MColors.bb10Surface

    x: expanded ? 0 : -width

    Behavior on x {
        NumberAnimation {
            duration: MMotion.moderate
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
    }

    Column {
        anchors.fill: parent
        anchors.margins: MSpacing.lg
        spacing: MSpacing.sm

        Repeater {
            model: root.items

            Rectangle {
                id: navItem

                required property var modelData
                required property int index

                width: parent.width
                height: MSpacing.touchTargetMin
                color: index === root.selectedIndex ? Qt.rgba(0, 191 / 255, 165 / 255, 0.12) : "transparent"
                radius: MRadius.md

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: MSpacing.md
                    text: navItem.modelData.title || navItem.modelData
                    color: navItem.index === root.selectedIndex ? MColors.marathonTeal : MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.weight: navItem.index === root.selectedIndex ? MTypography.weightDemiBold : MTypography.weightNormal
                    font.family: MTypography.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.selectedIndex = navItem.index;
                        root.itemSelected(navItem.index, navItem.modelData);
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.left: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.round(1000 * root.scaleFactor)
        visible: root.expanded
        onClicked: root.expanded = false
    }
}
