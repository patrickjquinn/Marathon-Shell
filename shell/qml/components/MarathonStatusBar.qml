import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// The status area: battery left, clock (or lock glyph) centre,
// radios right. No background; small regular-weight text.
Item {
    id: statusBar

    height: Constants.statusBarHeight

    // Ongoing-activity chip; replaces the clock while non-null.
    property Component activityChip: null

    function batteryIcon(level, charging) {
        return charging ? "battery-charging" : level < 0 ? "battery-empty" : level <= 10 ? "battery-warning" : level <= 25 ? "battery-low" : level <= 50 ? "battery-medium" : "battery-full";
    }

    // Strength is carried by the glyph, never by opacity: dimmed icons fall
    // below 3:1 on the bar and the steps can't be told apart.
    function signalIcon(strength) {
        return strength === 0 ? "cell-signal-none" : strength <= 25 ? "cell-signal-low" : strength <= 50 ? "cell-signal-medium" : strength <= 75 ? "cell-signal-high" : "cell-signal-full";
    }

    function wifiIcon(enabled, strength, connected) {
        return !enabled || !connected ? "wifi-slash" : strength <= 33 ? "wifi-low" : strength <= 66 ? "wifi-medium" : "wifi-high";
    }

    // Each cluster's glyphs go dark over a light backdrop, light over a dark one.
    component Tone: BackdropProbe {
        property color glyph: light ? Silica.Theme.darkPrimaryColor : Silica.Theme.lightPrimaryColor

        height: parent.height
        fallbackLight: Silica.Theme.colorScheme === Silica.Theme.DarkOnLight

        Behavior on glyph {
            ColorAnimation {
                duration: MMotion.durationFor("hover")
                easing.type: MMotion.easingFor("hover")
            }
        }
    }

    Tone {
        id: leftTone

        x: leftIconGroup.x
        width: leftIconGroup.width
    }

    Tone {
        id: centerTone

        x: centerContent.x
        width: centerContent.width
    }

    Tone {
        id: rightTone

        x: rightIconGroup.x
        width: rightIconGroup.width
    }

    Row {
        id: leftIconGroup

        anchors.left: parent.left
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Silica.Theme.paddingSmall
        z: 1

        GlyphIcon {
            name: statusBar.batteryIcon(SystemStatusStore.batteryLevel, SystemStatusStore.isPluggedIn)
            Accessible.name: SystemStatusStore.batteryLevel < 0 ? qsTr("Battery level unavailable") : qsTr("Battery %1%").arg(SystemStatusStore.batteryLevel)
            color: leftTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: SystemStatusStore.batteryLevel >= 0
            text: visible ? SystemStatusStore.batteryLevel + "%" : ""
            color: leftTone.glyph
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeExtraSmall
            font.features: ({
                    "tnum": 1
                })
            renderType: Text.QtRendering
            anchors.verticalCenter: parent.verticalCenter
        }

        GlyphIcon {
            name: Power.isPowerSaveMode ? "leaf" : "lightning"
            Accessible.name: Power.isPowerSaveMode ? qsTr("Battery saver on") : qsTr("Performance mode on")
            visible: Power.isPowerSaveMode || Power.powerProfile === "performance"
            color: leftTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
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

    // What is in use, a slice each, beside the clock: the microphone red, the
    // camera orange, location blue. From the kernel's own device opens
    // (Privacy) and the location service, so nothing uses them unseen.
    readonly property var privacyColors: {
        const colors = [];
        if (Privacy.microphone)
            colors.push("#ff3b30");
        if (Privacy.camera)
            colors.push("#ff9500");
        if (typeof LocationManager !== "undefined" && LocationManager && LocationManager.active)
            colors.push("#0a84ff");
        return colors;
    }

    function privacyDotContains(item, x, y) {
        if (!privacyDot.visible)
            return false;
        const p = privacyDot.mapFromItem(item, x, y);
        const slop = Silica.Theme.paddingLarge;
        return p.x >= -slop && p.y >= -slop && p.x <= privacyDot.width + slop && p.y <= privacyDot.height + slop;
    }

    Canvas {
        id: privacyDot

        objectName: "privacyDot"
        anchors.left: centerContent.right
        anchors.leftMargin: Silica.Theme.paddingSmall
        anchors.verticalCenter: centerContent.verticalCenter
        width: Math.round(Silica.Theme.fontSizeSmall * 0.55)
        height: width
        visible: statusBar.privacyColors.length > 0
        renderStrategy: Canvas.Cooperative
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Camera, microphone or location in use")
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const colors = statusBar.privacyColors, r = width / 2;
            const step = 2 * Math.PI / Math.max(1, colors.length);
            for (let i = 0; i < colors.length; ++i) {
                ctx.beginPath();
                ctx.moveTo(r, r);
                ctx.arc(r, r, r, -Math.PI / 2 + i * step, -Math.PI / 2 + (i + 1) * step);
                ctx.closePath();
                ctx.fillStyle = colors[i];
                ctx.fill();
            }
        }

        Connections {
            function onPrivacyColorsChanged() {
                privacyDot.requestPaint();
            }

            target: statusBar
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
            color: centerTone.glyph
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
            color: centerTone.glyph
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
            name: "headphones"
            color: rightTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: AudioManagerCpp.output !== ""
            Accessible.name: AudioManagerCpp.output === "bluetooth" ? qsTr("Bluetooth headphones connected") : qsTr("Headphones connected")
        }

        GlyphIcon {
            name: "plane"
            color: rightTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.isAirplaneMode
        }

        GlyphIcon {
            name: "bell-slash"
            color: rightTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.isDndMode
        }

        GlyphIcon {
            name: SystemStatusStore.isBluetoothConnected ? "bluetooth-connected" : "bluetooth"
            color: rightTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.isBluetoothOn
        }

        GlyphIcon {
            name: statusBar.signalIcon(SystemStatusStore.cellularStrength)
            color: rightTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: Modem.modemAvailable
        }

        Text {
            text: SystemStatusStore.dataType
            color: rightTone.glyph
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeTiny
            anchors.verticalCenter: parent.verticalCenter
            visible: Modem.modemAvailable && SystemStatusStore.dataType !== "" && SystemStatusStore.dataType !== "Unknown"
        }

        GlyphIcon {
            name: "cable"
            color: rightTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.ethernetConnected
        }

        GlyphIcon {
            name: statusBar.wifiIcon(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, Network.wifiConnected)
            color: rightTone.glyph
            size: Silica.Theme.iconSizeExtraSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.isWifiOn
        }
    }
}
