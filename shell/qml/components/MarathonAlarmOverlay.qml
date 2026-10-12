import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: alarmOverlay

    property var currentAlarm: null
    readonly property var settings: {
        const id = currentAlarm ? currentAlarm.id : "";
        return AlarmManagerCpp.activeAlarms.find(a => a.id === id) || {};
    }
    readonly property bool canSnooze: settings.snoozeEnabled !== false
    readonly property int snoozeMinutes: settings.snoozeDuration || 10

    function show(alarm) {
        currentAlarm = alarm;
        visible = true;
    }

    function dismiss() {
        if (currentAlarm) {
            AlarmManagerCpp.dismissAlarm(currentAlarm.id);
            currentAlarm = null;
        }
        visible = false;
    }

    function snooze() {
        if (currentAlarm) {
            AlarmManagerCpp.snoozeAlarm(currentAlarm.id);
            currentAlarm = null;
        }
        visible = false;
    }

    anchors.fill: parent
    visible: false
    z: 10000

    // A ring with its label beneath, as the power menu's choices.
    component AlarmAction: Column {
        id: action

        property string iconName
        property string label
        property bool emphasised: false
        property bool holdToActivate: false

        signal activated

        spacing: Silica.Theme.paddingMedium

        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()

        MCircularIconButton {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Silica.Theme.itemSizeLarge
            height: width
            iconName: action.iconName
            iconSize: Silica.Theme.iconSizeMedium
            variant: action.emphasised || holdArea.pressed ? "primary" : "secondary"
            a11yName: action.label
            onClicked: action.activated()

            MouseArea {
                id: holdArea

                anchors.fill: parent
                enabled: action.holdToActivate
                onPressAndHold: action.activated()
            }
        }

        Silica.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: action.label
            font.pixelSize: Silica.Theme.fontSizeSmall
            color: action.emphasised ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
        }
    }

    KeelAmbienceBackground {
        anchors.fill: parent
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
    }

    MouseArea {
        anchors.fill: parent
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Silica.Theme.horizontalPageMargin
        spacing: Silica.Theme.paddingLarge

        GlyphIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "bell"
            size: Silica.Theme.iconSizeLarge
            color: Silica.Theme.highlightColor
        }

        Silica.Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: SystemStatusStore.timeString
            color: Silica.Theme.primaryColor
            font.family: Silica.Theme.fontFamilyHeading
            font.pixelSize: Silica.Theme.fontSizeHuge
            font.weight: Font.Light
        }

        Silica.Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: alarmOverlay.currentAlarm ? alarmOverlay.currentAlarm.label : "Alarm"
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeLarge
            truncationMode: Silica.TruncationMode.Fade
        }

        Item {
            width: parent.width
            height: Silica.Theme.paddingLarge
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Silica.Theme.itemSizeMedium

            AlarmAction {
                objectName: "dismissAction"
                iconName: "x"
                label: qsTr("Dismiss")
                holdToActivate: true
                onActivated: {
                    HapticManager.medium();
                    alarmOverlay.dismiss();
                }
            }

            AlarmAction {
                objectName: "snoozeAction"
                visible: alarmOverlay.canSnooze
                iconName: "clock"
                label: qsTr("Snooze %n min", "", alarmOverlay.snoozeMinutes)
                emphasised: true
                onActivated: {
                    HapticManager.medium();
                    alarmOverlay.snooze();
                }
            }
        }

        Silica.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Hold Dismiss to stop the alarm")
            color: Silica.Theme.secondaryColor
            font.pixelSize: Silica.Theme.fontSizeExtraSmall
        }
    }
}
