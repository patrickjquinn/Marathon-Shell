import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · status bar (28 px glass).
//
// Layout:
//   • Left  — battery icon + percentage (tabular nums)
//   • Centre — time (most screens) OR lock icon (when on lock screen)
//   • Right — DnD · Bluetooth · cellular · ethernet · wifi
//
// Background: glassTitlebar (rgba 13,13,14, 0.72). Border-bottom is the
// hairline borderGlass rgba(1,1,1,0.06). Real backdrop blur arrives
// when GlassBg lands; for now the translucent fill gives the right
// composition over the wallpaper.
//
// Tabular numerics on the battery % and time so the digits don't dance
// during minute ticks.
Item {
    id: statusBar

    height: Constants.statusBarHeight

    Rectangle {
        anchors.fill: parent
        color: MColors.glassTitlebar
        z: Constants.zIndexBackground
    }

    // Hairline bottom border per DS spec.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: MColors.borderGlass
        z: Constants.zIndexBackground + 1
    }

    Row {
        id: leftIconGroup

        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        z: 1

        Icon {
            name: StatusBarIconService.getBatteryIcon(SystemStatusStore.batteryLevel, SystemStatusStore.isPluggedIn)
            color: StatusBarIconService.getBatteryColor(SystemStatusStore.batteryLevel, SystemStatusStore.isPluggedIn)
            size: Math.round(14 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: SystemStatusStore.batteryLevel + "%"
            color: StatusBarIconService.getBatteryColor(SystemStatusStore.batteryLevel, SystemStatusStore.isPluggedIn)
            font.family: MTypography.fontFamilyMedium
            font.pixelSize: MTypography.sizeCaption
            font.weight: MTypography.weightMedium
            font.letterSpacing: trackingForCaption
            font.features: ({
                    "tnum": 1
                })
            // QtRendering uses the FontLoader-registered Sora directly.
            // NativeRendering went through fontconfig and silently fell
            // back to Noto Sans on devices without a system-wide Sora
            // in the fontconfig cache.
            renderType: Text.QtRendering
            anchors.verticalCenter: parent.verticalCenter

            readonly property real trackingForCaption: MTypography.trackingCaption
        }
    }

    Item {
        id: centerContent

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(clockText.implicitWidth, lockIcon.width)
        height: Math.max(clockText.implicitHeight, lockIcon.height)

        Text {
            id: clockText

            anchors.centerIn: parent
            visible: opacity > 0.01
            opacity: SessionStore.isOnLockScreen ? 0 : 1
            text: SystemStatusStore.timeString
            color: MColors.textPrimary
            font.family: MTypography.fontFamilyRegular
            font.pixelSize: MTypography.sizeCaption
            font.weight: MTypography.weightRegular
            font.features: ({
                    "tnum": 1
                })
            // Text.QtRendering uses the FontLoader-registered Sora.
            // NativeRendering bypassed the loader and went through
            // fontconfig, which silently fell back to Noto Sans when
            // the system-wide Sora.ttf wasn't in the fontconfig cache.
            renderType: Text.QtRendering

            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.quick
                    easing.type: Easing.OutCubic
                }
            }
        }

        Icon {
            id: lockIcon

            anchors.centerIn: parent
            // Hard gate on isOnLockScreen rather than opacity > 0.01 so
            // the Icon node leaves the scene graph entirely off the lock
            // screen. With the opacity-only gate, the lock glyph stayed
            // resident as a faint dark silhouette behind the clock
            // during pixel-precise font hinting on the L5 panel —
            // visible as a "mask behind the colon" when an app was
            // foregrounded. The clock's fade-in still animates via the
            // clockText opacity Behavior, so the transition reads the
            // same; the icon just isn't there to draw against.
            visible: SessionStore.isOnLockScreen
            opacity: SessionStore.isOnLockScreen ? 1 : 0
            name: SessionStore.isLocked ? "lock" : "lock-open"
            size: Math.round(14 * Constants.scaleFactor)
            color: MColors.textPrimary
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
                    easing.type: Easing.OutBack
                }
            }
        }
    }

    Row {
        id: rightIconGroup

        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        z: 1

        Icon {
            name: "plane"
            color: MColors.textPrimary
            size: Math.round(14 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            visible: StatusBarIconService.shouldShowAirplaneMode(SystemStatusStore.isAirplaneMode)
        }

        Icon {
            name: "bell"
            color: MColors.textPrimary
            size: Math.round(14 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            visible: StatusBarIconService.shouldShowDnd(SystemStatusStore.isDndMode)
            opacity: 0.9
        }

        Icon {
            // Always show — every Marathon target ships with Bluetooth and
            // Wi-Fi radios, and gating visibility on the C++ manager's
            // `available` flag means the icon disappears entirely on images
            // where bluez/NetworkManager fail to spin up at boot (a system
            // config problem the user can't tell apart from "Marathon is
            // broken"). Opacity already conveys on/off/connected state.
            name: StatusBarIconService.getBluetoothIcon(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            color: MColors.textPrimary
            size: Math.round(14 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            opacity: StatusBarIconService.getBluetoothOpacity(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            visible: true
        }

        // Hide the radio icons when their radio is absent (iOS/Android
        // convention). A no-modem "smartphone" silhouette next to the
        // bluetooth glyph reads as visual noise — and at 14 px it's
        // easily mis-parsed as another battery indicator.
        Icon {
            name: StatusBarIconService.getSignalIcon(SystemStatusStore.cellularStrength)
            color: MColors.textPrimary
            size: Math.round(14 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            visible: ModemManagerCpp.modemAvailable
            opacity: StatusBarIconService.getSignalOpacity(SystemStatusStore.cellularStrength)
        }

        // Network-tech label (5G/LTE/4G/3G/E/G). iOS- and Android-style, sits
        // immediately right of the signal bars. Hidden when the modem isn't
        // available or hasn't reported a tech yet ("Unknown").
        Text {
            text: SystemStatusStore.dataType
            color: MColors.textPrimary
            font.family: MTypography.fontFamily
            font.pixelSize: Math.round(10 * Constants.scaleFactor)
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
            visible: ModemManagerCpp.modemAvailable && SystemStatusStore.dataType !== "" && SystemStatusStore.dataType !== "Unknown"
            opacity: StatusBarIconService.getSignalOpacity(SystemStatusStore.cellularStrength)
        }

        Icon {
            name: "cable"
            color: MColors.textPrimary
            size: Math.round(14 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.ethernetConnected
            opacity: 1
        }

        Icon {
            // Same rationale as the Bluetooth glyph above — always visible,
            // opacity reflects on/off/strength. NetworkManager not being
            // running shouldn't make the Wi-Fi indicator disappear.
            name: StatusBarIconService.getWifiIcon(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, NetworkManagerCpp.wifiConnected)
            color: MColors.textPrimary
            size: Math.round(14 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            visible: true
            opacity: StatusBarIconService.getWifiOpacity(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, NetworkManagerCpp.wifiConnected)
        }
    }
}
