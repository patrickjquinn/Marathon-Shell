import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Item {
    id: statusBar
    height: Constants.statusBarHeight

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: WallpaperStore.isDark ? "#80000000" : "#80FFFFFF"
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
        z: Constants.zIndexBackground
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

    // Center content: Clock OR Lock icon (animated transition)
    Item {
        id: centerContent
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(clockText.implicitWidth, lockIcon.width)
        height: Math.max(clockText.implicitHeight, lockIcon.height)

        // Dynamic position based on setting
        property string position: (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp.statusBarClockPosition) ? SettingsManagerCpp.statusBarClockPosition : "center"

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
                    target: centerContent
                    anchors.leftMargin: leftIconGroup.x + leftIconGroup.width + Constants.spacingLarge
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
                    target: centerContent
                    anchors.rightMargin: rightIconGroup.width + rightIconGroup.anchors.rightMargin + Constants.spacingLarge
                }
            }
        ]

        // Clock text (shown when NOT on lock screen)
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

        // Lock icon (shown when on lock screen, animates on lock state changes)
        Icon {
            id: lockIcon
            anchors.centerIn: parent
            visible: opacity > 0.01
            opacity: SessionStore.isOnLockScreen ? 1 : 0
            // Removed excessive opacity logging - fires constantly during animations
            name: SessionStore.isLocked ? "lock" : "lock-keyhole-open"
            size: Constants.iconSizeSmall  // Match other status bar icons
            color: MColors.text

            // Debug logging
            Component.onCompleted: {
                console.log("[StatusBar] Lock icon initialized - isLocked:", SessionStore.isLocked, "name:", name);
            }
            onNameChanged: {
                console.log("[StatusBar] Lock icon name changed to:", name, "(isLocked:", SessionStore.isLocked, ")");
            }

            // Animated lock state transitions (300ms, bouncy feel)
            scale: SessionStore.isAnimatingLock ? 0.8 : 1.0
            rotation: {
                if (SessionStore.lockTransition === "locking")
                    return 15;
                if (SessionStore.lockTransition === "unlocking")
                    return -15;
                return 0;
            }

            // GPU acceleration for smooth 60fps animations
            layer.enabled: true
            layer.smooth: true

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

            // Property to control whether name behavior is enabled
            property bool enableNameBehavior: true

            // Smooth morph animation when icon name changes
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
                        to: 1.0
                        duration: 150
                        easing.type: Easing.OutBack
                    }
                }
            }

            // Shake animation for invalid PIN
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

            // Unlock animation for valid PIN
            SequentialAnimation {
                id: unlockAnimation
                // Disable automatic name behavior during custom animation
                PropertyAction {
                    target: lockIcon
                    property: "enableNameBehavior"
                    value: false
                }
                ScriptAction {
                    script: console.log("[StatusBar] Unlock animation started!")
                }
                // Pulse scale up
                NumberAnimation {
                    target: lockIcon
                    property: "scale"
                    to: 1.3
                    duration: 200
                    easing.type: Easing.OutCubic
                }
                // Trigger proper unlock (sets grace period, updates state, changes icon)
                ScriptAction {
                    script: {
                        console.log("[StatusBar] Animation calling SessionStore.unlock()...");
                        SessionStore.unlock();
                    }
                }
                // Return to normal scale (icon has changed via SessionStore.unlock)
                NumberAnimation {
                    target: lockIcon
                    property: "scale"
                    to: 1.0
                    duration: 150
                    easing.type: Easing.OutBack
                }
                // Re-enable automatic name behavior
                PropertyAction {
                    target: lockIcon
                    property: "enableNameBehavior"
                    value: true
                }
                ScriptAction {
                    script: console.log("[StatusBar] Unlock animation complete!")
                }
            }

            // Connect to SessionStore signals
            Connections {
                target: SessionStore

                function onTriggerShakeAnimation() {
                    console.log("[StatusBar] Received triggerShakeAnimation signal");
                    shakeAnimation.start();
                }

                function onTriggerUnlockAnimation() {
                    console.log("[StatusBar] Received triggerUnlockAnimation signal");
                    unlockAnimation.start();
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
            visible: StatusBarIconService.shouldShowDND(SystemStatusStore.isDndMode)
            opacity: 0.9
        }

        Icon {
            name: StatusBarIconService.getBluetoothIcon(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: StatusBarIconService.getBluetoothOpacity(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            visible: NetworkManager.bluetoothAvailable && StatusBarIconService.shouldShowBluetooth(SystemStatusStore.isBluetoothOn)
        }

        // Cellular - always show, signal-off (crossed antenna) when unavailable
        Icon {
            name: (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp.modemAvailable) ? StatusBarIconService.getSignalIcon(SystemStatusStore.cellularStrength) : "smartphone"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp.modemAvailable) ? StatusBarIconService.getSignalOpacity(SystemStatusStore.cellularStrength) : 0.3
        }

        // Ethernet - only show when connected
        Icon {
            name: "cable"  // Using cable icon instead of plug-zap to avoid confusion with power
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.ethernetConnected
            opacity: 1.0
        }

        // WiFi - always show, wifi-off when unavailable
        Icon {
            name: NetworkManager.wifiAvailable ? StatusBarIconService.getWifiIcon(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, NetworkManager.wifiConnected) : "wifi-off"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: NetworkManager.wifiAvailable ? StatusBarIconService.getWifiOpacity(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, NetworkManager.wifiConnected) : 0.3
        }
    }
}
