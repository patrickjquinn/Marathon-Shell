import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Sailfish status area: battery left, clock (or lock glyph) centre,
// radios right. No background; small regular-weight text.
Item {
    id: statusBar

    height: Constants.statusBarHeight

    // Ongoing-activity chip; replaces the clock while non-null.
    property Component activityChip: null

    Row {
        id: leftIconGroup

        anchors.left: parent.left
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Silica.Theme.paddingSmall
        z: 1

        GlyphIcon {
            name: StatusBarIconService.getBatteryIcon(SystemStatusStore.batteryLevel, SystemStatusStore.isPluggedIn)
            color: Silica.Theme.primaryColor
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: SystemStatusStore.batteryLevel + "%"
            color: Silica.Theme.primaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeExtraSmall
            font.features: ({
                    "tnum": 1
                })
            renderType: Text.QtRendering
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Loader {
        id: activityChipLoader
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        active: statusBar.activityChip !== null
        sourceComponent: statusBar.activityChip
        z: 2

        opacity: active ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        id: centerContent

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(clockText.implicitWidth, lockIcon.width)
        height: Math.max(clockText.implicitHeight, lockIcon.height)
        opacity: statusBar.activityChip !== null ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }

        Text {
            id: clockText

            anchors.centerIn: parent
            visible: opacity > 0.01
            opacity: SessionStore.isOnLockScreen ? 0 : 1
            text: SystemStatusStore.timeString
            color: Silica.Theme.primaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeSmall
            font.features: ({
                    "tnum": 1
                })
            renderType: Text.QtRendering

            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.quick
                    easing.type: Easing.OutCubic
                }
            }
        }

        GlyphIcon {
            id: lockIcon

            anchors.centerIn: parent
            // Hard visibility gate: an opacity-only gate left a faint
            // glyph behind the clock on the L5 panel.
            visible: SessionStore.isOnLockScreen
            opacity: SessionStore.isOnLockScreen ? 1 : 0
            name: SessionStore.isLocked ? "lock" : "lock-open"
            size: Silica.Theme.iconSizeExtraSmall
            color: Silica.Theme.primaryColor
            scale: SessionStore.isAnimatingLock ? 0.8 : 1
            rotation: {
                if (SessionStore.lockTransition === "locking")
                    return 15;
                if (SessionStore.lockTransition === "unlocking")
                    return -15;
                return 0;
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.quick
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: MMotion.moderate
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on rotation {
                NumberAnimation {
                    duration: MMotion.moderate
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Row {
        id: rightIconGroup

        anchors.right: parent.right
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Silica.Theme.paddingSmall
        z: 1

        GlyphIcon {
            name: "plane"
            color: Silica.Theme.primaryColor
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: StatusBarIconService.shouldShowAirplaneMode(SystemStatusStore.isAirplaneMode)
        }

        GlyphIcon {
            name: "bell-slash"
            color: Silica.Theme.primaryColor
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: StatusBarIconService.shouldShowDnd(SystemStatusStore.isDndMode)
        }

        GlyphIcon {
            name: StatusBarIconService.getBluetoothIcon(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            color: Silica.Theme.primaryColor
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.isBluetoothOn
        }

        GlyphIcon {
            name: StatusBarIconService.getSignalIcon(SystemStatusStore.cellularStrength)
            color: Silica.Theme.primaryColor
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: ModemManagerCpp.modemAvailable
        }

        Text {
            text: SystemStatusStore.dataType
            color: Silica.Theme.primaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeTiny
            anchors.verticalCenter: parent.verticalCenter
            visible: ModemManagerCpp.modemAvailable && SystemStatusStore.dataType !== "" && SystemStatusStore.dataType !== "Unknown"
        }

        GlyphIcon {
            name: "cable"
            color: Silica.Theme.primaryColor
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.ethernetConnected
        }

        GlyphIcon {
            name: StatusBarIconService.getWifiIcon(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, NetworkManagerCpp.wifiConnected)
            color: Silica.Theme.primaryColor
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.isWifiOn
        }
    }
}
