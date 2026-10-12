pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../components"

Page {
    id: page

    property var app
    readonly property var audio: typeof Audio !== "undefined" ? Audio : null

    function profile(name) {
        page.app.run("Audio profile: " + name, () => page.audio.setAudioProfile(name));
    }

    function haptic(strength) {
        page.app.run("Haptic: " + strength, () => page.app.haptic(strength));
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Media & audio")
                description: page.app.summary
            }

            SectionHeader {
                text: qsTr("Audio manager")
            }
            DetailItem {
                objectName: "volume"
                label: qsTr("Volume")
                value: (page.audio ? Math.round(page.audio.volume * 100) : 0) + "%"
            }
            Actions {
                TestItem {
                    objectName: "playRingtone"
                    text: qsTr("Play ringtone")
                    onClicked: page.app.run("Play ringtone", () => page.audio.playRingtone())
                }
                TestItem {
                    objectName: "stopRingtone"
                    text: qsTr("Stop ringtone")
                    onClicked: page.app.run("Stop ringtone", () => page.audio.stopRingtone())
                }
                TestItem {
                    objectName: "notificationSound"
                    text: qsTr("Notification sound")
                    onClicked: page.app.run("Notification sound", () => page.audio.playNotificationSound())
                }
                TestItem {
                    objectName: "alarmSound"
                    text: qsTr("Alarm sound")
                    onClicked: page.app.run("Alarm sound", () => page.audio.playAlarmSound())
                }
                TestItem {
                    objectName: "stopAlarm"
                    text: qsTr("Stop alarm")
                    onClicked: page.app.run("Stop alarm sound", () => page.audio.stopAlarmSound())
                }
            }

            SectionHeader {
                text: qsTr("Audio profiles")
            }
            DetailItem {
                objectName: "profile"
                label: qsTr("Current")
                value: page.audio && page.audio.audioProfile ? page.audio.audioProfile : qsTr("unknown")
            }
            Actions {
                TestItem {
                    objectName: "profileSilent"
                    text: qsTr("Silent")
                    onClicked: page.profile("silent")
                }
                TestItem {
                    objectName: "profileVibrate"
                    text: qsTr("Vibrate")
                    onClicked: page.profile("vibrate")
                }
                TestItem {
                    objectName: "profileNormal"
                    text: qsTr("Normal")
                    onClicked: page.profile("normal")
                }
                TestItem {
                    objectName: "profileLoud"
                    text: qsTr("Loud")
                    onClicked: page.profile("loud")
                }
            }

            SectionHeader {
                text: qsTr("Haptic feedback")
            }
            Actions {
                TestItem {
                    objectName: "hapticLight"
                    text: qsTr("Light")
                    onClicked: page.haptic("light")
                }
                TestItem {
                    objectName: "hapticMedium"
                    text: qsTr("Medium")
                    onClicked: page.haptic("medium")
                }
                TestItem {
                    objectName: "hapticHeavy"
                    text: qsTr("Heavy")
                    onClicked: page.haptic("heavy")
                }
                TestItem {
                    objectName: "hapticPattern"
                    text: qsTr("Pattern")
                    onClicked: page.app.run("Haptic: pattern", () => page.audio.vibratePattern([100, 50, 100, 50, 200]))
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
