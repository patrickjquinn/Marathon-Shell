import MarathonOS.Shell 1.0
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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
            source: "file:///usr/share/marathon-shell/wallpapers/dither-noise.png"
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
            clip: true

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

            clip: true

            readonly property var scaleFactors: [0.75, 0.9, 1.0, 1.1, 1.25, 1.4, 1.5]

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: oobeRoot.compactLayout ? MSpacing.xl : MSpacing.xxl
                anchors.leftMargin: MSpacing.xl
                anchors.rightMargin: MSpacing.xl
                anchors.bottomMargin: Math.round((oobeRoot.compactLayout ? 90 : 110) * Constants.scaleFactor)
                spacing: oobeRoot.compactLayout ? MSpacing.sm : MSpacing.md

                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "text-aa"
                    size: Math.round((oobeRoot.compactLayout ? 32 : 40) * Constants.scaleFactor)
                    color: MColors.marathonTealBright
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Choose display size"
                    font.pixelSize: MTypography.sizeTitle2
                    font.weight: MTypography.weightExtraLight
                    font.family: MTypography.fontFamily
                    font.letterSpacing: MTypography.trackingTitle2
                    color: MColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: "Make text and icons easier to read. You can change this anytime."
                    font.pixelSize: MTypography.sizeSubhead
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                MCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    elevation: 2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: MSpacing.lg
                        spacing: MSpacing.sm

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Preview"
                            font.pixelSize: MTypography.sizeSmall
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: Math.max(1, Math.round(1 * Constants.scaleFactor))
                            font.family: MTypography.fontFamily
                            color: MColors.textTertiary
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.centerIn: parent
                                width: parent.width
                                spacing: Math.round(MSpacing.sm * Constants.userScaleFactor)

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Sample"
                                    font.pixelSize: Math.round(MTypography.sizeTitle2 * Constants.userScaleFactor)
                                    font.weight: MTypography.weightExtraLight
                                    font.family: MTypography.fontFamily
                                    font.letterSpacing: MTypography.trackingTitle2
                                    color: MColors.textPrimary

                                    Behavior on font.pixelSize {
                                        NumberAnimation {
                                            duration: MMotion.sm
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "The quick brown fox jumps over the lazy dog."
                                    font.pixelSize: Math.round(MTypography.sizeBody * Constants.userScaleFactor)
                                    font.family: MTypography.fontFamily
                                    color: MColors.textSecondary
                                    wrapMode: Text.WordWrap
                                    horizontalAlignment: Text.AlignHCenter

                                    Behavior on font.pixelSize {
                                        NumberAnimation {
                                            duration: MMotion.sm
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: Math.round(MSpacing.sm * Constants.userScaleFactor)

                                    Icon {
                                        name: "house"
                                        size: Math.round(20 * Constants.userScaleFactor)
                                        color: MColors.marathonTealBright

                                        Behavior on size {
                                            NumberAnimation {
                                                duration: MMotion.sm
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    Icon {
                                        name: "envelope"
                                        size: Math.round(20 * Constants.userScaleFactor)
                                        color: MColors.textPrimary

                                        Behavior on size {
                                            NumberAnimation {
                                                duration: MMotion.sm
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    Icon {
                                        name: "gear"
                                        size: Math.round(20 * Constants.userScaleFactor)
                                        color: MColors.textPrimary

                                        Behavior on size {
                                            NumberAnimation {
                                                duration: MMotion.sm
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: MSpacing.xs

                    Text {
                        text: "A"
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        color: MColors.textTertiary
                    }

                    Repeater {
                        model: scalePage.scaleFactors

                        Rectangle {
                            required property real modelData

                            readonly property bool selected: Math.abs(Constants.userScaleFactor - modelData) < 0.001

                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.round(40 * Constants.scaleFactor)
                            radius: Math.round(8 * Constants.scaleFactor)
                            color: selected ? MColors.marathonTealBright : "transparent"
                            border.width: 1
                            border.color: selected ? MColors.marathonTealBright : MColors.border

                            Behavior on color {
                                ColorAnimation {
                                    duration: MMotion.xs
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: Math.round(parent.modelData * 100)
                                font.pixelSize: MTypography.sizeSmall
                                font.weight: parent.selected ? Font.DemiBold : Font.Medium
                                font.family: MTypography.fontFamily
                                color: parent.selected ? "#000000" : MColors.textPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticManager.light();
                                    SettingsManagerCpp.userScaleFactor = parent.modelData;
                                }
                            }
                        }
                    }

                    Text {
                        text: "A"
                        font.pixelSize: Math.round(MTypography.sizeLarge * Constants.scaleFactor)
                        font.family: MTypography.fontFamily
                        color: MColors.textTertiary
                    }
                }
            }
        }

        Item {
            id: wifiPage

            clip: true

            property string pendingSsid: ""
            property bool firstScanDone: NetworkManagerCpp.availableNetworks.length > 0

            Connections {
                target: NetworkManagerCpp
                function onConnectionSuccess() {
                    wifiPage.pendingSsid = "";
                }
                function onConnectionFailed(message) {
                    wifiPage.pendingSsid = "";
                }
                function onAvailableNetworksChanged() {
                    if (NetworkManagerCpp.availableNetworks.length > 0)
                        wifiPage.firstScanDone = true;
                }
            }

            Timer {
                interval: 2500
                running: SystemStatusStore.isWifiOn && !wifiPage.firstScanDone
                repeat: false
                onTriggered: wifiPage.firstScanDone = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: oobeRoot.compactLayout ? MSpacing.xl : MSpacing.xxl
                anchors.leftMargin: MSpacing.xl
                anchors.rightMargin: MSpacing.xl
                anchors.bottomMargin: Math.round((oobeRoot.compactLayout ? 90 : 110) * Constants.scaleFactor)
                spacing: oobeRoot.compactLayout ? MSpacing.sm : MSpacing.md

                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    name: SystemStatusStore.isWifiOn ? "wifi" : "wifi-off"
                    size: Math.round((oobeRoot.compactLayout ? 32 : 40) * Constants.scaleFactor)
                    color: MColors.marathonTealBright
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Connect to a network"
                    font.pixelSize: MTypography.sizeTitle2
                    font.weight: MTypography.weightExtraLight
                    font.family: MTypography.fontFamily
                    font.letterSpacing: MTypography.trackingTitle2
                    color: MColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: SystemStatusStore.isWifiOn ? "Pick a network, or continue without one." : "Turn WiFi on to see nearby networks."
                    font.pixelSize: MTypography.sizeSubhead
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                MCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: wifiOffRow.implicitHeight + MSpacing.md * 2
                    elevation: 2
                    visible: !SystemStatusStore.isWifiOn

                    RowLayout {
                        id: wifiOffRow

                        anchors.fill: parent
                        anchors.margins: MSpacing.md
                        spacing: MSpacing.md

                        Icon {
                            name: "wifi"
                            size: Math.round(24 * Constants.scaleFactor)
                            color: MColors.textSecondary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "WiFi is off"
                            font.pixelSize: MTypography.sizeBody
                            font.family: MTypography.fontFamily
                            color: MColors.textPrimary
                        }

                        MToggle {
                            checked: SystemStatusStore.isWifiOn
                            onToggled: SystemControlStore.toggleWifi()
                        }
                    }
                }

                MCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    elevation: 2
                    visible: SystemStatusStore.isWifiOn

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: MSpacing.sm
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: MSpacing.touchTargetMedium
                            spacing: MSpacing.sm

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: MSpacing.md
                                text: "Networks"
                                font.pixelSize: MTypography.sizeSmall
                                font.weight: Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: Math.max(1, Math.round(1 * Constants.scaleFactor))
                                font.family: MTypography.fontFamily
                                color: MColors.textTertiary
                                verticalAlignment: Text.AlignVCenter
                            }

                            MIconButton {
                                Layout.preferredWidth: MSpacing.touchTargetMedium
                                Layout.preferredHeight: MSpacing.touchTargetMedium
                                Layout.rightMargin: MSpacing.xs
                                iconName: "refresh-cw"
                                a11yName: "Rescan networks"
                                iconSize: 18
                                iconColor: MColors.marathonTealBright
                                onClicked: {
                                    HapticManager.light();
                                    wifiPage.firstScanDone = false;
                                    NetworkManagerCpp.scanWifi();
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: MColors.border
                            opacity: 0.5
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Column {
                                anchors.fill: parent
                                anchors.margins: MSpacing.sm
                                spacing: MSpacing.sm
                                visible: !wifiPage.firstScanDone

                                Repeater {
                                    model: 4

                                    Rectangle {
                                        width: parent.width
                                        height: Math.round(56 * Constants.scaleFactor)
                                        radius: Math.round(8 * Constants.scaleFactor)
                                        color: MColors.surface

                                        SequentialAnimation on opacity {
                                            loops: Animation.Infinite
                                            running: !wifiPage.firstScanDone

                                            NumberAnimation {
                                                from: 0.25
                                                to: 0.55
                                                duration: 800
                                            }

                                            NumberAnimation {
                                                from: 0.55
                                                to: 0.25
                                                duration: 800
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - MSpacing.lg * 2
                                spacing: MSpacing.sm
                                visible: wifiPage.firstScanDone && NetworkManagerCpp.availableNetworks.length === 0

                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: "wifi-off"
                                    size: Math.round(32 * Constants.scaleFactor)
                                    color: MColors.textTertiary
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No networks found"
                                    font.pixelSize: MTypography.sizeBody
                                    font.family: MTypography.fontFamily
                                    color: MColors.textSecondary
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    width: parent.width
                                    text: "Move closer to a router, or tap refresh."
                                    font.pixelSize: MTypography.sizeSmall
                                    font.family: MTypography.fontFamily
                                    color: MColors.textTertiary
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Flickable {
                                anchors.fill: parent
                                contentHeight: networkColumn.height
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                visible: wifiPage.firstScanDone && NetworkManagerCpp.availableNetworks.length > 0

                                Column {
                                    id: networkColumn

                                    width: parent.width
                                    spacing: 0

                                    Repeater {
                                        model: NetworkManagerCpp.availableNetworks

                                        Item {
                                            id: networkRow

                                            required property var modelData
                                            required property int index

                                            readonly property bool isPending: wifiPage.pendingSsid === modelData.ssid
                                            readonly property bool rowEnabled: !modelData.connected && wifiPage.pendingSsid === ""

                                            width: parent.width
                                            height: Math.round(56 * Constants.scaleFactor)

                                            Rectangle {
                                                anchors.fill: parent
                                                color: pressArea.pressed ? MColors.elevated : "transparent"

                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: MMotion.xs
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: MSpacing.sm
                                                anchors.rightMargin: MSpacing.sm
                                                spacing: MSpacing.md

                                                Icon {
                                                    name: {
                                                        const s = modelData.strength;
                                                        if (s >= 75)
                                                            return "wifi-high";
                                                        if (s >= 50)
                                                            return "wifi";
                                                        if (s >= 25)
                                                            return "wifi-low";
                                                        return "wifi-zero";
                                                    }
                                                    size: Math.round(20 * Constants.scaleFactor)
                                                    color: modelData.connected ? MColors.marathonTealBright : MColors.textPrimary
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.ssid
                                                        font.pixelSize: MTypography.sizeBody
                                                        font.weight: modelData.connected ? Font.DemiBold : Font.Medium
                                                        font.family: MTypography.fontFamily
                                                        color: modelData.connected ? MColors.marathonTealBright : MColors.textPrimary
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        visible: modelData.connected || networkRow.isPending
                                                        text: networkRow.isPending ? "Connecting…" : "Connected"
                                                        font.pixelSize: MTypography.sizeSmall
                                                        font.family: MTypography.fontFamily
                                                        color: networkRow.isPending ? MColors.textSecondary : MColors.marathonTealBright
                                                    }
                                                }

                                                BusyIndicator {
                                                    Layout.preferredWidth: Math.round(20 * Constants.scaleFactor)
                                                    Layout.preferredHeight: Math.round(20 * Constants.scaleFactor)
                                                    running: networkRow.isPending
                                                    visible: running
                                                }

                                                Icon {
                                                    visible: modelData.secured && !networkRow.isPending && !modelData.connected
                                                    name: "lock"
                                                    size: Math.round(14 * Constants.scaleFactor)
                                                    color: MColors.textTertiary
                                                }

                                                Icon {
                                                    visible: modelData.connected
                                                    name: "check"
                                                    size: Math.round(16 * Constants.scaleFactor)
                                                    color: MColors.marathonTealBright
                                                }
                                            }

                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.left: parent.left
                                                anchors.leftMargin: MSpacing.xl + MSpacing.md
                                                anchors.right: parent.right
                                                anchors.rightMargin: MSpacing.sm
                                                height: 1
                                                color: MColors.border
                                                opacity: 0.3
                                                visible: networkRow.index < NetworkManagerCpp.availableNetworks.length - 1
                                            }

                                            MouseArea {
                                                id: pressArea

                                                anchors.fill: parent
                                                enabled: networkRow.rowEnabled
                                                onClicked: {
                                                    HapticManager.light();
                                                    if (modelData.secured) {
                                                        wifiPasswordDialogLoader.show(modelData.ssid, modelData.strength, modelData.security, modelData.secured);
                                                    } else {
                                                        wifiPage.pendingSsid = modelData.ssid;
                                                        NetworkManagerCpp.connectToNetwork(modelData.ssid, "");
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: MSpacing.xs
                    text: "Join other network…"
                    font.pixelSize: MTypography.sizeSmall
                    font.family: MTypography.fontFamily
                    font.weight: Font.Medium
                    color: MColors.marathonTealBright
                    visible: SystemStatusStore.isWifiOn && wifiPage.firstScanDone

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticManager.light();
                            wifiPasswordDialogLoader.show("", 0, "WPA2", true);
                        }
                    }
                }
            }
        }

        Item {
            id: timezonePage

            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: oobeRoot.compactLayout ? MSpacing.xl : MSpacing.xxl
                anchors.leftMargin: MSpacing.xl
                anchors.rightMargin: MSpacing.xl
                spacing: oobeRoot.compactLayout ? MSpacing.md : MSpacing.lg

                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "clock"
                    size: Math.round((oobeRoot.compactLayout ? 36 : 48) * Constants.scaleFactor)
                    color: MColors.marathonTealBright
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Set Time & Date"
                    font.pixelSize: MTypography.sizeTitle2
                    font.weight: MTypography.weightExtraLight
                    font.family: MTypography.fontFamily
                    font.letterSpacing: MTypography.trackingTitle2
                    color: MColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: "Configure your time format preferences."
                    font.pixelSize: MTypography.sizeSubhead
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                MCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: timeColumn.implicitHeight + MSpacing.lg * 2
                    elevation: 2

                    ColumnLayout {
                        id: timeColumn

                        anchors.fill: parent
                        anchors.margins: MSpacing.lg
                        spacing: MSpacing.sm

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatTime(new Date(), SettingsManagerCpp.timeFormat === "12h" ? "h:mm AP" : "HH:mm")
                            font.pixelSize: Math.round(48 * Constants.scaleFactor)
                            font.weight: Font.Light
                            font.family: MTypography.fontFamily
                            color: MColors.text
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDate(new Date(), "dddd, MMMM d, yyyy")
                            font.pixelSize: MTypography.sizeLarge
                            font.family: MTypography.fontFamily
                            color: MColors.textSecondary
                        }
                    }
                }

                MCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: formatRow.implicitHeight + MSpacing.md * 2
                    elevation: 2

                    RowLayout {
                        id: formatRow

                        anchors.fill: parent
                        anchors.margins: MSpacing.md
                        spacing: MSpacing.md

                        Icon {
                            name: "clock"
                            size: Math.round(24 * Constants.scaleFactor)
                            color: MColors.text
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Time Format"
                            font.pixelSize: MTypography.sizeLarge
                            font.family: MTypography.fontFamily
                            color: MColors.text
                            elide: Text.ElideRight
                        }

                        MButton {
                            text: "12h"
                            variant: SettingsManagerCpp.timeFormat === "12h" ? "primary" : "default"
                            size: "small"
                            onClicked: {
                                SettingsManagerCpp.timeFormat = "12h";
                                HapticManager.light();
                            }
                        }

                        MButton {
                            text: "24h"
                            variant: SettingsManagerCpp.timeFormat === "24h" ? "primary" : "default"
                            size: "small"
                            onClicked: {
                                SettingsManagerCpp.timeFormat = "24h";
                                HapticManager.light();
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Automatic timezone detection and network time sync will be enabled."
                    font.pixelSize: MTypography.sizeSmall
                    font.family: MTypography.fontFamily
                    color: MColors.textTertiary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        Item {
            id: gesturesPage

            clip: true

            // Interactive coachmark sequence — one gesture per sub-page.
            // The animated arrow loops to demonstrate direction; the user
            // performs the matching swipe inside the practice zone, which
            // marks the coachmark complete and advances. A Skip link is
            // available for users who cannot or do not want to practise.
            property int currentCoachmark: 0
            readonly property var coachmarks: [
                {
                    "icon": "chevron-up",
                    "title": "Swipe Up",
                    "body": "From the bottom of the screen to go home or peek at open apps.",
                    "direction": "up"
                },
                {
                    "icon": "chevron-down",
                    "title": "Swipe Down",
                    "body": "From the top of the screen to open Quick Settings — Wi-Fi, brightness, Do Not Disturb.",
                    "direction": "down"
                },
                {
                    "icon": "chevron-right",
                    "title": "Swipe Right",
                    "body": "Across the home grid to reach the Hub — messages, notifications, calls.",
                    "direction": "right"
                },
                {
                    "icon": "chevron-left",
                    "title": "Swipe Left",
                    "body": "From the Hub back to your apps. The same gesture works between any two pages.",
                    "direction": "left"
                },
                {
                    "icon": "check-circle",
                    "title": "You're set",
                    "body": "These gestures work everywhere in Marathon. Tap Next to continue.",
                    "direction": "none"
                }
            ]

            function markComplete() {
                if (gesturesPage.currentCoachmark < gesturesPage.coachmarks.length - 1)
                    gesturesPage.currentCoachmark++;
            }

            Column {
                id: gesturesHeader

                anchors.top: parent.top
                anchors.topMargin: oobeRoot.compactLayout ? MSpacing.xl : MSpacing.xxl
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: oobeRoot.compactLayout ? MSpacing.xs : MSpacing.sm

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "hand-pointing"
                    size: Math.round((oobeRoot.compactLayout ? 32 : 40) * Constants.scaleFactor)
                    color: MColors.marathonTealBright
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Learn the gestures"
                    font.pixelSize: MTypography.sizeTitle2
                    font.weight: MTypography.weightExtraLight
                    font.family: MTypography.fontFamily
                    font.letterSpacing: MTypography.trackingTitle2
                    color: MColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            StackLayout {
                id: coachmarkStack

                anchors.top: gesturesHeader.bottom
                anchors.topMargin: MSpacing.xl
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: coachmarkDots.top
                anchors.bottomMargin: MSpacing.lg
                currentIndex: gesturesPage.currentCoachmark

                Repeater {
                    model: gesturesPage.coachmarks

                    delegate: Item {
                        required property var modelData
                        required property int index

                        Column {
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: MSpacing.xl

                            // Animated arrow demo — only loops while this is
                            // the active coachmark and there is a direction
                            // to demonstrate.
                            Item {
                                width: Math.round(120 * Constants.scaleFactor)
                                height: Math.round(120 * Constants.scaleFactor)
                                anchors.horizontalCenter: parent.horizontalCenter

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: parent.height
                                    radius: width / 2
                                    color: MColors.marathonTealHoverGradient
                                    opacity: 0.5
                                }

                                Icon {
                                    id: coachmarkIcon

                                    anchors.centerIn: parent
                                    name: modelData.icon
                                    size: Math.round(72 * Constants.scaleFactor)
                                    color: MColors.accent

                                    transform: Translate {
                                        id: coachmarkNudge

                                        x: 0
                                        y: 0
                                    }
                                }

                                SequentialAnimation {
                                    running: gesturesPage.currentCoachmark === index && modelData.direction !== "none"
                                    loops: Animation.Infinite

                                    NumberAnimation {
                                        target: coachmarkNudge
                                        property: (modelData.direction === "left" || modelData.direction === "right") ? "x" : "y"
                                        from: 0
                                        to: {
                                            const amount = Math.round(32 * Constants.scaleFactor);
                                            if (modelData.direction === "up")
                                                return -amount;
                                            if (modelData.direction === "down")
                                                return amount;
                                            if (modelData.direction === "left")
                                                return -amount;
                                            if (modelData.direction === "right")
                                                return amount;
                                            return 0;
                                        }
                                        duration: 700
                                        easing.type: Easing.OutCubic
                                    }
                                    PauseAnimation {
                                        duration: 120
                                    }
                                    NumberAnimation {
                                        target: coachmarkNudge
                                        property: (modelData.direction === "left" || modelData.direction === "right") ? "x" : "y"
                                        to: 0
                                        duration: 500
                                        easing.type: Easing.OutCubic
                                    }
                                    PauseAnimation {
                                        duration: 400
                                    }
                                }
                            }

                            Text {
                                text: modelData.title
                                font.pixelSize: MTypography.sizeTitle3
                                font.weight: MTypography.weightExtraLight
                                font.family: MTypography.fontFamily
                                font.letterSpacing: MTypography.trackingTitle3
                                color: MColors.textPrimary
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: modelData.body
                                font.pixelSize: MTypography.sizeSubhead
                                font.family: MTypography.fontFamily
                                color: MColors.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                width: parent.width - MSpacing.xxl
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            // Practice zone — capture a matching swipe to
                            // confirm the gesture. Single-touch only; both
                            // distance and axis dominance are checked so a
                            // diagonal jitter doesn't accidentally pass.
                            Item {
                                width: parent.width - MSpacing.xxl
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: MSpacing.touchTargetMedium
                                visible: modelData.direction !== "none"

                                Rectangle {
                                    anchors.fill: parent
                                    radius: MRadius.md
                                    color: MColors.elev2
                                    border.width: 1
                                    border.color: MColors.borderSubtle
                                    opacity: practiceArea.pressed ? 0.7 : 0.4

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 120
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Try the " + modelData.title.toLowerCase() + " here"
                                    font.pixelSize: MTypography.sizeFootnote
                                    font.family: MTypography.fontFamily
                                    color: MColors.textTertiary
                                }

                                MouseArea {
                                    id: practiceArea

                                    property real pressX: 0
                                    property real pressY: 0

                                    anchors.fill: parent
                                    onPressed: function (mouse) {
                                        pressX = mouse.x;
                                        pressY = mouse.y;
                                    }
                                    onReleased: function (mouse) {
                                        const dx = mouse.x - pressX;
                                        const dy = mouse.y - pressY;
                                        const threshold = Math.round(36 * Constants.scaleFactor);
                                        let matched = false;
                                        if (modelData.direction === "up" && dy < -threshold && Math.abs(dy) > Math.abs(dx))
                                            matched = true;
                                        else if (modelData.direction === "down" && dy > threshold && Math.abs(dy) > Math.abs(dx))
                                            matched = true;
                                        else if (modelData.direction === "left" && dx < -threshold && Math.abs(dx) > Math.abs(dy))
                                            matched = true;
                                        else if (modelData.direction === "right" && dx > threshold && Math.abs(dx) > Math.abs(dy))
                                            matched = true;
                                        if (matched) {
                                            if (typeof HapticManager !== "undefined")
                                                HapticManager.medium();
                                            gesturesPage.markComplete();
                                        }
                                    }
                                }
                            }

                            Item {
                                width: parent.width
                                height: Math.round(32 * Constants.scaleFactor)
                                visible: modelData.direction !== "none"

                                Text {
                                    anchors.centerIn: parent
                                    text: "Skip this gesture"
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: Font.Medium
                                    font.family: MTypography.fontFamily
                                    color: MColors.accent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (typeof HapticManager !== "undefined")
                                            HapticManager.light();
                                        gesturesPage.markComplete();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Row {
                id: coachmarkDots

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round((oobeRoot.compactLayout ? 90 : 110) * Constants.scaleFactor)
                spacing: MSpacing.sm

                Repeater {
                    model: gesturesPage.coachmarks.length

                    delegate: Rectangle {
                        required property int index

                        readonly property bool isActive: index === gesturesPage.currentCoachmark

                        width: isActive ? Math.round(20 * Constants.scaleFactor) : Math.round(6 * Constants.scaleFactor)
                        height: Math.round(6 * Constants.scaleFactor)
                        radius: height / 2
                        color: isActive ? MColors.accent : MColors.whiteOverlay24
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on width {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 200
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

            clip: true

            readonly property int requiredLength: 6
            readonly property int maxLength: 6
            // "enter" → first attempt, "confirm" → re-enter to verify.
            property string stage: "enter"
            // PIN digits accumulated in the current stage.
            property string enteredPin: ""
            property string confirmedPin: ""
            readonly property string currentPin: stage === "enter" ? enteredPin : confirmedPin

            readonly property bool isCompact: oobeRoot.compactLayout
            readonly property real dotSize: Math.round((isCompact ? 12 : 16) * Constants.scaleFactor)
            readonly property real keySize: isCompact ? 56 : 70
            // Scaled size for cell-container Items (the spacer at row 4 col 0
            // and the +/-/dot keys). Must be ≥ MCircularIconButton's full
            // chrome size (buttonSize × sf + halo), so the layout reserves
            // enough room around the rendered button.
            readonly property real scaledKeyCell: Math.round(keySize * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
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
                if (passcodePage.currentPin.length === passcodePage.requiredLength)
                    passcodePage.tryAdvance();
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

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Math.round((passcodePage.isCompact ? 32 : 56) * Constants.scaleFactor)
                anchors.leftMargin: Math.round(28 * Constants.scaleFactor)
                anchors.rightMargin: Math.round(28 * Constants.scaleFactor)
                spacing: Math.round((passcodePage.isCompact ? 14 : 22) * Constants.scaleFactor)

                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "lock"
                    size: Math.round((passcodePage.isCompact ? 36 : 48) * Constants.scaleFactor)
                    color: MColors.marathonTealBright
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: passcodePage.stage === "enter" ? "Create a passcode" : "Confirm passcode"
                    font.pixelSize: MTypography.sizeTitle2
                    font.weight: MTypography.weightExtraLight
                    font.family: MTypography.fontFamily
                    font.letterSpacing: MTypography.trackingTitle2
                    color: MColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: passcodePage.stage === "enter" ? "Used to unlock your device after sleep." : "Re-enter the same passcode."
                    font.pixelSize: MTypography.sizeSubhead
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                // PIN-progress dots — fill teal as digits are entered.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Math.round(14 * Constants.scaleFactor)

                    Repeater {
                        model: passcodePage.maxLength

                        Rectangle {
                            required property int index

                            Layout.preferredWidth: passcodePage.dotSize
                            Layout.preferredHeight: passcodePage.dotSize
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
                    Layout.alignment: Qt.AlignHCenter
                    visible: oobeRoot.passcodeError.length > 0
                    text: oobeRoot.passcodeError
                    color: MColors.error
                    font.pixelSize: MTypography.sizeFootnote
                    font.family: MTypography.fontFamily
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignHCenter
                    columns: 3
                    columnSpacing: passcodePage.keySpacing
                    rowSpacing: passcodePage.keySpacing

                    Repeater {
                        model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

                        Item {
                            required property string modelData

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.maximumWidth: passcodePage.scaledKeyCell
                            Layout.maximumHeight: passcodePage.scaledKeyCell

                            MCircularIconButton {
                                anchors.centerIn: parent
                                width: Math.min(parent.width, parent.height)
                                height: width
                                text: modelData
                                buttonSize: passcodePage.keySize
                                iconSize: passcodePage.isCompact ? 22 : 28
                                variant: "secondary"
                                textColor: MColors.textPrimary
                                onClicked: passcodePage.appendDigit(modelData)
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumWidth: passcodePage.scaledKeyCell
                        Layout.maximumHeight: passcodePage.scaledKeyCell
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumWidth: passcodePage.scaledKeyCell
                        Layout.maximumHeight: passcodePage.scaledKeyCell

                        MCircularIconButton {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height)
                            height: width
                            text: "0"
                            buttonSize: passcodePage.keySize
                            iconSize: passcodePage.isCompact ? 22 : 28
                            variant: "secondary"
                            textColor: MColors.textPrimary
                            onClicked: passcodePage.appendDigit("0")
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumWidth: passcodePage.scaledKeyCell
                        Layout.maximumHeight: passcodePage.scaledKeyCell

                        MCircularIconButton {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height)
                            height: width
                            iconName: "delete"
                            buttonSize: passcodePage.keySize
                            iconSize: passcodePage.isCompact ? 20 : 24
                            variant: "secondary"
                            iconColor: MColors.textSecondary
                            enabled: passcodePage.currentPin.length > 0
                            onClicked: passcodePage.deleteDigit()
                        }
                    }
                }
            }
        }

        Item {
            clip: true

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
                    text: "You're all set"
                    font.pixelSize: MTypography.sizeTitle2
                    font.weight: MTypography.weightExtraLight
                    font.family: MTypography.fontFamily
                    font.letterSpacing: MTypography.trackingTitle2
                    color: MColors.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Text {
                    text: "Marathon is ready. Swipe up from the bottom of the screen to see your apps."
                    font.pixelSize: MTypography.sizeSubhead
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
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
        spacing: MSpacing.md

        MButton {
            width: (parent.width - MSpacing.md) / 2
            size: "large"
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
            height: Math.round(50 * Constants.scaleFactor)
            visible: oobeRoot.currentPage === 0
        }

        MButton {
            width: (parent.width - MSpacing.md) / 2
            size: "large"
            text: {
                if (oobeRoot.currentPage === oobeRoot.pages.length - 1)
                    return "Get Started";
                if (oobeRoot.currentPage === 5)
                    return passcodePage.stage === "enter" ? "Next" : "Set passcode";
                return "Next";
            }
            variant: "primary"
            disabled: oobeRoot.currentPage === 5 && passcodePage.currentPin.length < passcodePage.requiredLength
            onClicked: {
                HapticManager.light();
                if (oobeRoot.currentPage === 5) {
                    passcodePage.tryAdvance();
                    return;
                }
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
