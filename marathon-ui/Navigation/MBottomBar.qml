import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonOS.Shell

Rectangle {
    id: root

    property var actions: []

    signal actionClicked(int index)

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    width: parent ? parent.width : Math.round(400 * scaleFactor)
    height: Math.round(72 * scaleFactor)
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
