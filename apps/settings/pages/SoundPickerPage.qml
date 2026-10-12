pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings

Page {
    id: page

    // "ringtone", "notification" or "alarm".
    property string soundType: "ringtone"
    readonly property string key: ({ ringtone: "ringtone", notification: "notificationSound", alarm: "alarmSound" })[soundType]
    readonly property string current: Settings[key]

    function choose(path) {
        Settings[key] = path;
        Audio.previewSound(path);
    }

    SilicaListView {
        id: view

        objectName: "soundList"
        anchors.fill: parent
        model: page.soundType === "notification" ? Settings.availableNotificationSounds() : page.soundType === "alarm" ? Settings.availableAlarmSounds() : Settings.availableRingtones()
        header: PageHeader {
            title: SettingsController.soundTypeLabel(page.soundType)
            description: qsTr("Tap a sound to choose and hear it")
        }

        delegate: ListItem {
            id: item

            required property string modelData
            readonly property bool selected: modelData === page.current

            objectName: "sound-" + Settings.formatSoundName(modelData)
            Accessible.role: Accessible.RadioButton
            Accessible.name: Settings.formatSoundName(modelData)
            Accessible.checked: selected
            onClicked: page.choose(modelData)

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: check.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }
                text: Settings.formatSoundName(item.modelData)
                truncationMode: TruncationMode.Fade
                color: item.selected || item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Icon {
                id: check

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                visible: item.selected
                source: "image://theme/icon-s-accept"
                color: Theme.highlightColor
            }
        }

        ViewPlaceholder {
            enabled: view.count === 0
            text: qsTr("No sounds installed")
        }

        VerticalScrollDecorator {}
    }
}
