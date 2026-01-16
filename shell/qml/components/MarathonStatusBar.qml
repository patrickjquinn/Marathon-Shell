import MarathonUI.Core
import MarathonUI.Theme
import MarathonOS.Shell 1.0
import QtQuick

Item {
    id: statusBar

    height: Constants.statusBarHeight

    Rectangle {
        anchors.fill: parent
        z: Constants.zIndexBackground

        gradient: Gradient {
            GradientStop {
                position: 0
                color: WallpaperStore.isDark ? "#80000000" : "#80FFFFFF"
            }

            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }

    Row {
        id: leftIconGroup

        anchors.left: parent.left
        anchors.leftMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingSmall
        z: 1

        Icon {
            name: StatusBarIconService.getBatteryIcon(SystemStatusStore.batteryLevel, SystemStatusStore.isPluggedIn)
            color: StatusBarIconService.getBatteryColor(SystemStatusStore.batteryLevel, SystemStatusStore.isPluggedIn)
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: SystemStatusStore.batteryLevel + "%"
            color: StatusBarIconService.getBatteryColor(SystemStatusStore.batteryLevel, SystemStatusStore.isPluggedIn)
            font.pixelSize: Constants.fontSizeSmall
            font.family: MTypography.fontFamily
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Item {
        id: centerContent

        property string position: (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp.statusBarClockPosition) ? SettingsManagerCpp.statusBarClockPosition : "center"

        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(clockText.implicitWidth, lockIcon.width)
        height: Math.max(clockText.implicitHeight, lockIcon.height)
        states: [
            State {
                name: "left"
                when: centerContent.position === "left"

                AnchorChanges {
                    target: centerContent
                    anchors.horizontalCenter: undefined
                    anchors.left: parent.left
                    anchors.right: undefined
                }

                PropertyChanges {
                    centerContent.anchors.leftMargin: leftIconGroup.x + leftIconGroup.width + Constants.spacingLarge
                }
            },
            State {
                name: "center"
                when: centerContent.position === "center" || !centerContent.position

                AnchorChanges {
                    target: centerContent
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.left: undefined
                    anchors.right: undefined
                }
            },
            State {
                name: "right"
                when: centerContent.position === "right"

                AnchorChanges {
                    target: centerContent
                    anchors.horizontalCenter: undefined
                    anchors.left: undefined
                    anchors.right: parent.right
                }

                PropertyChanges {
                    centerContent.anchors.rightMargin: rightIconGroup.width + rightIconGroup.anchors.rightMargin + Constants.spacingLarge
                }
            }
        ]

        Text {
            id: clockText

            anchors.centerIn: parent
            visible: opacity > 0.01
            opacity: SessionStore.isOnLockScreen ? 0 : 1
            text: SystemStatusStore.timeString
            color: MColors.text
            font.pixelSize: Constants.fontSizeMedium
            font.weight: Font.Medium

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }

        Icon {
            id: lockIcon

            property bool enableNameBehavior: true

            anchors.centerIn: parent
            visible: opacity > 0.01
            opacity: SessionStore.isOnLockScreen ? 1 : 0
            name: SessionStore.isLocked ? "lock" : "lock-keyhole-open"
            size: Constants.iconSizeSmall
            color: MColors.text
            Component.onCompleted: {
                console.log("[StatusBar] Lock icon initialized - isLocked:", SessionStore.isLocked, "name:", name);
            }
            onNameChanged: {
                console.log("[StatusBar] Lock icon name changed to:", name, "(isLocked:", SessionStore.isLocked, ")");
            }
            scale: SessionStore.isAnimatingLock ? 0.8 : 1
            rotation: {
                if (SessionStore.lockTransition === "locking")
                    return 15;

                if (SessionStore.lockTransition === "unlocking")
                    return -15;

                return 0;
            }
            layer.enabled: true
            layer.smooth: true

            SequentialAnimation {
                id: shakeAnimation

                NumberAnimation {
                    target: lockIcon
                    property: "x"
                    to: 6
                    duration: 40
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: lockIcon
                    property: "x"
                    to: -6
                    duration: 40
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: lockIcon
                    property: "x"
                    to: 4
                    duration: 40
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: lockIcon
                    property: "x"
                    to: -4
                    duration: 40
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: lockIcon
                    property: "x"
                    to: 2
                    duration: 40
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: lockIcon
                    property: "x"
                    to: -2
                    duration: 40
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: lockIcon
                    property: "x"
                    to: 0
                    duration: 40
                    easing.type: Easing.OutCubic
                }
            }

            SequentialAnimation {
                id: unlockAnimation

                PropertyAction {
                    target: lockIcon
                    property: "enableNameBehavior"
                    value: false
                }

                ScriptAction {
                    script: console.log("[StatusBar] Unlock animation started!")
                }

                NumberAnimation {
                    target: lockIcon
                    property: "scale"
                    to: 1.3
                    duration: 200
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: lockIcon
                    property: "scale"
                    to: 1
                    duration: 150
                    easing.type: Easing.OutBack
                }

                PropertyAction {
                    target: lockIcon
                    property: "enableNameBehavior"
                    value: true
                }

                ScriptAction {
                    script: console.log("[StatusBar] Unlock animation complete!")
                }
            }

            Connections {
                function onTriggerShakeAnimation() {
                    console.log("[StatusBar] Received triggerShakeAnimation signal");
                    shakeAnimation.start();
                }

                function onTriggerUnlockAnimation() {
                    console.log("[StatusBar] Received triggerUnlockAnimation signal");
                    unlockAnimation.start();
                }

                target: SessionStore
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on rotation {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutBack
                }
            }

            Behavior on name {
                enabled: lockIcon.enableNameBehavior

                SequentialAnimation {
                    NumberAnimation {
                        target: lockIcon
                        property: "scale"
                        to: 0.8
                        duration: 150
                        easing.type: Easing.InCubic
                    }

                    PropertyAction {
                        target: lockIcon
                        property: "name"
                    }

                    NumberAnimation {
                        target: lockIcon
                        property: "scale"
                        to: 1
                        duration: 150
                        easing.type: Easing.OutBack
                    }
                }
            }
        }
    }

    Row {
        id: rightIconGroup

        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingMedium
        z: 1

        Icon {
            name: "plane"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: StatusBarIconService.shouldShowAirplaneMode(SystemStatusStore.isAirplaneMode)
        }

        Icon {
            name: "bell"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: StatusBarIconService.shouldShowDnd(SystemStatusStore.isDndMode)
            opacity: 0.9
        }

        Icon {
            name: StatusBarIconService.getBluetoothIcon(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: StatusBarIconService.getBluetoothOpacity(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            visible: (typeof BluetoothManagerCpp !== "undefined" && BluetoothManagerCpp ? BluetoothManagerCpp.available : false) && StatusBarIconService.shouldShowBluetooth(SystemStatusStore.isBluetoothOn)
        }

        Icon {
            name: (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp.modemAvailable) ? StatusBarIconService.getSignalIcon(SystemStatusStore.cellularStrength) : "smartphone"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp.modemAvailable) ? StatusBarIconService.getSignalOpacity(SystemStatusStore.cellularStrength) : 0.3
        }

        Icon {
            name: "cable"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.ethernetConnected
            opacity: 1
        }

        Icon {
            name: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.wifiAvailable : false) ? StatusBarIconService.getWifiIcon(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.wifiConnected : false) : "wifi-off"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.wifiAvailable : false) ? StatusBarIconService.getWifiOpacity(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.wifiConnected : false) : 0.3
        }
    }
}
