import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Navigation
import "pages"

MApp {
    id: phoneApp
    appId: "phone"
    appName: "Phone"
    appIcon: "assets/icon.svg"
    property bool hasContactsPermission: false
    property var contacts: hasContactsPermission && typeof ContactsManager !== 'undefined' ? ContactsManager.contacts : []
    property var callHistory: typeof CallHistoryManager !== 'undefined' ? CallHistoryManager.history : []

    property string dialedNumber: ""
    property bool inCall: typeof TelephonyService !== 'undefined' && TelephonyService.callState !== "idle"

    property int editingContactId: -1
    property string editingContactName: ""
    property string editingContactPhone: ""
    property string editingContactEmail: ""

    // Check contacts permission on launch
    Component.onCompleted: {
        if (typeof TelephonyService !== 'undefined' && TelephonyService.callState === "active") {
            var number = TelephonyService.activeNumber;
            var contactName = resolveContactName(number);
            activeCallPage.show(number, contactName);
            Logger.info("Phone", "Phone app opened with active call: " + contactName + " (" + number + ")");
        }

        // Check contacts permission
        if (typeof PermissionManager !== 'undefined') {
            if (PermissionManager.hasPermission(appId, "contacts")) {
                Logger.info("Phone", "Contacts permission already granted");
                hasContactsPermission = true;
            } else {
                Logger.info("Phone", "Requesting contacts permission");
                PermissionManager.requestPermission(appId, "contacts");
            }
        } else {
            Logger.warn("Phone", "PermissionManager not available, auto-granting");
            hasContactsPermission = true;
        }
    }

    // Listen for permission responses
    Connections {
        target: typeof PermissionManager !== 'undefined' ? PermissionManager : null

        function onPermissionGranted(grantedAppId, permission) {
            if (grantedAppId === appId && permission === "contacts") {
                Logger.info("Phone", "Contacts permission granted");
                hasContactsPermission = true;
            }
        }

        function onPermissionDenied(deniedAppId, permission) {
            if (deniedAppId === appId && permission === "contacts") {
                Logger.warn("Phone", "Contacts permission denied");
                hasContactsPermission = false;
            }
        }
    }

    Connections {
        target: typeof TelephonyService !== 'undefined' ? TelephonyService : null
        enabled: target !== null
        function onIncomingCall(number) {
            Logger.info("Phone", "Incoming call from: " + number);
            var contactName = resolveContactName(number);
            incomingCallScreen.show(number, contactName);
        }

        function onCallStateChanged(state) {
            Logger.info("Phone", "Call state changed: " + state);
            if (state === "idle") {
                // Call ended
                if (dialedNumber.length > 0) {
                    dialedNumber = "";
                }
                if (activeCallPage.visible) {
                    activeCallPage.hide();
                }
                if (incomingCallScreen.visible) {
                    incomingCallScreen.hide();
                }
            } else if (state === "active") {
                // Call answered - hide incoming screen, show active call screen
                if (incomingCallScreen.visible) {
                    incomingCallScreen.hide();
                }
                if (!activeCallPage.visible && typeof TelephonyService !== 'undefined') {
                    var number = TelephonyService.activeNumber;
                    var contactName = resolveContactName(number);
                    activeCallPage.show(number, contactName);
                }
            }
        }
    }

    function resolveContactName(number) {
        for (var i = 0; i < contacts.length; i++) {
            if (contacts[i].phone === number) {
                return contacts[i].name;
            }
        }
        return "Unknown";
    }

    function formatTimestamp(timestamp) {
        var now = Date.now();
        var diff = now - timestamp;
        var minutes = Math.floor(diff / (1000 * 60));
        var hours = Math.floor(diff / (1000 * 60 * 60));
        var days = Math.floor(diff / (1000 * 60 * 60 * 24));

        if (minutes < 60)
            return minutes + "m";
        if (hours < 24)
            return hours + "h";
        return days + "d";
    }

    function formatDuration(seconds) {
        var minutes = Math.floor(seconds / 60);
        var remainingSeconds = seconds % 60;
        return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds;
    }

    function addDigit(digit) {
        dialedNumber += digit;
        HapticService.light();
    }

    function deleteDigit() {
        if (dialedNumber.length > 0) {
            dialedNumber = dialedNumber.slice(0, -1);
            HapticService.light();
        }
    }

    function clearNumber() {
        dialedNumber = "";
        HapticService.light();
    }

    function makeCall() {
        if (dialedNumber.length > 0) {
            Logger.info("Phone", "Calling: " + dialedNumber);
            if (typeof TelephonyService !== 'undefined') {
                TelephonyService.dial(dialedNumber);
                var contactName = resolveContactName(dialedNumber);
                activeCallPage.show(dialedNumber, contactName);
            }
            HapticService.medium();
        }
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Column {
            anchors.fill: parent
            spacing: 0

            property int currentIndex: 0

            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentIndex

                // Dialer Page
                Rectangle {
                    color: MColors.background

                    Column {
                        anchors.fill: parent
                        anchors.margins: MSpacing.lg
                        spacing: MSpacing.lg

                        // Display
                        Rectangle {
                            width: parent.width
                            height: Constants.touchTargetLarge
                            color: MColors.surface
                            radius: Constants.borderRadiusSharp
                            border.width: Constants.borderWidthThin
                            border.color: MColors.border
                            antialiasing: Constants.enableAntialiasing

                            Text {
                                anchors.centerIn: parent
                                text: dialedNumber || "Enter number"
                                font.pixelSize: MTypography.sizeLarge
                                font.weight: Font.DemiBold
                                color: dialedNumber ? MColors.text : MColors.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // Keypad
                        Grid {
                            width: parent.width
                            height: parent.height - Constants.touchTargetLarge - Constants.touchTargetLarge - MSpacing.lg * 3
                            columns: 3
                            rows: 4
                            spacing: MSpacing.sm

                            Repeater {
                                model: [
                                    {
                                        digit: "1",
                                        letters: ""
                                    },
                                    {
                                        digit: "2",
                                        letters: "ABC"
                                    },
                                    {
                                        digit: "3",
                                        letters: "DEF"
                                    },
                                    {
                                        digit: "4",
                                        letters: "GHI"
                                    },
                                    {
                                        digit: "5",
                                        letters: "JKL"
                                    },
                                    {
                                        digit: "6",
                                        letters: "MNO"
                                    },
                                    {
                                        digit: "7",
                                        letters: "PQRS"
                                    },
                                    {
                                        digit: "8",
                                        letters: "TUV"
                                    },
                                    {
                                        digit: "9",
                                        letters: "WXYZ"
                                    },
                                    {
                                        digit: "*",
                                        letters: ""
                                    },
                                    {
                                        digit: "0",
                                        letters: "+"
                                    },
                                    {
                                        digit: "#",
                                        letters: ""
                                    }
                                ]

                                Rectangle {
                                    width: (parent.width - parent.spacing * 2) / 3
                                    height: (parent.height - parent.spacing * 3) / 4
                                    color: "transparent"
                                    border.width: Constants.borderWidthThin
                                    border.color: MColors.border
                                    radius: Constants.borderRadiusSharp
                                    antialiasing: Constants.enableAntialiasing

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: MSpacing.xs

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.digit
                                            font.pixelSize: MTypography.sizeXLarge
                                            font.weight: Font.Bold
                                            color: MColors.text
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.letters
                                            font.pixelSize: MTypography.sizeSmall
                                            color: MColors.textSecondary
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onPressed: {
                                            parent.color = MColors.surface;
                                            HapticService.light();
                                        }
                                        onReleased: {
                                            parent.color = "transparent";
                                        }
                                        onCanceled: {
                                            parent.color = "transparent";
                                        }
                                        onClicked: {
                                            addDigit(modelData.digit);
                                        }
                                    }
                                }
                            }
                        }

                        // Call/Delete buttons
                        Row {
                            width: parent.width
                            spacing: MSpacing.lg

                            Rectangle {
                                width: (parent.width - parent.spacing) / 2
                                height: Constants.touchTargetLarge
                                color: "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: MColors.border
                                radius: Constants.borderRadiusSharp
                                antialiasing: Constants.enableAntialiasing

                                Icon {
                                    anchors.centerIn: parent
                                    name: "delete"
                                    size: Constants.iconSizeLarge
                                    color: MColors.text
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        parent.color = MColors.surface;
                                        HapticService.light();
                                    }
                                    onReleased: {
                                        parent.color = "transparent";
                                    }
                                    onCanceled: {
                                        parent.color = "transparent";
                                    }
                                    onClicked: {
                                        deleteDigit();
                                    }
                                }
                            }

                            Rectangle {
                                width: (parent.width - parent.spacing) / 2
                                height: Constants.touchTargetLarge
                                color: MColors.accent
                                border.width: Constants.borderWidthMedium
                                border.color: MColors.accentDark
                                radius: Constants.borderRadiusSharp
                                antialiasing: Constants.enableAntialiasing

                                Icon {
                                    anchors.centerIn: parent
                                    name: "phone"
                                    size: Constants.iconSizeLarge
                                    color: MColors.text
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        parent.scale = 0.9;
                                        HapticService.medium();
                                    }
                                    onReleased: {
                                        parent.scale = 1.0;
                                    }
                                    onCanceled: {
                                        parent.scale = 1.0;
                                    }
                                    onClicked: {
                                        makeCall();
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 100
                                    }
                                }
                            }
                        }
                    }
                }

                // Call History Page
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    topMargin: MSpacing.md

                    model: callHistory

                    delegate: Item {
                        width: ListView.view.width
                        height: card.height + MSpacing.md

                        MCard {
                            id: card
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: MSpacing.md
                            anchors.rightMargin: MSpacing.md
                            elevation: 1
                            interactive: true

                            onClicked: {
                                dialedNumber = modelData.phone;
                                parent.parent.parent.parent.currentIndex = 0;
                            }

                            Row {
                                width: parent.parent.width - MSpacing.md * 2
                                height: MSpacing.touchTargetLarge
                                spacing: MSpacing.md

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData.type === "outgoing" ? "phone-outgoing" : modelData.type === "incoming" ? "phone-incoming" : "phone-missed"
                                    size: 20
                                    color: modelData.type === "missed" ? MColors.error : MColors.accent
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.spacing * 2 - 20 * 2
                                    spacing: MSpacing.xs

                                    Text {
                                        width: parent.width
                                        text: modelData.contactName
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: MTypography.weightDemiBold
                                        font.family: MTypography.fontFamily
                                        color: MColors.text
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        spacing: MSpacing.sm

                                        Text {
                                            text: modelData.phone
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            color: MColors.textSecondary
                                        }

                                        Text {
                                            text: "•"
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            color: MColors.textSecondary
                                        }

                                        Text {
                                            text: formatDuration(modelData.duration)
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            color: MColors.textSecondary
                                        }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: formatTimestamp(modelData.timestamp)
                                    font.pixelSize: MTypography.sizeSmall
                                    font.family: MTypography.fontFamily
                                    color: MColors.textTertiary
                                }
                            }
                        }
                    }
                }

                // Contacts Page
                Rectangle {
                    color: MColors.background

                    ListView {
                        id: contactsList
                        anchors.fill: parent
                        clip: true
                        topMargin: MSpacing.md

                        model: contacts

                        delegate: Item {
                            width: contactsList.width
                            height: contactCard.height + MSpacing.md

                            MCard {
                                id: contactCard
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: MSpacing.md
                                anchors.rightMargin: MSpacing.md
                                elevation: 1
                                interactive: true

                                onClicked: {
                                    editingContactId = modelData.id || -1;
                                    editingContactName = modelData.name || "";
                                    editingContactPhone = modelData.phone || "";
                                    editingContactEmail = modelData.email || "";
                                    contactEditorLoader.active = true;
                                }

                                Row {
                                    width: parent.parent.width - MSpacing.md * 2
                                    height: MSpacing.touchTargetLarge
                                    spacing: MSpacing.md

                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "user"
                                        size: 20
                                        color: MColors.accent
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - parent.spacing * 2 - 20 * 2
                                        spacing: MSpacing.xs

                                        Text {
                                            width: parent.width
                                            text: modelData.name
                                            font.pixelSize: MTypography.sizeBody
                                            font.weight: MTypography.weightDemiBold
                                            font.family: MTypography.fontFamily
                                            color: MColors.text
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.phone
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            color: MColors.textSecondary
                                        }
                                    }

                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: modelData.favorite ? "star" : "star-off"
                                        size: 20
                                        color: modelData.favorite ? MColors.accent : MColors.textTertiary
                                    }
                                }
                            }
                        }
                    }

                    MIconButton {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: MSpacing.lg
                        iconName: "plus"
                        iconSize: 28
                        variant: "primary"
                        shape: "circular"
                        onClicked: {
                            Logger.info("Phone", "Add new contact");
                            editingContactId = -1;
                            editingContactName = "";
                            editingContactPhone = "";
                            editingContactEmail = "";
                            contactEditorLoader.active = true;
                        }
                    }
                }
            }

            MTabBar {
                id: tabBar
                width: parent.width
                activeTab: parent.currentIndex

                tabs: [
                    {
                        label: "Dial",
                        icon: "phone"
                    },
                    {
                        label: "History",
                        icon: "clock"
                    },
                    {
                        label: "Contacts",
                        icon: "users"
                    }
                ]

                onTabSelected: index => {
                    HapticService.light();
                    tabBar.parent.currentIndex = index;
                }
            }
        }

        Loader {
            id: contactEditorLoader
            anchors.fill: parent
            active: false
            z: 999

            sourceComponent: Component {
                ContactEditorPage {
                    contactId: phoneApp.editingContactId
                    contactName: phoneApp.editingContactName
                    contactPhone: phoneApp.editingContactPhone
                    contactEmail: phoneApp.editingContactEmail

                    onContactSaved: {
                        contactEditorLoader.active = false;
                    }
                    onCancelled: {
                        contactEditorLoader.active = false;
                    }
                }
            }
        }

        IncomingCallScreen {
            id: incomingCallScreen
            anchors.fill: parent
        }

        ActiveCallPage {
            id: activeCallPage
            anchors.fill: parent
        }
    }
}
