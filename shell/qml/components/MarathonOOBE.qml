import MarathonOS.Shell 1.0
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Item {
    id: oobeRoot

    property WiFiPasswordDialog activePasswordDialog: null
    property var pendingPasswordRequest: null
    property int currentPage: 0
    readonly property var pages: [
        {
            "id": "welcome",
            "title": "Welcome"
        },
        {
            "id": "scale",
            "title": "Display"
        },
        {
            "id": "wifi",
            "title": "WiFi"
        },
        {
            "id": "timezone",
            "title": "Time"
        },
        {
            "id": "gestures",
            "title": "Gestures"
        },
        {
            "id": "passcode",
            "title": "Passcode"
        },
        {
            "id": "complete",
            "title": "Done"
        }
    ]

    // Passcode entry state for the new step.
    property string newPasscode: ""
    property string confirmPasscode: ""
    property string passcodeError: ""
    property bool passcodeSkipped: false

    // Compact OOBE layout for short / square screens (e.g. HyperPixel 4.0
    // Square 720×720 on the Hackberry CM5). At physical DPI 254 the DS-
    // canvas scaleFactor lands around 1.6×, and 220 sf reserved at the
    // bottom + 180 sf hero image + status bar overflowed the 720 px
    // panel — the logo+title got clipped on first boot.
    readonly property bool compactLayout: Constants.isSquareScreen || Constants.screenHeight < 800
    readonly property real swipeBottomMargin: compactLayout ? 140 : 220
    readonly property real heroImageBlockSize: compactLayout ? 100 : 180

    signal setupComplete

    anchors.fill: parent
    visible: !SettingsManagerCpp.firstRunComplete
    z: Constants.zIndexModalOverlay

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        preventStealing: true
        onPressed: function (mouse) {
            mouse.accepted = true;
        }
        onWheel: function (wheel) {
            wheel.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: MColors.background

        // Dither overlay — break HyperPixel 4.0 Square's 18 bpp DPI
        // quantisation banding on the smooth gradient below. Same
        // 4 % tiled noise pattern used by the live wallpaper renderer.
        Image {
            anchors.fill: parent
            source: "qrc:/wallpapers/dither-noise.png"
            fillMode: Image.Tile
            smooth: false
            opacity: 0.04
            z: Constants.zIndexBackground + 1
        }

        Rectangle {
            anchors.fill: parent
            opacity: 0.08

            gradient: Gradient {
                orientation: Gradient.Vertical

                GradientStop {
                    position: 0
                    color: MColors.accent
                }

                GradientStop {
                    position: 0.5
                    color: "transparent"
                }

                GradientStop {
                    position: 1
                    color: MColors.accent
                }
            }
        }
    }

    MarathonStatusBar {
        id: statusBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        z: 100
    }

    SwipeView {
        id: swipeView

        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight
        anchors.leftMargin: MSpacing.xl
        anchors.rightMargin: MSpacing.xl
        // Reserve enough room at the bottom for the Back/Next row (height =
        // touchTargetMedium ~70sf), the page-indicator row, the nav bar, plus
        // margins. The old 170sf was tight at any scale and clipped cards on
        // Gestures / Time & Date / Passcode at high DPI.
        anchors.bottomMargin: Math.round(oobeRoot.swipeBottomMargin * Constants.scaleFactor)
        currentIndex: oobeRoot.currentPage
        interactive: false
        clip: true

        Item {
            // Welcome page — canonical MarathonMark (teal disc + black M
            // + "MARATHON" tracked caps) per docs/redesign/marathonos/
            // project/design-system/ds-foundations.jsx. This is THE
            // brand mark; the old marathon.png raster is retired.
            Column {
                anchors.centerIn: parent
                spacing: Math.round(28 * Constants.scaleFactor)
                width: parent.width

                MMarathonMark {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: Math.round((oobeRoot.compactLayout ? 180 : 220) * Constants.scaleFactor)
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Welcome"
                    font.pixelSize: MTypography.sizeTitle1
                    font.weight: MTypography.weightExtraLight
                    font.family: MTypography.fontFamily
                    font.letterSpacing: MTypography.trackingTitle1
                    color: MColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "A modern, gesture-driven mobile shell.\nLet's get you set up."
                    font.pixelSize: MTypography.sizeSubhead
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    width: Math.round(360 * Constants.scaleFactor)
                }
            }
        }

        Item {
            id: scalePage

            property var scaleOptions: [
                {
                    "factor": 0.75,
                    "title": "75% - Compact",
                    "description": "More content, smaller text"
                },
                {
                    "factor": 0.9,
                    "title": "90% - Small",
                    "description": "Slightly smaller UI"
                },
                {
                    "factor": 1,
                    "title": "100% - Default",
                    "description": "Recommended for most users"
                },
                {
                    "factor": 1.1,
                    "title": "110% - Comfortable",
                    "description": "A bit larger for readability"
                },
                {
                    "factor": 1.25,
                    "title": "125% - Large",
                    "description": "Larger text, easier to read"
                },
                {
                    "factor": 1.4,
                    "title": "140% - Extra Large",
                    "description": "Maximum readability"
                },
                {
                    "factor": 1.5,
                    "title": "150% - Huge",
                    "description": "Oversized UI elements"
                }
            ]

            Column {
                // Anchor at top instead of centerIn -- the 7-radio list is
                // taller than the swipeView area at higher scale factors, so
                // centerIn would overflow upward and collide with the Skip
                // button row.
                anchors.top: parent.top
                anchors.topMargin: Math.round(60 * Constants.scaleFactor)
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                spacing: MSpacing.xl

                Text {
                    text: "Choose Display Size"
                    font.pixelSize: MTypography.sizeXXLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: MColors.text
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    text: "Adjust the size of text and UI elements. You can change this later in Settings."
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    width: parent.width
                    spacing: MSpacing.sm

                    Repeater {
                        model: scalePage.scaleOptions

                        Rectangle {
                            required property var modelData

                            width: parent.width
                            height: Constants.touchTargetMedium
                            radius: Constants.borderRadiusSmall
                            color: Constants.userScaleFactor === modelData.factor ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                            border.width: Constants.userScaleFactor === modelData.factor ? 1 : 0
                            border.color: Qt.rgba(20, 184, 166, 0.3)

                            Row {
                                anchors.fill: parent
                                anchors.margins: MSpacing.md
                                spacing: MSpacing.md

                                Rectangle {
                                    width: Math.round(28 * Constants.userScaleFactor)
                                    height: Math.round(28 * Constants.userScaleFactor)
                                    radius: Math.round(14 * Constants.userScaleFactor)
                                    color: Constants.userScaleFactor === modelData.factor ? MColors.marathonTeal : "transparent"
                                    border.width: Math.round(2 * Constants.userScaleFactor)
                                    border.color: Constants.userScaleFactor === modelData.factor ? MColors.marathonTeal : MColors.textSecondary
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        visible: Constants.userScaleFactor === modelData.factor
                                        width: Math.round(12 * Constants.userScaleFactor)
                                        height: Math.round(12 * Constants.userScaleFactor)
                                        radius: Math.round(6 * Constants.userScaleFactor)
                                        color: MColors.background
                                        anchors.centerIn: parent
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    Text {
                                        text: modelData.title
                                        color: MColors.textPrimary
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: Font.DemiBold
                                        font.family: MTypography.fontFamily
                                    }

                                    Text {
                                        text: modelData.description
                                        color: MColors.textSecondary
                                        font.pixelSize: MTypography.sizeSmall
                                        font.family: MTypography.fontFamily
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                // Write only to SettingsManagerCpp — the
                                // Constants.userScaleFactor Binding listens
                                // for the change and propagates back. Direct
                                // assignment to Constants would break that
                                // binding and the shell would no longer
                                // react to subsequent scale changes.
                                onClicked: SettingsManagerCpp.userScaleFactor = modelData.factor
                            }
                        }
                    }

                    Text {
                        text: "Current: " + Math.round(Constants.scaleFactor * 100) + "% (Base: " + Math.round((Constants.screenHeight / Constants.baseHeight) * 100) + "% × User: " + Math.round(Constants.userScaleFactor * 100) + "%)"
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        Item {
            Row {
                id: wifiHeader

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: MSpacing.lg
                height: Math.round(40 * Constants.scaleFactor)

                Text {
                    text: "Connect to WiFi"
                    font.pixelSize: MTypography.sizeXXLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: MColors.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Flickable {
                anchors.top: wifiHeader.bottom
                anchors.topMargin: MSpacing.xl
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                contentHeight: wifiColumn.height
                clip: true
                boundsBehavior: Flickable.DragAndOvershootBounds

                Column {
                    id: wifiColumn

                    width: parent.width
                    spacing: MSpacing.xxl

                    Text {
                        text: "Connect to a wireless network to continue"
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    MCard {
                        width: parent.width
                        height: MSpacing.touchTargetMedium
                        elevation: 2

                        Row {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            spacing: MSpacing.md

                            Icon {
                                id: wifiIcon

                                name: SystemStatusStore.isWifiOn ? "wifi" : "wifi-off"
                                size: Math.round(24 * Constants.scaleFactor)
                                color: SystemStatusStore.isWifiOn ? MColors.accent : MColors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - wifiIcon.width - wifiToggleSwitch.width - (MSpacing.md * 2)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: MSpacing.xs

                                Text {
                                    text: "WiFi"
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: MTypography.fontFamily
                                    color: MColors.text
                                }

                                Text {
                                    text: SystemStatusStore.isWifiOn ? "Enabled" : "Disabled"
                                    font.pixelSize: MTypography.sizeSmall
                                    font.family: MTypography.fontFamily
                                    color: MColors.textSecondary
                                }
                            }

                            MToggle {
                                id: wifiToggleSwitch

                                checked: SystemStatusStore.isWifiOn
                                onToggled: SystemControlStore.toggleWifi()
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.md
                        visible: SystemStatusStore.isWifiOn

                        Text {
                            text: "Available Networks"
                            width: parent.width
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: Font.DemiBold
                            font.family: MTypography.fontFamily
                            color: MColors.text
                        }

                        Repeater {
                            model: NetworkManagerCpp.availableNetworks

                            MCard {
                                required property var modelData

                                width: parent.parent.width
                                height: MSpacing.touchTargetMedium
                                elevation: 2
                                interactive: true
                                onPressedChanged: {
                                    border.color = pressed ? MColors.accent : MColors.border;
                                }
                                onClicked: {
                                    Logger.info("OOBE", "WiFi network selected:", modelData.ssid);
                                    HapticManager.light();
                                    wifiPasswordDialogLoader.show(modelData.ssid, modelData.strength, modelData.security, modelData.secured);
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: MSpacing.md
                                    spacing: MSpacing.md

                                    Icon {
                                        name: {
                                            if (modelData.strength === 0)
                                                return "wifi-zero";

                                            if (modelData.strength <= 33)
                                                return "wifi-low";

                                            if (modelData.strength <= 66)
                                                return "wifi";

                                            return "wifi-high";
                                        }
                                        size: Math.round(24 * Constants.scaleFactor)
                                        color: modelData.connected ? MColors.accent : MColors.text
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: MSpacing.xs
                                        width: parent.width - Math.round(24 * Constants.scaleFactor) - MSpacing.md * 2 - (modelData.connected ? Math.round(24 * Constants.scaleFactor) + MSpacing.md : 0)

                                        Text {
                                            text: modelData.ssid
                                            font.pixelSize: MTypography.sizeBody
                                            font.weight: modelData.connected ? Font.DemiBold : Font.Medium
                                            font.family: MTypography.fontFamily
                                            color: modelData.connected ? MColors.accent : MColors.text
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Row {
                                            spacing: MSpacing.sm

                                            Text {
                                                text: modelData.connected ? "Connected" : (modelData.security || "Open")
                                                font.pixelSize: MTypography.sizeSmall
                                                font.family: MTypography.fontFamily
                                                color: modelData.connected ? MColors.accent : MColors.textSecondary
                                                font.weight: modelData.connected ? Font.Medium : Font.Normal
                                            }

                                            Text {
                                                text: "•"
                                                font.pixelSize: MTypography.sizeSmall
                                                color: MColors.textSecondary
                                                visible: !modelData.connected
                                            }

                                            Text {
                                                text: modelData.strength + "%"
                                                font.pixelSize: MTypography.sizeSmall
                                                font.family: MTypography.fontFamily
                                                color: MColors.textSecondary
                                                visible: !modelData.connected
                                            }

                                            Icon {
                                                name: "lock"
                                                size: Math.round(16 * Constants.scaleFactor)
                                                color: MColors.textTertiary
                                                visible: modelData.secured && !modelData.connected
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    Icon {
                                        name: "circle-check"
                                        size: Math.round(24 * Constants.scaleFactor)
                                        color: MColors.accent
                                        visible: modelData.connected
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            Row {
                id: timeHeader

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: MSpacing.lg
                height: Math.round(40 * Constants.scaleFactor)

                Text {
                    text: "Set Time & Date"
                    font.pixelSize: MTypography.sizeXXLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: MColors.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Flickable {
                anchors.top: timeHeader.bottom
                anchors.topMargin: MSpacing.xl
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                contentHeight: timeColumn.height
                clip: true
                boundsBehavior: Flickable.DragAndOvershootBounds

                Column {
                    id: timeColumn

                    width: parent.width
                    spacing: MSpacing.xxl

                    Text {
                        text: "Configure your time format preferences"
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    MCard {
                        width: parent.width
                        height: Math.round(120 * Constants.scaleFactor)
                        elevation: 2

                        Column {
                            anchors.centerIn: parent
                            anchors.topMargin: MSpacing.lg
                            anchors.bottomMargin: MSpacing.lg
                            spacing: MSpacing.sm
                            width: parent.width - (MSpacing.lg * 2)

                            Text {
                                text: Qt.formatTime(new Date(), SettingsManagerCpp.timeFormat === "12h" ? "h:mm AP" : "HH:mm")
                                font.pixelSize: Math.round(48 * Constants.scaleFactor)
                                font.weight: Font.Light
                                font.family: MTypography.fontFamily
                                color: MColors.text
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: Qt.formatDate(new Date(), "dddd, MMMM d, yyyy")
                                font.pixelSize: MTypography.sizeLarge
                                font.family: MTypography.fontFamily
                                color: MColors.textSecondary
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    MCard {
                        width: parent.width
                        height: MSpacing.touchTargetMedium
                        elevation: 2

                        Row {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            spacing: MSpacing.md

                            Icon {
                                id: clockIcon

                                name: "clock"
                                size: Math.round(24 * Constants.scaleFactor)
                                color: MColors.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: timeFormatText

                                text: "Time Format"
                                font.pixelSize: MTypography.sizeLarge
                                font.family: MTypography.fontFamily
                                color: MColors.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Item {
                                width: parent.width - clockIcon.width - timeFormatText.implicitWidth - buttonsRow.implicitWidth - (MSpacing.md * 3)
                                height: parent.height
                            }

                            Row {
                                id: buttonsRow

                                spacing: MSpacing.md
                                anchors.verticalCenter: parent.verticalCenter

                                MButton {
                                    text: "12h"
                                    variant: SettingsManagerCpp.timeFormat === "12h" ? "primary" : "default"
                                    height: MSpacing.touchTargetSmall
                                    onClicked: {
                                        SettingsManagerCpp.timeFormat = "12h";
                                        HapticManager.light();
                                    }
                                }

                                MButton {
                                    text: "24h"
                                    variant: SettingsManagerCpp.timeFormat === "24h" ? "primary" : "default"
                                    height: MSpacing.touchTargetSmall
                                    onClicked: {
                                        SettingsManagerCpp.timeFormat = "24h";
                                        HapticManager.light();
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: "Automatic timezone detection and network time sync will be enabled"
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        color: MColors.textTertiary
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        Item {
            Row {
                id: gesturesHeader

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: MSpacing.lg
                height: Math.round(40 * Constants.scaleFactor)

                Text {
                    text: "Learn Gestures"
                    font.pixelSize: MTypography.sizeXXLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: MColors.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Flickable {
                anchors.top: gesturesHeader.bottom
                anchors.topMargin: MSpacing.xl
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                contentHeight: gestureColumn.height
                clip: true
                boundsBehavior: Flickable.DragAndOvershootBounds

                Column {
                    id: gestureColumn

                    width: parent.width
                    spacing: MSpacing.xxl

                    Text {
                        text: "Marathon OS is designed for fluid, gesture-driven navigation."
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Repeater {
                        model: [
                            {
                                "icon": "chevron-up",
                                "title": "Swipe Up",
                                "description": "From bottom edge to open app grid"
                            },
                            {
                                "icon": "chevron-down",
                                "title": "Swipe Down",
                                "description": "From top edge to open quick settings"
                            },
                            {
                                "icon": "chevron-right",
                                "title": "Swipe Right",
                                "description": "From left edge to open Hub"
                            },
                            {
                                "icon": "grid",
                                "title": "Pinch In",
                                "description": "In app grid to open task switcher"
                            },
                            {
                                "icon": "chevrons-up",
                                "title": "Swipe Sideways",
                                "description": "Navigate between pages"
                            }
                        ]

                        MCard {
                            required property var modelData

                            width: parent.width
                            height: MSpacing.touchTargetLarge + MSpacing.md
                            elevation: 2

                            Row {
                                anchors.fill: parent
                                anchors.margins: MSpacing.md
                                spacing: MSpacing.lg

                                MCard {
                                    width: MSpacing.touchTargetMedium
                                    height: MSpacing.touchTargetMedium
                                    elevation: 0
                                    color: MColors.marathonTealHoverGradient
                                    radius: MRadius.md
                                    anchors.verticalCenter: parent.verticalCenter

                                    Icon {
                                        name: modelData.icon
                                        size: Math.round(24 * Constants.scaleFactor)
                                        color: MColors.accent
                                        anchors.centerIn: parent
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: MSpacing.xs

                                    Text {
                                        text: modelData.title
                                        font.pixelSize: MTypography.sizeLarge
                                        font.weight: Font.Medium
                                        font.family: MTypography.fontFamily
                                        color: MColors.text
                                    }

                                    Text {
                                        text: modelData.description
                                        font.pixelSize: MTypography.sizeBody
                                        font.family: MTypography.fontFamily
                                        color: MColors.textSecondary
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Passcode page — keypad-driven PIN setup, two-stage (enter then
        // confirm). Visual pattern mirrors MarathonPinScreen (the lock-
        // screen unlock UI) so OOBE and the lock screen feel unified.
        // iOS / Android quality: 6 progress dots, circular digit keys,
        // animated stage transition, haptic feedback on every press.
        Item {
            id: passcodePage

            readonly property int requiredLength: 4
            readonly property int maxLength: 8
            // "enter" → first attempt, "confirm" → re-enter to verify.
            property string stage: "enter"
            // PIN digits accumulated in the current stage.
            property string enteredPin: ""
            property string confirmedPin: ""
            readonly property string currentPin: stage === "enter" ? enteredPin : confirmedPin

            readonly property bool isCompact: oobeRoot.compactLayout
            readonly property real dotSize: Math.round((isCompact ? 12 : 16) * Constants.scaleFactor)
            readonly property real keySize: Math.round((isCompact ? 56 : 70) * Constants.scaleFactor)
            readonly property real keySpacing: Math.round((isCompact ? 10 : 14) * Constants.scaleFactor)

            function appendDigit(d) {
                if (passcodePage.currentPin.length >= passcodePage.maxLength)
                    return;
                if (passcodePage.stage === "enter")
                    passcodePage.enteredPin += d;
                else
                    passcodePage.confirmedPin += d;
                oobeRoot.passcodeError = "";
                if (typeof HapticManager !== 'undefined')
                    HapticManager.light();
            }

            function deleteDigit() {
                if (passcodePage.stage === "enter" && passcodePage.enteredPin.length > 0)
                    passcodePage.enteredPin = passcodePage.enteredPin.slice(0, -1);
                else if (passcodePage.stage === "confirm" && passcodePage.confirmedPin.length > 0)
                    passcodePage.confirmedPin = passcodePage.confirmedPin.slice(0, -1);
                if (typeof HapticManager !== 'undefined')
                    HapticManager.light();
            }

            function tryAdvance() {
                if (passcodePage.stage === "enter") {
                    if (passcodePage.enteredPin.length < passcodePage.requiredLength) {
                        oobeRoot.passcodeError = "At least " + passcodePage.requiredLength + " digits";
                        return;
                    }
                    passcodePage.stage = "confirm";
                    oobeRoot.passcodeError = "";
                } else {
                    if (passcodePage.confirmedPin !== passcodePage.enteredPin) {
                        oobeRoot.passcodeError = "Passcodes don't match. Try again.";
                        passcodePage.confirmedPin = "";
                        if (typeof HapticManager !== 'undefined')
                            HapticManager.medium();
                        return;
                    }
                    if (typeof SecurityManagerCpp !== 'undefined')
                        SecurityManagerCpp.setQuickPINFirstRun(passcodePage.enteredPin);
                    oobeRoot.newPasscode = passcodePage.enteredPin;
                    oobeRoot.confirmPasscode = passcodePage.enteredPin;
                    oobeRoot.passcodeSkipped = false;
                    oobeRoot.passcodeError = "";
                    if (typeof HapticManager !== 'undefined')
                        HapticManager.medium();
                    oobeRoot.currentPage++;
                }
            }

            Column {
                anchors.fill: parent
                anchors.topMargin: Math.round((passcodePage.isCompact ? 32 : 56) * Constants.scaleFactor)
                anchors.leftMargin: Math.round(28 * Constants.scaleFactor)
                anchors.rightMargin: Math.round(28 * Constants.scaleFactor)
                spacing: Math.round((passcodePage.isCompact ? 14 : 22) * Constants.scaleFactor)

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "lock"
                    size: Math.round((passcodePage.isCompact ? 36 : 48) * Constants.scaleFactor)
                    color: MColors.marathonTealBright
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: passcodePage.stage === "enter" ? "Create a passcode" : "Confirm passcode"
                    font.pixelSize: MTypography.sizeTitle2
                    font.weight: MTypography.weightExtraLight
                    font.family: MTypography.fontFamily
                    font.letterSpacing: MTypography.trackingTitle2
                    color: MColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: passcodePage.stage === "enter" ? "Used to unlock your device after sleep." : "Re-enter the same passcode."
                    font.pixelSize: MTypography.sizeSubhead
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                // PIN-progress dots — fill teal as digits are entered.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Math.round(14 * Constants.scaleFactor)
                    topPadding: Math.round(6 * Constants.scaleFactor)

                    Repeater {
                        model: passcodePage.maxLength

                        Rectangle {
                            required property int index

                            width: passcodePage.dotSize
                            height: passcodePage.dotSize
                            radius: width / 2
                            color: index < passcodePage.currentPin.length ? MColors.marathonTealBright : "transparent"
                            border.width: 1
                            border.color: index < passcodePage.currentPin.length ? MColors.marathonTealBright : MColors.borderSubtle
                            scale: (index === passcodePage.currentPin.length - 1 && passcodePage.currentPin.length > 0) ? 1.25 : 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutBack
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: oobeRoot.passcodeError.length > 0
                    text: oobeRoot.passcodeError
                    color: MColors.error
                    font.pixelSize: MTypography.sizeFootnote
                    font.family: MTypography.fontFamily
                    height: visible ? implicitHeight : 0
                }

                // Numeric keypad — 1-9 grid, then [empty | 0 | delete] row.
                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 3
                    columnSpacing: passcodePage.keySpacing
                    rowSpacing: passcodePage.keySpacing
                    topPadding: Math.round(6 * Constants.scaleFactor)

                    Repeater {
                        model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

                        MCircularIconButton {
                            required property string modelData

                            text: modelData
                            buttonSize: passcodePage.keySize
                            iconSize: Math.round((passcodePage.isCompact ? 22 : 28) * Constants.scaleFactor)
                            variant: "secondary"
                            textColor: MColors.textPrimary
                            onClicked: passcodePage.appendDigit(modelData)
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: passcodePage.keySpacing

                    Item {
                        width: passcodePage.keySize
                        height: passcodePage.keySize
                    }

                    MCircularIconButton {
                        text: "0"
                        buttonSize: passcodePage.keySize
                        iconSize: Math.round((passcodePage.isCompact ? 22 : 28) * Constants.scaleFactor)
                        variant: "secondary"
                        textColor: MColors.textPrimary
                        onClicked: passcodePage.appendDigit("0")
                    }

                    MCircularIconButton {
                        iconName: "delete"
                        buttonSize: passcodePage.keySize
                        iconSize: Math.round((passcodePage.isCompact ? 20 : 24) * Constants.scaleFactor)
                        variant: "secondary"
                        iconColor: MColors.textSecondary
                        enabled: passcodePage.currentPin.length > 0
                        onClicked: passcodePage.deleteDigit()
                    }
                }

                Item {
                    width: parent.width
                    height: Math.round(8 * Constants.scaleFactor)
                }

                // Primary action — context-aware text + state.
                MButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(220 * Constants.scaleFactor)
                    text: passcodePage.stage === "enter" ? "Next" : "Set passcode"
                    variant: "primary"
                    disabled: passcodePage.currentPin.length < passcodePage.requiredLength
                    onClicked: passcodePage.tryAdvance()
                }
            }
        }

        Item {
            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: MSpacing.xxl

                MCard {
                    width: Math.round(120 * Constants.scaleFactor)
                    height: Math.round(120 * Constants.scaleFactor)
                    radius: MRadius.circle
                    color: MColors.elevated
                    elevation: 2
                    anchors.horizontalCenter: parent.horizontalCenter

                    Icon {
                        name: "circle-check"
                        size: Math.round(48 * Constants.scaleFactor)
                        color: MColors.accent
                        anchors.centerIn: parent
                    }
                }

                Text {
                    text: "You're All Set!"
                    font.pixelSize: MTypography.sizeXXLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: MColors.text
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Text {
                    text: "Marathon OS is ready to use. Swipe up from the bottom to see your apps."
                    font.pixelSize: MTypography.sizeLarge
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Text {
                    text: "Tip: open Settings to set a screen-lock PIN, link a CardDAV/CalDAV account for contacts and calendar sync, or check for software updates."
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textTertiary
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                    Accessible.name: text
                }
            }
        }
    }

    Row {
        id: navigationRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: pageIndicatorRow.top
        anchors.leftMargin: MSpacing.xl
        anchors.rightMargin: MSpacing.xl
        anchors.bottomMargin: MSpacing.xl
        height: MSpacing.touchTargetMedium
        spacing: MSpacing.md

        MButton {
            width: (parent.width - MSpacing.md) / 2
            height: parent.height
            text: "Back"
            variant: "default"
            visible: oobeRoot.currentPage > 0
            onClicked: {
                if (oobeRoot.currentPage > 0) {
                    HapticManager.light();
                    oobeRoot.currentPage--;
                }
            }
        }

        Item {
            width: (parent.width - MSpacing.md) / 2
            height: parent.height
            visible: oobeRoot.currentPage === 0
        }

        MButton {
            width: (parent.width - MSpacing.md) / 2
            height: parent.height
            text: oobeRoot.currentPage === oobeRoot.pages.length - 1 ? "Get Started" : "Next"
            variant: "primary"
            // Passcode page (index 5) has its own primary "Set passcode"
            // action — the bottom Next button is hidden there so the user
            // can't bypass passcode setup. /etc/shadow ships with the user
            // account locked '!'; skipping passcode produces an unusable
            // lock screen.
            visible: oobeRoot.currentPage !== 5
            onClicked: {
                HapticManager.light();
                if (oobeRoot.currentPage < oobeRoot.pages.length - 1) {
                    oobeRoot.currentPage++;
                } else {
                    SettingsManagerCpp.firstRunComplete = true;
                    oobeRoot.setupComplete();
                }
            }
        }
    }

    Row {
        id: pageIndicatorRow

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: navBar.top
        anchors.bottomMargin: MSpacing.xxl
        spacing: MSpacing.md
        height: Math.round(20 * Constants.scaleFactor)

        Repeater {
            model: oobeRoot.pages.length

            Rectangle {
                required property int index

                width: oobeRoot.currentPage === index ? Math.round(20 * Constants.scaleFactor) : Math.round(12 * Constants.scaleFactor)
                height: oobeRoot.currentPage === index ? Math.round(20 * Constants.scaleFactor) : Math.round(12 * Constants.scaleFactor)
                radius: oobeRoot.currentPage === index ? Math.round(10 * Constants.scaleFactor) : Math.round(6 * Constants.scaleFactor)
                color: oobeRoot.currentPage === index ? MColors.accent : MColors.textTertiary
                opacity: oobeRoot.currentPage === index ? 1 : 0.5
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    MButton {
        // Anchor below the status bar (not against swipeView top) so the
        // button never crashes into centered logo content on the first page.
        anchors.top: statusBar.bottom
        anchors.topMargin: MSpacing.sm
        anchors.right: parent.right
        anchors.rightMargin: MSpacing.xl
        text: "Skip"
        variant: "default"
        // Skip is only meaningful for early informational steps. The
        // Passcode page needs to complete (the user has no PAM password to
        // fall back on — pmOS_root /etc/shadow ships with the account
        // locked '!'), so hide Skip from page 5 (Passcode) onward. Also
        // hide on page 6 (Done) since that has its own Get Started action.
        visible: oobeRoot.currentPage < 5
        z: 200
        onClicked: {
            SettingsManagerCpp.firstRunComplete = true;
            HapticManager.light();
            oobeRoot.setupComplete();
        }
    }

    MarathonNavBar {
        id: navBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 100
        onSwipeLeft: {
            if (oobeRoot.currentPage > 0) {
                HapticManager.light();
                oobeRoot.currentPage--;
            }
        }
        onSwipeRight: {
            if (oobeRoot.currentPage < oobeRoot.pages.length - 1) {
                HapticManager.light();
                oobeRoot.currentPage++;
            }
        }
    }

    Loader {
        id: wifiPasswordDialogLoader

        function show(ssid, strength, security, secured) {
            active = true;
            oobeRoot.pendingPasswordRequest = {
                "ssid": ssid,
                "strength": strength,
                "security": security,
                "secured": secured
            };
            if (oobeRoot.activePasswordDialog) {
                oobeRoot.activePasswordDialog.show(ssid, strength, security, secured);
                oobeRoot.pendingPasswordRequest = null;
            }
        }

        anchors.fill: parent
        active: false
        onLoaded: {
            oobeRoot.activePasswordDialog = item;
            if (oobeRoot.pendingPasswordRequest) {
                var request = oobeRoot.pendingPasswordRequest;
                oobeRoot.pendingPasswordRequest = null;
                oobeRoot.activePasswordDialog.show(request.ssid, request.strength, request.security, request.secured);
            }
        }
        onActiveChanged: {
            if (!active)
                oobeRoot.activePasswordDialog = null;
        }

        sourceComponent: WiFiPasswordDialog {
            onConnectRequested: (ssid, password) => {
                Logger.info("OOBE", "Connecting to WiFi:", ssid);
                NetworkManagerCpp.connectToNetwork(ssid, password);
            }
            onCancelled: {
                Logger.info("OOBE", "WiFi connection cancelled");
            }
        }
    }

    Connections {
        function onConnectionSuccess() {
            // hide() runs the slide-down + fade-out animation (~250 ms).
            // The prior code set `wifiPasswordDialogLoader.active = false`
            // synchronously on the next line, which destroys the Loader's
            // content RIGHT AWAY — killing the animation mid-flight and
            // making the dialog appear to vanish instantly. The user has
            // no time to see the connection completed.
            //
            // Now we just call .hide() — the dialog's own hideAnimation
            // ScriptAction sets internalVisible=false at the end, the
            // dialog stays in the scene but invisible. cleanupTimer
            // destroys the Loader content shortly AFTER the animation
            // finishes so the next show() rebuilds cleanly.
            if (oobeRoot.activePasswordDialog) {
                oobeRoot.activePasswordDialog.hide();
                wifiCleanupTimer.restart();
            }
            HapticManager.medium();
        }

        function onConnectionFailed(message) {
            if (oobeRoot.activePasswordDialog)
                oobeRoot.activePasswordDialog.showError(message);
        }

        target: NetworkManagerCpp
    }

    Timer {
        id: wifiCleanupTimer

        // Slightly longer than the dialog's 250 ms hideAnimation so the
        // animation has completed before we destroy the Loader content.
        interval: 320
        repeat: false
        onTriggered: wifiPasswordDialogLoader.active = false
    }

    Timer {
        interval: 1000
        running: SystemStatusStore.isWifiOn
        repeat: false
        onTriggered: {
            if (SystemStatusStore.isWifiOn) {
                NetworkManagerCpp.scanWifi();
            }
        }
    }
}
