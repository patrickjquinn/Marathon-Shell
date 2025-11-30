import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Containers

/**
 * Marathon OS - Out-of-Box Experience (OOBE)
 *
 * World-class first-run setup with Marathon design system
 */
Item {
    id: oobeRoot
    anchors.fill: parent
    visible: !SettingsManagerCpp.firstRunComplete
    z: Constants.zIndexModalOverlay

    signal setupComplete

    // State management
    property int currentPage: 0
    readonly property var pages: [
        {
            id: "welcome",
            title: "Welcome"
        },
        {
            id: "wifi",
            title: "WiFi"
        },
        {
            id: "timezone",
            title: "Time"
        },
        {
            id: "gestures",
            title: "Gestures"
        },
        {
            id: "complete",
            title: "Done"
        }
    ]

    // Background with subtle radial gradient pattern
    Rectangle {
        anchors.fill: parent
        color: MColors.background

        // Subtle radial gradient overlay for depth
        Rectangle {
            anchors.fill: parent
            opacity: 0.08
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: MColors.accent
                }
                GradientStop {
                    position: 0.5
                    color: "transparent"
                }
                GradientStop {
                    position: 1.0
                    color: MColors.accent
                }
            }
        }
    }

    // =========================================================================
    // Use actual Marathon Status Bar component
    // =========================================================================
    MarathonStatusBar {
        id: statusBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        z: 100
    }

    // Page container
    SwipeView {
        id: swipeView
        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight
        anchors.leftMargin: MSpacing.xl
        anchors.rightMargin: MSpacing.xl
        anchors.bottomMargin: Math.round(170 * Constants.scaleFactor)
        currentIndex: oobeRoot.currentPage
        interactive: false
        clip: true

        // Page 0: Welcome
        Item {
            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: MSpacing.xxl

                Item {
                    width: parent.width
                    height: Math.round(180 * Constants.scaleFactor)

                    Image {
                        anchors.centerIn: parent
                        width: Math.min(parent.width * 0.45, Math.round(180 * Constants.scaleFactor))
                        height: width
                        source: "qrc:/images/marathon.png"
                        fillMode: Image.PreserveAspectFit
                        smooth: false  // Better performance
                        mipmap: false  // Better performance
                        asynchronous: true
                        cache: true

                        // Removed animations for better performance
                    }
                }

                Text {
                    text: "Welcome to Marathon OS"
                    font.pixelSize: MTypography.sizeXXLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: MColors.text
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Text {
                    text: "A modern, gesture-driven mobile shell for Linux"
                    font.pixelSize: MTypography.sizeLarge
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                Text {
                    text: "Let's get you set up"
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textTertiary
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                    topPadding: MSpacing.lg
                }
            }
        }

        // Page 1: WiFi
        Item {
            // Header row with title and skip button
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

                    // WiFi toggle - styled like settings app
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

                    // Available Networks Section
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

                        // Network List
                        Repeater {
                            model: NetworkManager.availableWifiNetworks

                            MCard {
                                width: parent.parent.width
                                height: MSpacing.touchTargetMedium
                                elevation: 2
                                interactive: true

                                onPressedChanged: {
                                    border.color = pressed ? MColors.accent : MColors.border;
                                }

                                // Use MCard's built-in onClicked signal instead of redundant MouseArea
                                onClicked: {
                                    Logger.info("OOBE", "WiFi network selected:", modelData.ssid);
                                    HapticService.light();
                                    wifiPasswordDialogLoader.show(modelData.ssid, modelData.strength, modelData.security, modelData.secured);
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: MSpacing.md
                                    spacing: MSpacing.md

                                    // Signal strength icon (proper signal bars, not opacity)
                                    Icon {
                                        name: {
                                            // Use proper signal bar icons based on strength
                                            if (modelData.strength === 0)
                                                return "wifi-zero";
                                            if (modelData.strength <= 33)
                                                return "wifi-low";     // 1-2 bars (weak)
                                            if (modelData.strength <= 66)
                                                return "wifi";         // 2-3 bars (good)
                                            return "wifi-high";                                   // 3-4 bars (excellent)
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

                                            // Show "Connected" for active network
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
                                                visible: !modelData.connected  // Hide separator for connected networks
                                            }

                                            Text {
                                                text: modelData.strength + "%"
                                                font.pixelSize: MTypography.sizeSmall
                                                font.family: MTypography.fontFamily
                                                color: MColors.textSecondary
                                                visible: !modelData.connected  // Hide strength % for connected networks (icon is enough)
                                            }

                                            Icon {
                                                name: "lock"
                                                size: Math.round(16 * Constants.scaleFactor)
                                                color: MColors.textTertiary
                                                visible: modelData.secured && !modelData.connected  // Hide lock for connected networks
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    // Checkmark for connected network
                                    Icon {
                                        name: "check-circle"
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

        // Page 2: Time & Date
        Item {
            // Header row with title
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
                                        HapticService.light();
                                    }
                                }

                                MButton {
                                    text: "24h"
                                    variant: SettingsManagerCpp.timeFormat === "24h" ? "primary" : "default"
                                    height: MSpacing.touchTargetSmall
                                    onClicked: {
                                        SettingsManagerCpp.timeFormat = "24h";
                                        HapticService.light();
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

        // Page 3: Gestures
        Item {
            // Header row with title
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
                                icon: "chevron-up",
                                title: "Swipe Up",
                                description: "From bottom edge to open app grid"
                            },
                            {
                                icon: "chevron-down",
                                title: "Swipe Down",
                                description: "From top edge to open quick settings"
                            },
                            {
                                icon: "chevron-right",
                                title: "Swipe Right",
                                description: "From left edge to open Hub"
                            },
                            {
                                icon: "grid",
                                title: "Pinch In",
                                description: "In app grid to open task switcher"
                            },
                            {
                                icon: "chevrons-up",
                                title: "Swipe Sideways",
                                description: "Navigate between pages"
                            }
                        ]

                        MCard {
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

        // Page 4: Complete
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
                        name: "check-circle"
                        size: MTypography.sizeXLarge
                        color: MColors.text
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
            }
        }
    }

    // =========================================================================
    // Navigation buttons
    // =========================================================================
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
                    HapticService.light();
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
            onClicked: {
                HapticService.light();
                if (oobeRoot.currentPage < oobeRoot.pages.length - 1) {
                    oobeRoot.currentPage++;
                } else {
                    SettingsManagerCpp.firstRunComplete = true;
                    oobeRoot.setupComplete();
                }
            }
        }
    }

    // =========================================================================
    // Page indicators - styled like shell
    // =========================================================================
    Row {
        id: pageIndicatorRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: navBar.top
        anchors.bottomMargin: MSpacing.xxl
        spacing: MSpacing.md
        height: Math.round(20 * Constants.scaleFactor) // Fixed height for vertical alignment

        Repeater {
            model: oobeRoot.pages.length

            Rectangle {
                width: oobeRoot.currentPage === index ? Math.round(20 * Constants.scaleFactor) : Math.round(12 * Constants.scaleFactor)
                height: oobeRoot.currentPage === index ? Math.round(20 * Constants.scaleFactor) : Math.round(12 * Constants.scaleFactor)
                radius: oobeRoot.currentPage === index ? Math.round(10 * Constants.scaleFactor) : Math.round(6 * Constants.scaleFactor)
                color: oobeRoot.currentPage === index ? MColors.accent : MColors.textTertiary
                opacity: oobeRoot.currentPage === index ? 1.0 : 0.5
                anchors.verticalCenter: parent.verticalCenter // Vertically align all dots
            }
        }
    }

    // Skip button - positioned in top right of page content area
    MButton {
        anchors.top: swipeView.top
        anchors.topMargin: MSpacing.lg
        anchors.right: parent.right
        anchors.rightMargin: MSpacing.xl
        text: "Skip"
        variant: "default"
        visible: oobeRoot.currentPage < oobeRoot.pages.length - 1
        z: 200
        onClicked: {
            SettingsManagerCpp.firstRunComplete = true;
            HapticService.light();
            oobeRoot.setupComplete();
        }
    }

    // =========================================================================
    // Use actual Marathon Nav Bar component
    // =========================================================================
    MarathonNavBar {
        id: navBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 100

        // Hook up nav bar back gesture to OOBE navigation
        onSwipeLeft: {
            if (oobeRoot.currentPage > 0) {
                HapticService.light();
                oobeRoot.currentPage--;
            }
        }

        onSwipeRight: {
            if (oobeRoot.currentPage < oobeRoot.pages.length - 1) {
                HapticService.light();
                oobeRoot.currentPage++;
            }
        }
    }

    // WiFi password dialog
    Loader {
        id: wifiPasswordDialogLoader
        anchors.fill: parent
        active: false
        sourceComponent: WiFiPasswordDialog {
            onConnectRequested: (ssid, password) => {
                Logger.info("OOBE", "Connecting to WiFi:", ssid);
                NetworkManager.connectToWifi(ssid, password);
            }
            onCancelled: {
                Logger.info("OOBE", "WiFi connection cancelled");
            }
        }

        function show(ssid, strength, security, secured) {
            active = true;
            if (item)
                item.show(ssid, strength, security, secured);
        }
    }

    Connections {
        target: NetworkManager
        function onConnectionSuccess() {
            if (wifiPasswordDialogLoader.active && wifiPasswordDialogLoader.item) {
                wifiPasswordDialogLoader.item.hide();
                wifiPasswordDialogLoader.active = false;
            }
            HapticService.medium();
        }
        function onConnectionFailed(message) {
            if (wifiPasswordDialogLoader.active && wifiPasswordDialogLoader.item) {
                wifiPasswordDialogLoader.item.showError(message);
            }
        }
    }

    Timer {
        interval: 1000
        running: SystemStatusStore.isWifiOn
        repeat: false
        onTriggered: {
            if (SystemStatusStore.isWifiOn)
                NetworkManager.scanWifi();
        }
    }
}
