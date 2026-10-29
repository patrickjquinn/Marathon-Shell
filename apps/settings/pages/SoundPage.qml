pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    function setVolume(percent) {
        Audio.setVolume(Math.max(0, Math.min(100, percent)) / 100);
    }

    // Ringtones, notifications and alarms have their own levels, which the
    // media volume does not scale.
    function setToneVolume(key, percent) {
        Settings[key] = Math.max(0, Math.min(100, percent)) / 100;
    }

    function pickSound(type) {
        pageStack.push(Qt.resolvedUrl("SoundPickerPage.qml"), {
            soundType: type
        });
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Sounds")
            }

            Slider {
                objectName: "volumeSlider"
                width: parent.width
                label: qsTr("Media volume")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                value: Logic.percent(Audio.volume)
                valueText: Audio.muted ? qsTr("Muted") : qsTr("%1%").arg(Math.round(sliderValue))
                onValueChanged: {
                    if (down)
                        page.setVolume(value);
                }
                onReleased: page.setVolume(value)
            }
            TextSwitch {
                objectName: "muteSwitch"
                text: qsTr("Mute")
                description: qsTr("Alarms, ringtones and notifications keep their own volume")
                automaticCheck: false
                checked: Audio.muted
                onClicked: Audio.setMuted(!Audio.muted)
            }

            SectionHeader {
                text: qsTr("Tones")
            }
            ValueButton {
                objectName: "ringtoneButton"
                visible: Modem.available
                label: qsTr("Ringtone")
                value: Settings.formatSoundName(Settings.ringtone)
                onClicked: page.pickSound("ringtone")
            }
            Slider {
                objectName: "ringtoneVolumeSlider"
                visible: Modem.available
                width: parent.width
                label: qsTr("Ringtone volume")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                value: Logic.percent(Settings.ringtoneVolume)
                valueText: qsTr("%1%").arg(Math.round(sliderValue))
                onReleased: page.setToneVolume("ringtoneVolume", value)
            }
            ValueButton {
                objectName: "notificationSoundButton"
                label: qsTr("Notification sound")
                value: Settings.formatSoundName(Settings.notificationSound)
                onClicked: page.pickSound("notification")
            }
            Slider {
                objectName: "notificationVolumeSlider"
                width: parent.width
                label: qsTr("Notification volume")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                value: Logic.percent(Settings.notificationVolume)
                valueText: qsTr("%1%").arg(Math.round(sliderValue))
                onReleased: page.setToneVolume("notificationVolume", value)
            }
            ValueButton {
                objectName: "alarmSoundButton"
                label: qsTr("Alarm sound")
                value: Settings.formatSoundName(Settings.alarmSound)
                onClicked: page.pickSound("alarm")
            }
            Slider {
                objectName: "alarmVolumeSlider"
                width: parent.width
                label: qsTr("Alarm volume")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                value: Logic.percent(Settings.alarmVolume)
                valueText: qsTr("%1%").arg(Math.round(sliderValue))
                onReleased: page.setToneVolume("alarmVolume", value)
            }

            SectionHeader {
                visible: Haptics.available
                text: qsTr("Feedback")
            }
            TextSwitch {
                objectName: "vibrationSwitch"
                visible: Haptics.available
                text: qsTr("Vibration")
                description: qsTr("Turn off to stop all vibration, including key presses")
                automaticCheck: false
                checked: Settings.vibrationEnabled
                onClicked: Settings.vibrationEnabled = !checked
            }

            Column {
                width: parent.width
                visible: Audio.perAppVolumeSupported

                SectionHeader {
                    text: qsTr("App volume")
                }
                Repeater {
                    id: streams

                    objectName: "streams"
                    model: Audio.streams

                    Item {
                        id: stream

                        required property var model

                        width: column.width
                        height: slider.height

                        Slider {
                            id: slider

                            anchors {
                                left: parent.left
                                right: mute.left
                            }
                            label: stream.model.appName
                            enabled: !stream.model.muted
                            minimumValue: 0
                            maximumValue: 100
                            stepSize: 1
                            value: Logic.percent(stream.model.volume)
                            valueText: stream.model.muted ? qsTr("Muted") : qsTr("%1%").arg(Math.round(sliderValue))
                            onValueChanged: {
                                if (down)
                                    Audio.setStreamVolume(stream.model.streamId, value / 100);
                            }
                            onReleased: Audio.setStreamVolume(stream.model.streamId, value / 100)
                        }
                        IconButton {
                            id: mute

                            objectName: "muteButton"
                            anchors {
                                right: parent.right
                                rightMargin: Theme.horizontalPageMargin
                                verticalCenter: parent.verticalCenter
                            }
                            icon.source: stream.model.muted ? "image://theme/icon-m-speaker-mute" : "image://theme/icon-m-speaker"
                            Accessible.name: stream.model.muted ? qsTr("Unmute %1").arg(stream.model.appName) : qsTr("Mute %1").arg(stream.model.appName)
                            onClicked: Audio.setStreamMuted(stream.model.streamId, !stream.model.muted)
                        }
                    }
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: streams.count === 0
                    text: qsTr("No apps are playing audio")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
