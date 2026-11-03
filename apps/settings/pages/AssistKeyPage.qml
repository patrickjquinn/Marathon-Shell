pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    component ActionCombo: ComboBox {
        id: combo

        required property string value
        signal chosen(string action)

        width: parent.width
        Binding on currentIndex {
            value: Logic.assistKeyActions.findIndex(a => a.id === combo.value)
        }
        menu: ContextMenu {
            Repeater {
                model: Logic.assistKeyActions

                MenuItem {
                    required property var modelData

                    text: modelData.title
                    onClicked: combo.chosen(modelData.id)
                }
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Assistant key")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("The key between the volume keys. It works in any app, and on the lock screen after your PIN.")
            }
            ActionCombo {
                objectName: "assistPressCombo"
                label: qsTr("Press")
                value: Settings.assistKeyPress
                onChosen: action => Settings.assistKeyPress = action
            }
            ActionCombo {
                objectName: "assistHoldCombo"
                label: qsTr("Press and hold")
                value: Settings.assistKeyHold
                onChosen: action => Settings.assistKeyHold = action
            }
        }

        VerticalScrollDecorator {}
    }
}
