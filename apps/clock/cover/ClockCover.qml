import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic
import "../models"

CoverBackground {
    id: root

    property var alarms: []
    required property Stopwatch stopwatch
    required property CountdownTimer countdown
    property date now: new Date()
    readonly property var next: Logic.nextAlarm(alarms, now)
    readonly property string mode: countdown.running ? "timer" : stopwatch.running ? "stopwatch" : countdown.remaining > 0 ? "timer" : next ? "alarm" : "idle"

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
        visible: root.mode === "idle"
        text: qsTr("No alarms")
        icon.source: "image://theme/icon-l-alarm"
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        visible: root.mode !== "idle"
        spacing: Theme.paddingSmall

        CoverHeadline {
            objectName: "coverHeadline"
            width: parent.width
            value: root.mode === "timer" ? Logic.formatCountdown(root.countdown.remaining) : root.mode === "stopwatch" ? Logic.formatCountdown(Math.floor(root.stopwatch.elapsed / 1000)) : root.next ? Format.formatDate(root.next.when, Formatter.TimeValue) : ""
            valueColor: root.mode === "timer" && !root.countdown.running ? Theme.secondaryHighlightColor : Theme.highlightColor
            label: root.mode === "timer" ? qsTr("Timer") : root.mode === "stopwatch" ? qsTr("Stopwatch") : root.next ? root.next.alarm.label || qsTr("Alarm") : ""
        }
        Label {
            objectName: "coverDetail"
            width: parent.width
            visible: text !== ""
            text: root.mode === "alarm" && root.next ? root.dayText(root.next.when) : root.mode === "timer" && !root.countdown.running ? qsTr("Paused") : ""
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
        }
    }

    CoverActionList {
        enabled: root.mode === "timer"

        CoverAction {
            objectName: "toggleTimer"
            iconSource: root.countdown.running ? "image://theme/icon-cover-pause" : "image://theme/icon-cover-play"
            onTriggered: root.countdown.running ? root.countdown.pause() : root.countdown.start()
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
