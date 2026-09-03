import MarathonOS.Shell 1.0
import MarathonUI.Core
import QtQuick
import QtQuick.Controls

Item {
    id: toolBar

    signal clipboardClicked
    signal emojiClicked
    signal settingsClicked
    signal dismissClicked

    component ToolButton: AbstractButton {
        id: toolButton
        property string iconName: ""

        width: Math.round(40 * Constants.scaleFactor)
        height: Math.round(30 * Constants.scaleFactor)
        onClicked: HapticManager.light()

        background: Rectangle {
            color: toolButton.pressed ? "#33ffffff" : "transparent"
            radius: 4
        }

        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                name: toolButton.iconName
                size: Math.round(20 * Constants.scaleFactor)
                color: "white"
                opacity: 0.9
            }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: Math.round(24 * Constants.scaleFactor)

        ToolButton {
            iconName: "file-text"
            onClicked: toolBar.clipboardClicked()
        }

        ToolButton {
            iconName: "star"
            onClicked: toolBar.emojiClicked()
        }

        ToolButton {
            iconName: "settings"
            onClicked: toolBar.settingsClicked()
        }

        ToolButton {
            iconName: "chevron-down"
            onClicked: toolBar.dismissClicked()
        }
    }
}
