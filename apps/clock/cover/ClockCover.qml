import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic

CoverBackground {
    id: root

    property var alarms: []
    required property QtObject stopwatch
    required property QtObject countdown
    property date now: new Date()
    readonly property var next: Logic.nextAlarm(alarms, now)
    readonly property string mode: countdown.running ? "timer" : stopwatch.running ? "stopwatch" : next ? "alarm" : "idle"

    signal newAlarmRequested

    function dayText(when) {
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const days = Math.round((new Date(when.getFullYear(), when.getMonth(), when.getDate()) - today) / 86400000);
        if (days === 0)
            return qsTr("Today");
        if (days === 1)
            return qsTr("Tomorrow");
        return Qt.locale().dayName(when.getDay());
    }

    Timer {
        interval: root.mode === "stopwatch" ? 1000 : 30000
        repeat: true
        triggeredOnStart: true
        running: root.status === Cover.Active
        onTriggered: {
            root.now = new Date();
            root.stopwatch.update();
        }
    }

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        enabled: root.mode === "idle"
        text: qsTr("No alarms")
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        visible: root.mode !== "idle"

        Label {
            objectName: "coverTitle"
            width: parent.width
            text: root.mode === "timer" ? Logic.formatCountdown(root.countdown.remaining)
                : root.mode === "stopwatch" ? Logic.formatCountdown(Math.floor(root.stopwatch.elapsed / 1000))
                : root.next ? Format.formatDate(root.next.when, Formatter.TimeValue) : ""
            font.pixelSize: Theme.fontSizeHuge
            font.features: ({ "tnum": 1 })
            fontSizeMode: Text.HorizontalFit
        }
        Label {
            objectName: "coverSubtitle"
            width: parent.width
            text: root.mode === "timer" ? qsTr("Timer")
                : root.mode === "stopwatch" ? qsTr("Stopwatch")
                : root.next ? root.next.alarm.label || qsTr("Alarm") : ""
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
        }
        Label {
            width: parent.width
            visible: root.mode === "alarm"
            text: root.next ? root.dayText(root.next.when) : ""
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.secondaryColor
        }
    }

    CoverActionList {
        enabled: root.mode === "timer"

        CoverAction {
            objectName: "pauseTimer"
            iconSource: "image://theme/icon-cover-pause"
            onTriggered: root.countdown.pause()
        }
    }
    CoverActionList {
        enabled: root.mode === "stopwatch"

        CoverAction {
            objectName: "stopStopwatch"
            iconSource: "image://theme/icon-cover-pause"
            onTriggered: root.stopwatch.stop()
        }
    }
    CoverActionList {
        enabled: root.mode === "alarm" || root.mode === "idle"

        CoverAction {
            objectName: "newAlarmAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: root.newAlarmRequested()
        }
    }
}
