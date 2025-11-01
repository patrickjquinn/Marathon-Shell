import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import "../MarathonUI/Theme"
import "../MarathonUI/Controls"
import MarathonUI.Theme

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

    signal setupComplete()

    // State management
    property int currentPage: 0
    readonly property var pages: [
        { id: "welcome", title: "Welcome" },
        { id: "wifi", title: "WiFi" },
        { id: "timezone", title: "Time" },
        { id: "gestures", title: "Gestures" },
        { id: "complete", title: "Done" }
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
                GradientStop { position: 0.0; color: MColors.accent }
                GradientStop { position: 0.5; color: "transparent" }
                GradientStop { position: 1.0; color: MColors.accent }
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
                    font.pixelSize: MTypography.sizeDisplay
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
                    font.pixelSize: MTypography.sizeDisplay
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
                    spacing: Constants.spacingXLarge
                    
                    Text {
                        text: "Connect to a wireless network to continue"
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                // WiFi toggle - styled like settings app
                Rectangle {
                    width: parent.width
                    height: Constants.appIconSize
                    radius: Constants.borderRadiusSmall
                    color: Qt.rgba(255, 255, 255, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(255, 255, 255, 0.08)

                    Icon {
                        id: wifiIcon
                        name: SystemStatusStore.isWifiOn ? "wifi" : "wifi-off"
                        size: Constants.iconSizeMedium
                        color: SystemStatusStore.isWifiOn ? MColors.accent : MColors.textSecondary
                        anchors.left: parent.left
                        anchors.leftMargin: Constants.spacingMedium
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.left: wifiIcon.right
                        anchors.leftMargin: Constants.spacingMedium
                        anchors.right: wifiToggleSwitch.left
                        anchors.rightMargin: Constants.spacingMedium
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Math.round(4 * Constants.scaleFactor)

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

                    MarathonToggle {
                        id: wifiToggleSwitch
                        checked: SystemStatusStore.isWifiOn
                        onToggled: SystemControlStore.toggleWifi()
                        anchors.right: parent.right
                        anchors.rightMargin: Constants.spacingMedium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                    // Available Networks Section
                    Column {
                        width: parent.width
                        spacing: Constants.spacingMedium
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

                            Rectangle {
                                width: parent.parent.width
                                height: Constants.appIconSize
                                radius: Constants.borderRadiusSmall
                                color: Qt.rgba(255, 255, 255, 0.04)
                                border.width: 1
                                border.color: mouseArea.pressed ? MColors.accent : Qt.rgba(255, 255, 255, 0.08)

                        Row {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            spacing: Constants.spacingMedium

                            // Signal strength icon
                            Icon {
                                name: "wifi"
                                size: Constants.iconSizeMedium
                                color: modelData.strength > 60 ? MColors.accent : 
                                       modelData.strength > 30 ? MColors.text : MColors.textSecondary
                                opacity: modelData.strength > 60 ? 1.0 :
                                         modelData.strength > 30 ? 0.7 : 0.4
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Math.round(4 * Constants.scaleFactor)
                                width: parent.width - Constants.iconSizeMedium - (Constants.spacingMedium * 2)

                                Text {
                                    text: modelData.ssid
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: Font.Medium
                                    font.family: MTypography.fontFamily
                                    color: MColors.text
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                Row {
                                    spacing: Constants.spacingSmall

                                    Text {
                                        text: modelData.security || "Open"
                                        font.pixelSize: MTypography.sizeSmall
                                        font.family: MTypography.fontFamily
                                        color: MColors.textSecondary
                                    }

                                    Text {
                                        text: "•"
                                        font.pixelSize: MTypography.sizeSmall
                                        color: MColors.textSecondary
                                    }

                                    Text {
                                        text: modelData.strength + "%"
                                        font.pixelSize: MTypography.sizeSmall
                                        font.family: MTypography.fontFamily
                                        color: MColors.textSecondary
                                    }

                                    Icon {
                                        name: "lock"
                                        size: Constants.iconSizeSmall
                                        color: MColors.textTertiary
                                        visible: modelData.secured
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }

                                MouseArea {
                                    id: mouseArea
                                    anchors.fill: parent
                                    onClicked: {
                                        HapticService.light()
                                        wifiPasswordDialogLoader.show(modelData.ssid, modelData.strength, modelData.security, modelData.secured)
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
                    font.pixelSize: MTypography.sizeDisplay
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
                    spacing: Constants.spacingXLarge
                    
                    Text {
                        text: "Configure your time format preferences"
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                Rectangle {
                    width: parent.width
                    height: Constants.lockScreenClockFontSize + (MSpacing.lg * 2)
                    radius: MRadius.lg
                    color: MColors.surface
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border

                    Column {
                        anchors.centerIn: parent
                        spacing: MSpacing.sm

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

                Rectangle {
                    width: parent.width
                    height: Constants.touchTargetMedium
                    radius: MRadius.md
                    color: MColors.surface
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border

                    Row {
                        anchors.fill: parent
                        anchors.margins: MSpacing.md
                        spacing: MSpacing.md

                        Icon {
                            name: "clock"
                            size: Constants.iconSizeMedium
                            color: MColors.text
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Time Format"
                            font.pixelSize: MTypography.sizeLarge
                            font.family: MTypography.fontFamily
                            color: MColors.text
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(200 * Constants.scaleFactor)
                        }

                        Row {
                            spacing: MSpacing.md
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                width: Constants.touchTargetMedium + MSpacing.md
                                height: Constants.touchTargetSmall
                                radius: MRadius.md
                                color: SettingsManagerCpp.timeFormat === "12h" ? MColors.accent : "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: SettingsManagerCpp.timeFormat === "12h" ? MColors.accent : MColors.border

                                Text {
                                    text: "12h"
                                    font.pixelSize: MTypography.sizeBody
                                    font.family: MTypography.fontFamily
                                    color: SettingsManagerCpp.timeFormat === "12h" ? MColors.background : MColors.text
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        SettingsManagerCpp.timeFormat = "12h"
                                        HapticService.light()
                                    }
                                }
                            }

                            Rectangle {
                                width: Constants.touchTargetMedium + MSpacing.md
                                height: Constants.touchTargetSmall
                                radius: MRadius.md
                                color: SettingsManagerCpp.timeFormat === "24h" ? MColors.accent : "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: SettingsManagerCpp.timeFormat === "24h" ? MColors.accent : MColors.border

                                Text {
                                    text: "24h"
                                    font.pixelSize: MTypography.sizeBody
                                    font.family: MTypography.fontFamily
                                    color: SettingsManagerCpp.timeFormat === "24h" ? MColors.background : MColors.text
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        SettingsManagerCpp.timeFormat = "24h"
                                        HapticService.light()
                                    }
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
                    font.pixelSize: MTypography.sizeDisplay
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
                    spacing: Constants.spacingXLarge

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
                            { icon: "chevron-up", title: "Swipe Up", description: "From bottom edge to open app grid" },
                            { icon: "chevron-down", title: "Swipe Down", description: "From top edge to open quick settings" },
                            { icon: "chevron-right", title: "Swipe Right", description: "From left edge to open Hub" },
                            { icon: "grid", title: "Pinch In", description: "In app grid to open task switcher" },
                            { icon: "chevrons-up", title: "Swipe Sideways", description: "Navigate between pages" }
                        ]

                        Rectangle {
                            width: parent.width
                            height: Constants.touchTargetLarge + MSpacing.md
                            radius: MRadius.md
                            color: MColors.surface
                            border.width: Constants.borderWidthThin
                            border.color: MColors.border

                            Row {
                                anchors.fill: parent
                                anchors.margins: MSpacing.md
                                spacing: MSpacing.lg

                                Rectangle {
                                    width: Constants.touchTargetMedium
                                    height: Constants.touchTargetMedium
                                    radius: MRadius.md
                                    color: MColors.accentSubtle
                                    anchors.verticalCenter: parent.verticalCenter

                                    Icon {
                                        name: modelData.icon
                                        size: Constants.iconSizeMedium
                                        color: MColors.accent
                                        anchors.centerIn: parent
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: MSpacing.xs
                                    width: parent.width - Constants.touchTargetMedium - (MSpacing.lg * 2)

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

                Rectangle {
                    width: Math.round(120 * Constants.scaleFactor)
                    height: Math.round(120 * Constants.scaleFactor)
                    radius: Math.round(60 * Constants.scaleFactor)
                    color: MColors.successSubtle
                    anchors.horizontalCenter: parent.horizontalCenter

                    Icon {
                        name: "check-circle"
                        size: Constants.iconSizeXLarge
                        color: MColors.success
                        anchors.centerIn: parent
                    }
                }

                Text {
                    text: "You're All Set!"
                    font.pixelSize: MTypography.sizeDisplay
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
    // Page indicators - styled like shell
    // =========================================================================
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: navigationRow.top
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

    // =========================================================================
    // Navigation buttons
    // =========================================================================
    Row {
        id: navigationRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: navBar.top
        anchors.leftMargin: MSpacing.xl
        anchors.rightMargin: MSpacing.xl
        anchors.bottomMargin: MSpacing.xl
        height: Constants.touchTargetMedium
        spacing: MSpacing.md

        Rectangle {
            width: (parent.width - MSpacing.md) / 2
            height: parent.height
            radius: MRadius.md
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MColors.border
            visible: oobeRoot.currentPage > 0

            Text {
                text: "Back"
                font.pixelSize: MTypography.sizeLarge
                font.family: MTypography.fontFamily
                color: MColors.text
                anchors.centerIn: parent
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (oobeRoot.currentPage > 0) {
                        HapticService.light()
                        oobeRoot.currentPage--
                    }
                }
            }
        }

        Item {
            width: (parent.width - MSpacing.md) / 2
            height: parent.height
            visible: oobeRoot.currentPage === 0
        }

        Rectangle {
            width: (parent.width - MSpacing.md) / 2
            height: parent.height
            radius: MRadius.md
            color: MColors.accent

            Text {
                text: oobeRoot.currentPage === oobeRoot.pages.length - 1 ? "Get Started" : "Next"
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Medium
                font.family: MTypography.fontFamily
                color: MColors.background
                anchors.centerIn: parent
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    HapticService.light()
                    if (oobeRoot.currentPage < oobeRoot.pages.length - 1) {
                        oobeRoot.currentPage++
                    } else {
                        SettingsManagerCpp.firstRunComplete = true
                        oobeRoot.setupComplete()
                    }
                }
            }
        }
    }

    // Skip button - positioned in top right of page content area
    Rectangle {
        anchors.top: swipeView.top
        anchors.topMargin: MSpacing.lg
        anchors.right: parent.right
        anchors.rightMargin: MSpacing.xl
        width: Math.round(60 * Constants.scaleFactor)
        height: Math.round(40 * Constants.scaleFactor)
        radius: MRadius.md
        color: "transparent"
        visible: oobeRoot.currentPage < oobeRoot.pages.length - 1
        z: 200

        Text {
            text: "Skip"
            font.pixelSize: MTypography.sizeBody
            font.weight: Font.Medium
            font.family: MTypography.fontFamily
            color: MColors.textTertiary
            anchors.centerIn: parent
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                SettingsManagerCpp.firstRunComplete = true
                HapticService.light()
                oobeRoot.setupComplete()
            }
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
                HapticService.light()
                oobeRoot.currentPage--
            }
        }
        
        onSwipeRight: {
            if (oobeRoot.currentPage < oobeRoot.pages.length - 1) {
                HapticService.light()
                oobeRoot.currentPage++
            }
        }
    }
    
    // WiFi password dialog
    Loader {
        id: wifiPasswordDialogLoader
        anchors.fill: parent
        active: false
        sourceComponent: WiFiPasswordDialog {
            onConnectRequested: (password) => {
                NetworkManager.connectToWifi(networkSsid, password)
            }
            onCancelled: {}
        }
        
        function show(ssid, strength, security, secured) {
            active = true
            if (item) item.show(ssid, strength, security, secured)
        }
    }
    
    Connections {
        target: NetworkManager
        function onConnectionSuccess() {
            if (wifiPasswordDialogLoader.active && wifiPasswordDialogLoader.item) {
                wifiPasswordDialogLoader.item.hide()
                wifiPasswordDialogLoader.active = false
            }
            HapticService.medium()
        }
        function onConnectionFailed(message) {
            if (wifiPasswordDialogLoader.active && wifiPasswordDialogLoader.item) {
                wifiPasswordDialogLoader.item.showError(message)
            }
        }
    }
    
    Timer {
        interval: 1000
        running: SystemStatusStore.isWifiOn
        repeat: false
        onTriggered: {
            if (SystemStatusStore.isWifiOn) NetworkManager.scanWifi()
        }
    }
}
