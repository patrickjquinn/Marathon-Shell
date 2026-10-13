pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// First-run setup, drawn as Sailfish's setup wizard: each step is a page
// on the dimmed ambience with a highlight-coloured heading.
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

    // Short / square panels (HyperPixel 4.0 Square 720×720).
    readonly property bool compactLayout: Constants.isSquareScreen || Constants.screenHeight < 800
    // Measured from the Back/Next row and nav bar so it tracks every scale.
    readonly property real swipeBottomInset: navigationRow.height + navBar.height + Silica.Theme.paddingLarge * 2

    signal setupComplete

    component StepTitle: Silica.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Silica.Theme.horizontalPageMargin
        Layout.rightMargin: Silica.Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        color: Silica.Theme.highlightColor
        font.pixelSize: Silica.Theme.fontSizeLarge
    }

    component StepBody: Silica.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Silica.Theme.horizontalPageMargin
        Layout.rightMargin: Silica.Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        color: Silica.Theme.secondaryHighlightColor
        font.pixelSize: Silica.Theme.fontSizeSmall
    }

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

    KeelAmbienceBackground {
        width: oobeRoot.width
        height: oobeRoot.height
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light

        // Breaks the HyperPixel Square's 18 bpp banding.
        Image {
            anchors.fill: parent
            source: "file:///usr/share/marathon-shell/wallpapers/dither-noise.png"
            fillMode: Image.Tile
            smooth: false
            opacity: 0.04
            visible: DeviceProfile.panelDither
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
        anchors.topMargin: topChrome.height + statusBar.height
        anchors.bottomMargin: Math.round(oobeRoot.swipeBottomInset)
        currentIndex: oobeRoot.currentPage
        interactive: false
        clip: true

        Item {
            clip: true

            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: Silica.Theme.paddingLarge

                MMarathonMark {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: Math.round((oobeRoot.compactLayout ? 180 : 220) * Constants.scaleFactor)
                    glow: false
                }

                Silica.Label {
                    x: Silica.Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    text: "Welcome"
                    color: Silica.Theme.highlightColor
                    font.pixelSize: Silica.Theme.fontSizeExtraLarge
                    horizontalAlignment: Text.AlignHCenter
                }

                Silica.Label {
                    x: Silica.Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    text: "A modern, gesture-driven mobile shell.\nLet's get you set up."
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: Silica.Theme.fontSizeMedium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }

        Item {
            id: scalePage

            clip: true

            readonly property var scaleFactors: [0.75, 0.9, 1.0, 1.1, 1.25, 1.4, 1.5]

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Silica.Theme.paddingLarge
                spacing: Silica.Theme.paddingMedium

                StepTitle {
                    text: "Choose display size"
                }

                StepBody {
                    text: "Make text and icons easier to read. 100% is the default, and you can change this anytime."
                }

                Silica.SectionHeader {
                    Layout.fillWidth: true
                    Layout.leftMargin: Silica.Theme.horizontalPageMargin
                    Layout.rightMargin: Silica.Theme.horizontalPageMargin
                    text: "Preview"
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Column {
                        x: Silica.Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Silica.Theme.paddingSmall

                        Silica.Label {
                            width: parent.width
                            text: "Sample"
                            color: Silica.Theme.primaryColor
                            font.pixelSize: Silica.Theme.fontSizeExtraLarge
                            truncationMode: Silica.TruncationMode.Fade
                        }

                        Silica.Label {
                            width: parent.width
                            text: "The quick brown fox jumps over the lazy dog."
                            color: Silica.Theme.secondaryColor
                            font.pixelSize: Silica.Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Silica.Theme.horizontalPageMargin
                    Layout.rightMargin: Silica.Theme.horizontalPageMargin
                    spacing: 0

                    Repeater {
                        model: scalePage.scaleFactors

                        Silica.BackgroundItem {
                            id: scaleChoice

                            required property real modelData

                            readonly property bool selected: Math.abs(Constants.userScaleFactor - modelData) < 0.001

                            Layout.fillWidth: true
                            Layout.preferredHeight: Silica.Theme.itemSizeSmall
                            onClicked: {
                                HapticManager.light();
                                SettingsManagerCpp.userScaleFactor = scaleChoice.modelData;
                            }

                            Accessible.role: Accessible.RadioButton
                            Accessible.name: scaleLabel.text
                            Accessible.checked: scaleChoice.selected

                            Column {
                                anchors.centerIn: parent
                                width: parent.width

                                Silica.Label {
                                    id: scaleLabel

                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Math.round(scaleChoice.modelData * 100) + "%"
                                    font.pixelSize: Silica.Theme.fontSizeSmall
                                    fontSizeMode: Text.HorizontalFit
                                    minimumPixelSize: Silica.Theme.fontSizeTiny
                                    color: scaleChoice.selected || scaleChoice.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                                }

                                GlyphIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: "check"
                                    size: Silica.Theme.iconSizeExtraSmall
                                    color: Silica.Theme.highlightColor
                                    opacity: scaleChoice.selected ? 1 : 0
                                }
                            }
                        }
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
                anchors.topMargin: Silica.Theme.paddingLarge
                spacing: Silica.Theme.paddingMedium

                StepTitle {
                    text: "Connect to a network"
                }

                StepBody {
                    text: SystemStatusStore.isWifiOn ? "Pick a network, or continue without one." : "Turn WiFi on to see nearby networks."
                }

                Silica.TextSwitch {
                    Layout.fillWidth: true
                    visible: !SystemStatusStore.isWifiOn
                    text: "WiFi"
                    checked: SystemStatusStore.isWifiOn
                    automaticCheck: false
                    onClicked: SystemControlStore.toggleWifi()
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Silica.Theme.itemSizeSmall
                    visible: SystemStatusStore.isWifiOn

                    Silica.IconButton {
                        id: rescanButton

                        anchors.left: parent.left
                        anchors.leftMargin: Silica.Theme.horizontalPageMargin - Silica.Theme.paddingMedium
                        anchors.verticalCenter: parent.verticalCenter
                        icon.source: "image://theme/icon-m-refresh"
                        Accessible.name: "Rescan networks"
                        onClicked: {
                            HapticManager.light();
                            wifiPage.firstScanDone = false;
                            NetworkManagerCpp.scanWifi();
                        }
                    }

                    Silica.SectionHeader {
                        anchors.left: rescanButton.right
                        anchors.right: parent.right
                        anchors.rightMargin: Silica.Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Networks"
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: SystemStatusStore.isWifiOn

                    Silica.BusyIndicator {
                        anchors.centerIn: parent
                        size: Silica.BusyIndicatorSize.Medium
                        running: oobeRoot.visible && !wifiPage.firstScanDone
                        visible: !wifiPage.firstScanDone
                    }

                    Column {
                        x: Silica.Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Silica.Theme.paddingMedium
                        visible: wifiPage.firstScanDone && NetworkManagerCpp.availableNetworks.length === 0

                        Silica.Label {
                            width: parent.width
                            text: "No networks found"
                            color: Silica.Theme.secondaryHighlightColor
                            font.pixelSize: Silica.Theme.fontSizeExtraLarge
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                        }

                        Silica.Label {
                            width: parent.width
                            text: "Move closer to a router, or tap refresh."
                            color: Silica.Theme.secondaryColor
                            font.pixelSize: Silica.Theme.fontSizeMedium
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
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

                            Repeater {
                                model: NetworkManagerCpp.availableNetworks

                                Silica.BackgroundItem {
                                    id: networkRow

                                    required property var modelData
                                    required property int index

                                    readonly property bool isPending: wifiPage.pendingSsid === modelData.ssid
                                    readonly property bool rowEnabled: !modelData.connected && wifiPage.pendingSsid === ""
                                    readonly property bool lit: modelData.connected || highlighted

                                    width: parent.width
                                    height: Math.max(Silica.Theme.itemSizeSmall, networkText.height + 2 * Silica.Theme.paddingMedium)
                                    enabled: networkRow.rowEnabled
                                    onClicked: {
                                        HapticManager.light();
                                        if (networkRow.modelData.secured) {
                                            wifiPasswordDialogLoader.show(networkRow.modelData.ssid, networkRow.modelData.strength, networkRow.modelData.security, networkRow.modelData.secured);
                                        } else {
                                            wifiPage.pendingSsid = networkRow.modelData.ssid;
                                            NetworkManagerCpp.connectToNetwork(networkRow.modelData.ssid, "");
                                        }
                                    }

                                    GlyphIcon {
                                        id: strengthIcon

                                        x: Silica.Theme.horizontalPageMargin
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: {
                                            const s = networkRow.modelData.strength;
                                            if (s >= 75)
                                                return "wifi-high";
                                            if (s >= 50)
                                                return "wifi-medium";
                                            if (s >= 25)
                                                return "wifi-low";
                                            return "wifi-none";
                                        }
                                        size: Silica.Theme.iconSizeSmall
                                        color: networkRow.lit ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                                    }

                                    Column {
                                        id: networkText

                                        anchors.left: strengthIcon.right
                                        anchors.leftMargin: Silica.Theme.paddingLarge
                                        anchors.right: networkTrail.left
                                        anchors.rightMargin: Silica.Theme.paddingMedium
                                        anchors.verticalCenter: parent.verticalCenter

                                        Silica.Label {
                                            width: parent.width
                                            text: networkRow.modelData.ssid
                                            color: networkRow.lit ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                                            truncationMode: Silica.TruncationMode.Fade
                                        }

                                        Silica.Label {
                                            visible: networkRow.modelData.connected || networkRow.isPending
                                            text: networkRow.isPending ? "Connecting…" : "Connected"
                                            color: networkRow.isPending ? Silica.Theme.secondaryColor : Silica.Theme.secondaryHighlightColor
                                            font.pixelSize: Silica.Theme.fontSizeExtraSmall
                                        }
                                    }

                                    Row {
                                        id: networkTrail

                                        anchors.right: parent.right
                                        anchors.rightMargin: Silica.Theme.horizontalPageMargin
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Silica.Theme.paddingSmall

                                        Silica.BusyIndicator {
                                            anchors.verticalCenter: parent.verticalCenter
                                            size: Silica.BusyIndicatorSize.ExtraSmall
                                            running: networkRow.isPending
                                            visible: running
                                        }

                                        GlyphIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: networkRow.modelData.secured && !networkRow.isPending && !networkRow.modelData.connected
                                            name: "lock"
                                            size: Silica.Theme.iconSizeExtraSmall
                                            color: Silica.Theme.secondaryColor
                                        }

                                        GlyphIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: networkRow.modelData.connected
                                            name: "check"
                                            size: Silica.Theme.iconSizeExtraSmall
                                            color: Silica.Theme.highlightColor
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Silica.BackgroundItem {
                    id: joinOther

                    Layout.fillWidth: true
                    Layout.preferredHeight: Silica.Theme.itemSizeSmall
                    visible: SystemStatusStore.isWifiOn && wifiPage.firstScanDone
                    onClicked: {
                        HapticManager.light();
                        wifiPasswordDialogLoader.show("", 0, "WPA2", true);
                    }

                    Silica.Label {
                        x: Silica.Theme.horizontalPageMargin
                        width: parent.width - 2 * x
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Join other network…"
                        color: joinOther.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                        truncationMode: Silica.TruncationMode.Fade
                    }
                }
            }
        }

        Item {
            id: timezonePage

            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Silica.Theme.paddingLarge
                spacing: Silica.Theme.paddingMedium

                StepTitle {
                    text: "Time and date"
                }

                StepBody {
                    text: "Configure your time format preferences."
                }

                Silica.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Silica.Theme.horizontalPageMargin
                    Layout.rightMargin: Silica.Theme.horizontalPageMargin
                    Layout.topMargin: Silica.Theme.paddingLarge
                    text: SystemStatusStore.timeString
                    color: Silica.Theme.primaryColor
                    font.pixelSize: Silica.Theme.fontSizeHuge
                    font.family: Silica.Theme.fontFamilyHeading
                }

                Silica.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Silica.Theme.horizontalPageMargin
                    Layout.rightMargin: Silica.Theme.horizontalPageMargin
                    text: Qt.formatDate(new Date(), "dddd, MMMM d, yyyy")
                    color: Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeMedium
                    truncationMode: Silica.TruncationMode.Fade
                }

                Silica.SectionHeader {
                    Layout.fillWidth: true
                    Layout.leftMargin: Silica.Theme.horizontalPageMargin
                    Layout.rightMargin: Silica.Theme.horizontalPageMargin
                    text: "Time format"
                }

                Column {
                    Layout.fillWidth: true

                    Repeater {
                        model: [
                            {
                                "value": "12h",
                                "label": "12-hour"
                            },
                            {
                                "value": "24h",
                                "label": "24-hour"
                            }
                        ]

                        Silica.BackgroundItem {
                            id: formatChoice

                            required property var modelData

                            readonly property bool selected: SettingsManagerCpp.timeFormat === modelData.value

                            width: parent.width
                            height: Silica.Theme.itemSizeSmall
                            onClicked: {
                                SettingsManagerCpp.timeFormat = formatChoice.modelData.value;
                                HapticManager.light();
                            }

                            Silica.Label {
                                x: Silica.Theme.horizontalPageMargin
                                width: parent.width - 2 * x
                                anchors.verticalCenter: parent.verticalCenter
                                text: formatChoice.modelData.label
                                color: formatChoice.selected || formatChoice.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                            }

                            GlyphIcon {
                                anchors.right: parent.right
                                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                                anchors.verticalCenter: parent.verticalCenter
                                visible: formatChoice.selected
                                name: "check"
                                size: Silica.Theme.iconSizeExtraSmall
                                color: Silica.Theme.highlightColor
                            }
                        }
                    }
                }

                Silica.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Silica.Theme.horizontalPageMargin
                    Layout.rightMargin: Silica.Theme.horizontalPageMargin
                    text: "The clock sets itself over the network. Choose your time zone any time in Settings → Date & Time."
                    color: Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    wrapMode: Text.Wrap
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        Item {
            id: gesturesPage

            clip: true

            // One gesture per sub-page; Next steps through them.
            property int currentCoachmark: 0
            readonly property var coachmarks: [
                {
                    "icon": "chevron-left",
                    "title": "Back",
                    "body": "Drag the pill at the bottom of the screen to the left to go back.",
                    "direction": "left",
                    "source": "pill"
                },
                {
                    "icon": "chevron-right",
                    "title": "Forward",
                    "body": "Drag the pill to the right to go forward again.",
                    "direction": "right",
                    "source": "pill"
                },
                {
                    "icon": "chevron-up",
                    "title": "Home and open apps",
                    "body": "Flick the pill up to go home. Drag it further up to see your open apps.",
                    "direction": "up",
                    "source": "pill"
                },
                {
                    "icon": "chevron-down",
                    "title": "Quick Settings",
                    "body": "Drag the pill down for Wi-Fi, brightness and Do Not Disturb.",
                    "direction": "down",
                    "source": "pill"
                },
                {
                    "icon": "chevron-right",
                    "title": "Hub",
                    "body": "Swipe in from the left edge of the screen to peek at the Hub — messages, notifications and calls.",
                    "direction": "right",
                    "source": "edge"
                },
                {
                    "icon": "check-circle",
                    "title": "You're set",
                    "body": "These gestures work everywhere in Marathon. Tap Next to continue.",
                    "direction": "none",
                    "source": "none"
                }
            ]

            function stepForward() {
                if (currentCoachmark === coachmarks.length - 1)
                    return false;
                currentCoachmark++;
                return true;
            }

            function stepBack() {
                if (currentCoachmark === 0)
                    return false;
                currentCoachmark--;
                return true;
            }

            Silica.Label {
                id: gesturesHeader

                anchors.top: parent.top
                anchors.topMargin: Silica.Theme.paddingLarge
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                text: "Learn the gestures"
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeLarge
                wrapMode: Text.Wrap
            }

            Silica.PageIndicator {
                id: coachmarkDots

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: gesturesHeader.bottom
                anchors.topMargin: Silica.Theme.paddingMedium
                count: gesturesPage.coachmarks.length
                currentIndex: gesturesPage.currentCoachmark
            }

            StackLayout {
                id: coachmarkStack

                anchors.top: coachmarkDots.bottom
                anchors.topMargin: Silica.Theme.paddingLarge
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Silica.Theme.paddingLarge
                currentIndex: gesturesPage.currentCoachmark

                Repeater {
                    model: gesturesPage.coachmarks

                    delegate: Item {
                        id: coachmarkDelegate

                        required property var modelData
                        required property int index

                        Column {
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: Silica.Theme.paddingLarge

                            Item {
                                width: Silica.Theme.itemSizeHuge
                                height: Silica.Theme.itemSizeHuge
                                anchors.horizontalCenter: parent.horizontalCenter

                                // The screen's left edge, for the Hub peek.
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Constants.spacingXSmall
                                    height: parent.height
                                    radius: Constants.borderRadiusSharp
                                    color: Silica.Theme.secondaryColor
                                    visible: coachmarkDelegate.modelData.source === "edge"
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Silica.Theme.paddingMedium

                                    transform: Translate {
                                        id: coachmarkNudge

                                        x: 0
                                        y: 0
                                    }

                                    GlyphIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        name: coachmarkDelegate.modelData.icon
                                        size: Silica.Theme.iconSizeExtraLarge
                                        color: Silica.Theme.highlightColor
                                    }

                                    // Drawn like the nav bar's pill.
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Constants.cardBannerHeight
                                        height: Constants.spacingXSmall
                                        radius: Constants.borderRadiusSharp
                                        color: Silica.Theme.primaryColor
                                        visible: coachmarkDelegate.modelData.source === "pill"
                                    }
                                }

                                SequentialAnimation {
                                    // Gated on visibility: the OOBE stays instantiated after setup.
                                    running: oobeRoot.visible && gesturesPage.currentCoachmark === coachmarkDelegate.index && coachmarkDelegate.modelData.direction !== "none"
                                    loops: Animation.Infinite

                                    NumberAnimation {
                                        target: coachmarkNudge
                                        property: (coachmarkDelegate.modelData.direction === "left" || coachmarkDelegate.modelData.direction === "right") ? "x" : "y"
                                        from: 0
                                        to: {
                                            const amount = Silica.Theme.paddingLarge * 2;
                                            if (coachmarkDelegate.modelData.direction === "up")
                                                return -amount;
                                            if (coachmarkDelegate.modelData.direction === "down")
                                                return amount;
                                            if (coachmarkDelegate.modelData.direction === "left")
                                                return -amount;
                                            if (coachmarkDelegate.modelData.direction === "right")
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
                                        property: (coachmarkDelegate.modelData.direction === "left" || coachmarkDelegate.modelData.direction === "right") ? "x" : "y"
                                        to: 0
                                        duration: 500
                                        easing.type: Easing.OutCubic
                                    }
                                    PauseAnimation {
                                        duration: 400
                                    }
                                }
                            }

                            Silica.Label {
                                x: Silica.Theme.horizontalPageMargin
                                width: parent.width - 2 * x
                                text: coachmarkDelegate.modelData.title
                                color: Silica.Theme.primaryColor
                                font.pixelSize: Silica.Theme.fontSizeLarge
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }

                            Silica.Label {
                                x: Silica.Theme.horizontalPageMargin
                                width: parent.width - 2 * x
                                text: coachmarkDelegate.modelData.body
                                color: Silica.Theme.secondaryColor
                                font.pixelSize: Silica.Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }

        // Two-stage PIN setup (enter, then confirm) in the lock screen's style.
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
            readonly property real dotSize: Silica.Theme.paddingLarge
            readonly property real keySpacing: isCompact ? Silica.Theme.paddingMedium : Silica.Theme.paddingLarge

            // Design size; only an upper bound, see keyCellFit.
            readonly property real keyCellDesign: Math.round(keyCellBase * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
            readonly property real keyCellBase: isCompact ? 56 : 72

            // Height left for the four keypad rows below the header block.
            readonly property real keypadBudget: height - Math.round(216 * Constants.scaleFactor)
            readonly property real keyCellFit: Math.floor((keypadBudget - 3 * keySpacing) / 4)

            // Shrink to fit rather than clip; the 44 px floor is in device pixels on purpose.
            readonly property real scaledKeyCell: Math.max(44, Math.min(keyCellDesign, keyCellFit))

            // In MCircularIconButton's logical units, so glyphs follow the cell.
            readonly property real keySize: Math.max(20, scaledKeyCell / Constants.scaleFactor - 12)
            readonly property real keyGlyphSize: Math.max(11, Math.round(keySize * 0.5))

            // Header type is capped against the page so it can't starve the keypad.
            readonly property real headerTypeCap: Math.max(16, Math.round(height * 0.045))
            readonly property real titleSize: Math.min(Silica.Theme.fontSizeLarge, Math.round(headerTypeCap * 1.35))
            readonly property real subtitleSize: Math.min(Silica.Theme.fontSizeSmall, headerTypeCap)

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
                anchors.topMargin: Silica.Theme.paddingLarge
                anchors.leftMargin: Silica.Theme.horizontalPageMargin
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                spacing: passcodePage.isCompact ? Silica.Theme.paddingSmall : Silica.Theme.paddingMedium

                Silica.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: passcodePage.stage === "enter" ? "Create a passcode" : "Confirm passcode"
                    color: Silica.Theme.highlightColor
                    font.pixelSize: passcodePage.titleSize
                    horizontalAlignment: Text.AlignHCenter
                }

                Silica.Label {
                    Layout.fillWidth: true
                    text: passcodePage.stage === "enter" ? "Used to unlock your device after sleep." : "Re-enter the same passcode."
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: passcodePage.subtitleSize
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Silica.Theme.paddingLarge

                    Repeater {
                        model: passcodePage.maxLength

                        Rectangle {
                            required property int index

                            readonly property bool filled: index < passcodePage.currentPin.length

                            Layout.preferredWidth: passcodePage.dotSize
                            Layout.preferredHeight: passcodePage.dotSize
                            radius: width / 2
                            color: filled ? Silica.Theme.highlightColor : "transparent"
                            border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                            border.color: filled ? Silica.Theme.highlightColor : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }
                        }
                    }
                }

                Silica.Label {
                    Layout.fillWidth: true
                    visible: oobeRoot.passcodeError.length > 0
                    text: oobeRoot.passcodeError
                    color: Silica.Theme.errorColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
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
                            id: keyDelegate

                            required property string modelData

                            Layout.alignment: Qt.AlignCenter
                            Layout.preferredWidth: passcodePage.scaledKeyCell
                            Layout.preferredHeight: passcodePage.scaledKeyCell

                            MCircularIconButton {
                                anchors.centerIn: parent
                                width: passcodePage.scaledKeyCell
                                height: passcodePage.scaledKeyCell
                                text: keyDelegate.modelData
                                buttonSize: passcodePage.keySize
                                iconSize: passcodePage.keyGlyphSize
                                variant: "secondary"
                                onClicked: passcodePage.appendDigit(keyDelegate.modelData)
                            }
                        }
                    }

                    Item {
                        Layout.alignment: Qt.AlignCenter
                        Layout.preferredWidth: passcodePage.scaledKeyCell
                        Layout.preferredHeight: passcodePage.scaledKeyCell
                    }

                    Item {
                        Layout.alignment: Qt.AlignCenter
                        Layout.preferredWidth: passcodePage.scaledKeyCell
                        Layout.preferredHeight: passcodePage.scaledKeyCell

                        MCircularIconButton {
                            anchors.centerIn: parent
                            width: passcodePage.scaledKeyCell
                            height: passcodePage.scaledKeyCell
                            text: "0"
                            buttonSize: passcodePage.keySize
                            iconSize: passcodePage.keyGlyphSize
                            variant: "secondary"
                            onClicked: passcodePage.appendDigit("0")
                        }
                    }

                    Item {
                        Layout.alignment: Qt.AlignCenter
                        Layout.preferredWidth: passcodePage.scaledKeyCell
                        Layout.preferredHeight: passcodePage.scaledKeyCell

                        MCircularIconButton {
                            anchors.centerIn: parent
                            width: passcodePage.scaledKeyCell
                            height: passcodePage.scaledKeyCell
                            iconName: "delete"
                            a11yName: "Delete"
                            buttonSize: passcodePage.keySize
                            iconSize: Math.max(10, Math.round(passcodePage.keyGlyphSize * 0.85))
                            variant: "secondary"
                            disabled: passcodePage.currentPin.length === 0
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
                spacing: Silica.Theme.paddingLarge

                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "circle-check"
                    size: Silica.Theme.iconSizeExtraLarge
                    color: Silica.Theme.highlightColor
                }

                Silica.Label {
                    x: Silica.Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    text: "You're all set"
                    color: Silica.Theme.highlightColor
                    font.pixelSize: Silica.Theme.fontSizeExtraLarge
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Silica.Label {
                    x: Silica.Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    text: "Marathon is ready. Swipe up from the bottom of the screen to see your apps."
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: Silica.Theme.fontSizeMedium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Row {
        id: navigationRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: navBar.top
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        anchors.bottomMargin: Silica.Theme.paddingLarge
        spacing: Silica.Theme.paddingMedium

        Silica.Button {
            width: (parent.width - parent.spacing) / 2
            text: "Back"
            visible: oobeRoot.currentPage > 0
            onClicked: {
                HapticManager.light();
                if (oobeRoot.currentPage === 4 && gesturesPage.stepBack())
                    return;
                oobeRoot.currentPage--;
            }
        }

        Item {
            width: (parent.width - parent.spacing) / 2
            height: Silica.Theme.itemSizeExtraSmall
            visible: oobeRoot.currentPage === 0
        }

        Silica.Button {
            width: (parent.width - parent.spacing) / 2
            color: Silica.Theme.highlightColor
            text: {
                if (oobeRoot.currentPage === oobeRoot.pages.length - 1)
                    return "Get Started";
                if (oobeRoot.currentPage === 5)
                    return passcodePage.stage === "enter" ? "Next" : "Done";
                return "Next";
            }
            enabled: !(oobeRoot.currentPage === 5 && passcodePage.currentPin.length < passcodePage.requiredLength)
            onClicked: {
                HapticManager.light();
                if (oobeRoot.currentPage === 4 && gesturesPage.stepForward())
                    return;
                if (oobeRoot.currentPage === 5) {
                    passcodePage.tryAdvance();
                    return;
                }
                if (oobeRoot.currentPage < oobeRoot.pages.length - 1) {
                    oobeRoot.currentPage++;
                } else {
                    // Before firstRunComplete: setting it unloads the wizard.
                    oobeRoot.setupComplete();
                    SettingsManagerCpp.firstRunComplete = true;
                }
            }
        }
    }

    // Step dots, with Skip as a header text action on the right.
    Item {
        id: topChrome

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: statusBar.bottom
        height: Silica.Theme.itemSizeSmall
        z: 200

        Silica.PageIndicator {
            id: pageIndicatorRow

            anchors.centerIn: parent
            count: oobeRoot.pages.length
            currentIndex: oobeRoot.currentPage
        }

        Item {
            id: skipRow

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: skipButton.visible ? skipButton.width : 0

            Silica.BackgroundItem {
                id: skipButton

                width: skipLabel.implicitWidth + 2 * Silica.Theme.horizontalPageMargin
                height: parent.height
                // The passcode can't be skipped: there is no PAM password to fall back on.
                visible: oobeRoot.currentPage < 5
                Accessible.role: Accessible.Button
                Accessible.name: "Skip"
                onClicked: {
                    HapticManager.light();
                    oobeRoot.currentPage = 5;
                }

                Silica.Label {
                    id: skipLabel

                    anchors.centerIn: parent
                    text: "Skip"
                    color: skipButton.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                }
            }
        }
    }

    MarathonNavBar {
        id: navBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 100
        onSwipeLeft: {
            if (oobeRoot.currentPage === 4 && gesturesPage.stepBack()) {
                HapticManager.light();
                return;
            }
            if (oobeRoot.currentPage > 0) {
                HapticManager.light();
                oobeRoot.currentPage--;
            }
        }
        onSwipeRight: {
            if (oobeRoot.currentPage === 4 && gesturesPage.stepForward()) {
                HapticManager.light();
                return;
            }
            if (oobeRoot.currentPage === 5 && oobeRoot.newPasscode === "")
                return;
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
            // hide() animates out; wifiCleanupTimer unloads after it finishes.
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

        // Just past the dialog's 250 ms hide animation.
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
