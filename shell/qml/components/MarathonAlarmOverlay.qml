import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: alarmOverlay

    property var currentAlarm: null

    function show(alarm) {
        currentAlarm = alarm;
        visible = true;
        swipeUpText.opacity = 1;
        if (!MMotion.reduceMotion)
            swipeAnimation.start();
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
            variant: action.emphasised ? "primary" : "secondary"
            a11yName: action.label
            onClicked: action.activated()
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
        property real startY: 0
        property bool dragging: false

        anchors.fill: parent
        preventStealing: true
        onPressed: mouse => {
            startY = mouse.y;
            dragging = false;
        }
        onPositionChanged: mouse => {
            if (Math.abs(mouse.y - startY) > 20)
                dragging = true;

            if (dragging) {
                var delta = mouse.y - startY;
                if (delta < -100)
                    alarmOverlay.dismiss();
            }
        }
        onReleased: {
            dragging = false;
        }
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
            text: Qt.formatTime(new Date(), "hh:mm")
            color: Silica.Theme.primaryColor
            font.family: Silica.Theme.fontFamilyHeading
            font.pixelSize: Silica.Theme.fontSizeHuge * 1.5
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
                iconName: "clock"
                label: "Snooze"
                onActivated: {
                    HapticManager.medium();
                    alarmOverlay.snooze();
                }
            }

            AlarmAction {
                iconName: "x"
                label: "Dismiss"
                emphasised: true
                onActivated: {
                    HapticManager.medium();
                    alarmOverlay.dismiss();
                }
            }
        }

        Item {
            width: parent.width
            height: Silica.Theme.paddingLarge
        }

        Silica.Label {
            id: swipeUpText

            anchors.horizontalCenter: parent.horizontalCenter
            text: "↑ Swipe up to dismiss"
            color: Silica.Theme.secondaryColor
            font.pixelSize: Silica.Theme.fontSizeExtraSmall

            SequentialAnimation {
                id: swipeAnimation

                loops: Animation.Infinite

                NumberAnimation {
                    target: swipeUpText
                    property: "opacity"
                    from: 1
                    to: 0.3
                    duration: 1500
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    target: swipeUpText
                    property: "opacity"
                    from: 0.3
                    to: 1
                    duration: 1500
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    Timer {
        id: updateTimeTimer

        interval: 1000
        repeat: true
        running: alarmOverlay.visible
        onTriggered: {
            alarmOverlay.currentAlarmChanged();
        }
    }

    Connections {
        function onAlarmTriggered(id, label) {
            alarmOverlay.show({
                "id": id,
                "label": label
            });
        }

        target: AlarmManagerCpp
    }
}
