pragma ComponentBehavior: Bound
import MarathonApp.Clock
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick

Item {
    id: alarmPage

    required property var app
    property var lastDeleted: null
    readonly property int backLayers: alarmEditorDialog.showing ? 1 : 0

    function handleBack() {
        alarmEditorDialog.close();
    }

    function hourOf(timeStr) {
        return timeStr ? parseInt(timeStr.split(":")[0]) : 0;
    }

    function minuteOf(timeStr) {
        return timeStr ? parseInt(timeStr.split(":")[1]) : 0;
    }

    function reportFailure(ok, message) {
        if (!ok)
            snackbar.show(message, "");
    }

    MTopBar {
        id: topBar
        width: parent.width
        title: "Alarms"
    }

    ListView {
        id: alarmsList

        anchors.fill: parent
        anchors.topMargin: topBar.height + MSpacing.md
        clip: true
        model: alarmPage.app.alarms
        spacing: 0
        bottomMargin: fab.height + MSpacing.lg * 2

        delegate: AlarmItem {
            required property var modelData

            width: alarmsList.width
            alarmId: modelData.id
            alarmHour: alarmPage.hourOf(modelData.time)
            alarmMinute: alarmPage.minuteOf(modelData.time)
            alarmLabel: modelData.label || "Alarm"
            alarmEnabled: modelData.enabled
            alarmRepeat: modelData.repeat || []
            onClicked: alarmEditorDialog.openForEdit(alarmId, alarmHour, alarmMinute, alarmLabel, alarmRepeat)
            onToggled: alarmPage.app.toggleAlarm(alarmId)
        }
    }

    MEmptyState {
        anchors.centerIn: parent
        width: parent.width - MSpacing.xl * 2
        visible: alarmsList.count === 0
        iconName: "alarm"
        iconSize: 64
        title: "No alarms set"
        message: "Tap New alarm to create one."
    }

    MFloatingActionButton {
        id: fab

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.lg
        label: "New alarm"
        onClicked: alarmEditorDialog.open()
    }

    MSnackbar {
        id: snackbar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: fab.top
        anchors.margins: MSpacing.md
        onActionTriggered: alarmPage.reportFailure(alarmPage.app.restoreAlarm(alarmPage.lastDeleted), "Couldn't restore the alarm. Create it again with New alarm.")
    }

    AlarmEditorDialog {
        id: alarmEditorDialog

        onAlarmCreated: function (hour, minute, label, repeat) {
            alarmPage.reportFailure(alarmPage.app.createAlarm(hour, minute, label, repeat), "Couldn't save the alarm. Try again.");
        }
        onAlarmUpdated: function (alarmId, hour, minute, label, repeat) {
            alarmPage.reportFailure(alarmPage.app.updateAlarm(alarmId, hour, minute, label, repeat), "Couldn't save the alarm. Try again.");
        }
        onAlarmDeleted: function (alarmId) {
            const alarm = alarmPage.app._getAlarmById(alarmId);
            if (!alarmPage.app.deleteAlarm(alarmId)) {
                snackbar.show("Couldn't delete the alarm. Try again.", "");
                return;
            }
            alarmPage.lastDeleted = alarm;
            snackbar.show("Alarm deleted", "Undo");
        }
    }
}
