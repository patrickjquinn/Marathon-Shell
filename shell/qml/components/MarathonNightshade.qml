pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import "../core/Weather.js" as Weather

// Nightshade: on the charger within its hours, the idle timer leaves a dim
// bedside clock up instead of turning the screen off. Static but for one
// redraw a minute, when the clock turns and the face drifts against burn-in.
Item {
    id: root

    readonly property bool active: Display.nightshade
    // Minutes since the epoch: each one a step of the drift.
    property int step: 0
    readonly property var items: SettingsManagerCpp.nightshadeItems || []
    readonly property color tint: MColors.nightshadeTints[SettingsManagerCpp.nightshadeTint] || MColors.nightshadeTints.red
    readonly property real drift: Math.round(Silica.Theme.paddingLarge * 2)
    readonly property var path: [[0, 0], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
    readonly property point offset: Qt.point(path[step % path.length][0] * drift, path[step % path.length][1] * drift)

    function due() {
        const now = new Date();
        return SettingsManagerCpp.nightshadeDue(Power.isPluggedIn, Power.hasActiveCalls, now.getHours() * 60 + now.getMinutes());
    }

    // The idle timers' blank: Nightshade when due, else the screen goes off.
    function idle(reason) {
        if (!due()) {
            Display.turnScreenOff(reason);
            return;
        }
        Logger.info("Nightshade", "Shown in place of " + reason);
        step = Math.floor(Date.now() / 60000);
        SessionStore.showLock();
        Display.nightshade = true;
    }

    // Back to the lock screen; with a reason, the screen goes off as well.
    function leave(reason) {
        if (!active)
            return;
        if (reason)
            Display.turnScreenOff(reason);
        Display.nightshade = false;
    }

    function tick() {
        step = Math.floor(Date.now() / 60000);
        if (!due())
            leave("Nightshade's hours are over");
    }

    visible: active

    Connections {
        function onIsPluggedInChanged() {
            if (!Power.isPluggedIn)
                root.leave("Nightshade unplugged");
        }
        function onHasActiveCallsChanged() {
            if (Power.hasActiveCalls)
                root.leave("");
        }

        enabled: root.active
        target: Power
    }

    Connections {
        function onHasActiveAlarmChanged() {
            if (AlarmManagerCpp.hasActiveAlarm)
                root.leave("");
        }

        enabled: root.active
        target: AlarmManagerCpp
    }

    Connections {
        function onCurrentTimeChanged() {
            root.tick();
        }

        enabled: root.active
        target: SystemStatusStore
    }

    // Off by any other way, the panel comes back as the lock screen.
    Connections {
        function onScreenOnChanged() {
            if (!Display.screenOn)
                Display.nightshade = false;
        }

        target: Display
    }

    Loader {
        anchors.fill: parent
        active: root.active
        sourceComponent: face
    }

    Component {
        id: face

        Rectangle {
            color: MColors.nightshadeBackground

            MouseArea {
                anchors.fill: parent
                Accessible.role: Accessible.Button
                //: Tapping the bedside clock brings back the lock screen
                Accessible.name: qsTr("Show the lock screen")
                Accessible.onPressAction: root.leave("")
                onClicked: root.leave("")
            }

            Column {
                id: content

                objectName: "nightshadeFace"
                x: Math.round((parent.width - width) / 2 + root.offset.x)
                y: Math.round((parent.height - height) / 2 + root.offset.y)
                spacing: Silica.Theme.paddingMedium

                Behavior on x {
                    enabled: !MMotion.reduceMotion
                    NumberAnimation {
                        duration: MMotion.durationFor("panel")
                        easing.type: MMotion.easingFor("panel")
                    }
                }
                Behavior on y {
                    enabled: !MMotion.reduceMotion
                    NumberAnimation {
                        duration: MMotion.durationFor("panel")
                        easing.type: MMotion.easingFor("panel")
                    }
                }

                Silica.Label {
                    objectName: "nightshadeClock"
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.items.indexOf("clock") >= 0
                    text: SystemStatusStore.timeString
                    color: root.tint
                    font.pixelSize: Math.round(Silica.Theme.fontSizeHuge * 1.9)
                    font.weight: Font.ExtraLight
                    font.features: ({
                            "tnum": 1
                        })
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Silica.Theme.paddingLarge
                    opacity: 0.7

                    Row {
                        objectName: "nightshadeBattery"
                        visible: root.items.indexOf("battery") >= 0
                        spacing: Silica.Theme.paddingSmall

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: Power.isCharging ? "battery-charging" : "battery-full"
                            size: Silica.Theme.iconSizeSmall
                            color: root.tint
                        }
                        Silica.Label {
                            anchors.verticalCenter: parent.verticalCenter
                            //: Battery charge on the bedside clock, e.g. 82%
                            text: qsTr("%1%").arg(Power.batteryLevel)
                            color: root.tint
                            font.pixelSize: Silica.Theme.fontSizeMedium
                        }
                    }

                    Row {
                        id: weather

                        readonly property var current: WeatherClient.forecast.current || null

                        objectName: "nightshadeWeather"
                        visible: root.items.indexOf("weather") >= 0 && current !== null
                        spacing: Silica.Theme.paddingSmall

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: weather.current ? Weather.glyph(weather.current.symbol, ((WeatherClient.forecast.hourly || [])[0] || {}).is_day) : ""
                            size: Silica.Theme.iconSizeSmall
                            color: root.tint
                        }
                        Silica.Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: weather.current ? Weather.temperature(weather.current.temperature, SettingsManagerCpp.fahrenheit) : ""
                            color: root.tint
                            font.pixelSize: Silica.Theme.fontSizeMedium
                        }
                    }

                    // A count only: what they say stays behind the lock.
                    Row {
                        objectName: "nightshadeNotifications"
                        visible: root.items.indexOf("notifications") >= 0 && NotificationService.unreadCount > 0 && SettingsManagerCpp.showNotificationsOnLockScreen
                        spacing: Silica.Theme.paddingSmall

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "bell"
                            size: Silica.Theme.iconSizeSmall
                            color: root.tint
                        }
                        Silica.Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: NotificationService.unreadCount
                            color: root.tint
                            font.pixelSize: Silica.Theme.fontSizeMedium
                        }
                    }
                }
            }
        }
    }
}
