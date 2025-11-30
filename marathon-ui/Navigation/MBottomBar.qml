import QtQuick
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    id: root

    property var actions: []

    signal actionClicked(int index)

    width: parent ? parent.width : 400
    height: 72
    color: MColors.bb10Elevated
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    Row {
        anchors.centerIn: parent
        spacing: MSpacing.md

        Repeater {
            model: root.actions

            MButton {
                text: modelData.text || ""
                iconName: modelData.icon || ""
                variant: modelData.variant || "default"
                onClicked: root.actionClicked(index)
            }
        }
    }
}
