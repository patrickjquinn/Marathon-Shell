pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../components"

Page {
    id: page

    property var app
    readonly property var alarms: typeof Alarms !== "undefined" ? Alarms : null
    property string lastAlarmId: ""

    function wake(reason) {
        page.app.run("Wake: " + reason, () => WakeManager.wake(reason));
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Alarms & wake")
                description: page.app.summary
            }

            SectionHeader {
                text: qsTr("Alarm trigger")
            }
            DetailItem {
                objectName: "alarmCount"
                label: qsTr("Current alarms")
                value: page.alarms ? page.alarms.alarms.length : 0
            }
            Actions {
                TestItem {
                    objectName: "triggerAlarm"
                    text: qsTr("Trigger alarm")
                    onClicked: page.app.run("Trigger alarm", () => {
                        if (typeof page.alarms.triggerAlarmNow === "function") {
                            page.alarms.triggerAlarmNow("Test Alarm");
                            return true;
                        }
                        page.lastAlarmId = page.alarms.createAlarm(page.app.inMinutes(1), "Test Alarm (auto trigger)", [], {});
                        return page.lastAlarmId !== "";
                    })
                }
                TestItem {
                    objectName: "createAlarm"
                    text: qsTr("Create alarm")
                    onClicked: page.app.run("Create alarm", () => !!page.alarms.createAlarm(page.app.inMinutes(1), "Test Alarm (+1 min)", [], {}))
                }
            }

            SectionHeader {
                text: qsTr("Wake manager")
            }
            HintLabel {
                text: qsTr("Test system wake functionality")
            }
            Actions {
                TestItem {
                    objectName: "wakeAlarm"
                    text: qsTr("Wake (alarm)")
                    onClicked: page.wake("alarm")
                }
                TestItem {
                    objectName: "wakeCall"
                    text: qsTr("Wake (call)")
                    onClicked: page.wake("call")
                }
                TestItem {
                    objectName: "wakeNotification"
                    text: qsTr("Wake (notification)")
                    onClicked: page.wake("notification")
                }
                TestItem {
                    objectName: "scheduleWake"
                    text: qsTr("Schedule wake")
                    onClicked: page.app.run("Schedule wake in 1 minute", () => {
                        const t = new Date();
                        t.setMinutes(t.getMinutes() + 1);
                        WakeManager.scheduleWake(t, "test");
                    })
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
