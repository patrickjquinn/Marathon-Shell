pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Notifications")
            }
            TextSwitch {
                objectName: "dndSwitch"
                text: qsTr("Do not disturb")
                description: qsTr("Silences notifications and calls")
                automaticCheck: false
                checked: Settings.dndEnabled
                onClicked: {
                    Settings.dndEnabled = !checked;
                    Audio.setDoNotDisturb(Settings.dndEnabled);
                }
            }
            TextSwitch {
                objectName: "lockScreenSwitch"
                text: qsTr("Show on lock screen")
                description: qsTr("Shows notifications while the device is locked")
                automaticCheck: false
                checked: Settings.showNotificationsOnLockScreen
                onClicked: Settings.showNotificationsOnLockScreen = !checked
            }
            ValueButton {
                objectName: "soundButton"
                label: qsTr("Notification sound")
                value: Settings.formatSoundName(Settings.notificationSound)
                onClicked: pageStack.push(Qt.resolvedUrl("SoundPickerPage.qml"), { soundType: "notification" })
            }

            SectionHeader {
                text: qsTr("Apps")
                visible: apps.count > 0
            }
            Repeater {
                id: apps

                objectName: "appSwitches"
                model: SettingsController.notificationApps || []

                TextSwitch {
                    required property var modelData

                    objectName: "notify-" + modelData.id
                    text: modelData.name
                    automaticCheck: false
                    checked: modelData.enabled
                    onClicked: SettingsController.setNotificationEnabled(modelData.id, !checked)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
