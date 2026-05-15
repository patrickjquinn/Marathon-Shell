import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

MApp {
    id: phoneApp

    property bool hasContactsPermission: false
    property var contacts: hasContactsPermission ? ContactsManager.contacts : []
    property var callHistory: CallHistoryManager.history
    property string dialedNumber: ""
    property bool inCall: TelephonyService.callState !== "idle"
    property int editingContactId: -1
    property string editingContactName: ""
    property string editingContactPhone: ""
    property string editingContactEmail: ""
    property var activeCallPageRef: null
    property var incomingCallScreenRef: null
    // True when launched from the lock screen via the "Emergency" affordance
    // (route="/emergency"). The UI hides contacts/history and only exposes a
    // dialer; the actual emergency-number gate is enforced by the modem.
    readonly property bool emergencyOnly: (typeof MARATHON_APP_ROUTE !== "undefined") && (MARATHON_APP_ROUTE === "/emergency")

    function resolveContactName(number) {
        for (var i = 0; i < contacts.length; i++) {
            if (contacts[i].phone === number)
                return contacts[i].name;
        }
        return "Unknown";
    }

    function formatTimestamp(timestamp) {
        var now = Date.now();
        var ts = Number(timestamp);
        if (Number.isFinite(ts) && ts > 0 && ts < 1e+11)
            ts = ts * 1000;

        if (!Number.isFinite(ts) || ts <= 0)
            return "";

        var diff = now - ts;
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
        var s = Number(seconds);
        if (!Number.isFinite(s) || s <= 0)
            return "";

        var minutes = Math.floor(s / 60);
        var remainingSeconds = Math.floor(s % 60);
        return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds;
    }

    function historyField(row, key, fallbackValue) {
        if (!row)
            return fallbackValue;

        var v = row[key];
        if (v === undefined || v === null || v === "")
            return fallbackValue;

        return v;
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
            // Emergency mode routes through dialEmergency() so the audit
            // trail captures the attempt with metadata (operator, modem
            // path) regardless of whether the modem accepts the number.
            if (emergencyOnly)
                TelephonyService.dialEmergency(dialedNumber);
            else
                TelephonyService.dial(dialedNumber);
            var contactName = emergencyOnly ? "Emergency" : resolveContactName(dialedNumber);
            if (activeCallPageRef)
                activeCallPageRef.show(dialedNumber, contactName);

            HapticService.medium();
        }
    }

    appId: "phone"
    appName: "Phone"
    appIcon: "assets/icon.svg"
    Component.onCompleted: {
        if (emergencyOnly)
            Logger.warn("Phone", "Launched in EMERGENCY ONLY mode -- contacts/history disabled");

        if (TelephonyService.callState === "active") {
            var number = TelephonyService.activeNumber;
            var contactName = resolveContactName(number);
            if (activeCallPageRef)
                activeCallPageRef.show(number, contactName);

            Logger.info("Phone", "Phone app opened with active call: " + contactName + " (" + number + ")");
        }
        if (emergencyOnly)
            // Skip contacts permission request -- emergency mode never reads contacts.
            return;

        if (PermissionManager.hasPermission(appId, "contacts")) {
            Logger.info("Phone", "Contacts permission already granted");
            hasContactsPermission = true;
        } else {
            Logger.info("Phone", "Requesting contacts permission");
            PermissionManager.requestPermission(appId, "contacts");
        }
    }

    Connections {
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

        target: PermissionManager
    }

    Connections {
        function onIncomingCall(number) {
            Logger.info("Phone", "Incoming call from: " + number);
            var contactName = resolveContactName(number);
            if (incomingCallScreenRef)
                incomingCallScreenRef.show(number, contactName);
        }

        function onCallStateChanged(state) {
            Logger.info("Phone", "Call state changed: " + state);
            if (state === "idle") {
                if (dialedNumber.length > 0)
                    dialedNumber = "";

                if (activeCallPageRef && activeCallPageRef.visible)
                    activeCallPageRef.hide();

                if (incomingCallScreenRef && incomingCallScreenRef.visible)
                    incomingCallScreenRef.hide();
            } else if (state === "active") {
                if (incomingCallScreenRef && incomingCallScreenRef.visible)
                    incomingCallScreenRef.hide();

                if (activeCallPageRef && !activeCallPageRef.visible) {
                    var number = TelephonyService.activeNumber;
                    var contactName = resolveContactName(number);
                    activeCallPageRef.show(number, contactName);
                }
            }
        }

        target: TelephonyService
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Column {
            property int currentIndex: 0

            anchors.fill: parent
            spacing: 0

            // App header — "Phone" title + search · menu actions per JSX
            // screens-apps-1.jsx:PhoneDialer (TopBar).
            MTopBar {
                width: parent.width
                title: "Phone"
                actions: [
                    Icon {
                        name: "search"
                        size: 22
                        color: MColors.textSecondary
                    },
                    Icon {
                        name: "ellipsis-vertical"
                        size: 22
                        color: MColors.textSecondary
                    }
                ]
            }

            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height - 88
                currentIndex: parent.currentIndex

                // DS Phone · Dialer (screens-apps-1.jsx:171).
                // 36/Light dialed number + teal contact-match subtitle.
                // 3×4 grid of 68 px elev-2 circles. Bottom action row:
                // user-icon · 64 px teal-gradient call circle · backspace x.
                Rectangle {
                    id: dialerPane
                    color: MColors.background

                    // Resolve a contact from the dialed number via the
                    // ContactsManager IPC client. Falls back to empty when
                    // no contact matches or the client isn't available.
                    function lookupContact(num) {
                        if (!num || num.length < 3)
                            return "";
                        if (typeof ContactsManager === "undefined")
                            return "";
                        const c = ContactsManager.getContactByNumber(num);
                        if (!c || !c.name)
                            return "";
                        // Default label is "Mobile" — when the contact model
                        // grows to support multiple labelled numbers per
                        // entry, this should use the matched number's label.
                        return c.name + " · Mobile";
                    }
                    readonly property string contactMatch: lookupContact(dialedNumber)

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        anchors.topMargin: 20
                        spacing: 0

                        // Display: dialed number + contact match
                        Item {
                            width: parent.width
                            height: 110

                            Column {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: dialedNumber.length > 0 ? dialedNumber : ""
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: 36
                                    font.weight: MTypography.weightExtraLight   // 200 per JSX
                                    font.letterSpacing: 1
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: dialerPane.contactMatch
                                    color: MColors.marathonTealBright
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    visible: text.length > 0
                                }
                            }
                        }

                        Grid {
                            id: dialPadGrid

                            // Key diameter scales with the available width
                            // (parent column width minus 24 px side padding
                            // minus 2 × 18 px gaps). JSX shows ~92 px keys at
                            // 390 px canvas; mapped to 540 px that's ~127 px.
                            // Clamped to 110 to leave breathing room for the
                            // bottom action row.
                            readonly property real cellSize: Math.min(Math.floor((parent.width - 18 * 2) / 3), Math.round(110 * Constants.scaleFactor))

                            anchors.horizontalCenter: parent.horizontalCenter
                            columns: 3
                            rowSpacing: 14
                            columnSpacing: 18
                            topPadding: 8
                            bottomPadding: 8

                            Repeater {
                                model: [
                                    {
                                        "digit": "1",
                                        "letters": ""
                                    },
                                    {
                                        "digit": "2",
                                        "letters": "ABC"
                                    },
                                    {
                                        "digit": "3",
                                        "letters": "DEF"
                                    },
                                    {
                                        "digit": "4",
                                        "letters": "GHI"
                                    },
                                    {
                                        "digit": "5",
                                        "letters": "JKL"
                                    },
                                    {
                                        "digit": "6",
                                        "letters": "MNO"
                                    },
                                    {
                                        "digit": "7",
                                        "letters": "PQRS"
                                    },
                                    {
                                        "digit": "8",
                                        "letters": "TUV"
                                    },
                                    {
                                        "digit": "9",
                                        "letters": "WXYZ"
                                    },
                                    {
                                        "digit": "*",
                                        "letters": ""
                                    },
                                    {
                                        "digit": "0",
                                        "letters": "+"
                                    },
                                    {
                                        "digit": "#",
                                        "letters": ""
                                    }
                                ]

                                Rectangle {
                                    required property var modelData

                                    width: dialPadGrid.cellSize
                                    height: dialPadGrid.cellSize
                                    radius: width / 2
                                    // JSX dialer keys are darker than the
                                    // default elev-2 card — they sit on the
                                    // background as soft pucks. elev-1
                                    // (#0a0a0b) reads correctly against the
                                    // pure-black canvas; pressed state lifts
                                    // to bb10-card.
                                    color: keyArea.pressed ? MColors.bb10Card : MColors.elev1
                                    border.width: 1
                                    border.color: MColors.whiteOverlay04

                                    // Top-only inset highlight — circular
                                    // version of the asymmetric DS edge
                                    // treatment. A 1-px-thick arc at the
                                    // top of the key reads as "lit from
                                    // above" without breaking the round
                                    // silhouette.
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: 2
                                        width: parent.width * 0.55
                                        height: 1
                                        color: Qt.rgba(1, 1, 1, 0.10)
                                        radius: 0.5
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.digit
                                            color: MColors.textPrimary
                                            font.family: MTypography.fontFamily
                                            font.pixelSize: Math.round(dialPadGrid.cellSize * 0.32)
                                            font.weight: MTypography.weightLight    // 300
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.letters
                                            color: MColors.textSecondary
                                            font.family: MTypography.fontFamily
                                            font.pixelSize: Math.round(dialPadGrid.cellSize * 0.11)
                                            font.weight: Font.Medium
                                            font.letterSpacing: 1.5
                                            visible: text.length > 0
                                        }
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 80
                                        }
                                    }

                                    MouseArea {
                                        id: keyArea
                                        anchors.fill: parent
                                        onClicked: {
                                            HapticService.light();
                                            addDigit(modelData.digit);
                                        }
                                    }
                                }
                            }
                        }

                        // Spacer pushes the action row to the bottom.
                        Item {
                            width: parent.width
                            height: Math.max(0, parent.parent.parent.height - 110 - dialPadGrid.height - 76 - 20)
                        }

                        // Action row — contacts shortcut · call · backspace.
                        Item {
                            width: parent.width
                            height: 76

                            Row {
                                anchors.fill: parent
                                anchors.bottomMargin: 12

                                Item {
                                    width: parent.width / 3
                                    height: parent.height
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "user"
                                        size: 22
                                        color: MColors.textTertiary
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: parent.parent.parent.parent.parent.parent.parent.parent.parent.currentIndex = 2
                                    }
                                }

                                Item {
                                    width: parent.width / 3
                                    height: parent.height
                                    Rectangle {
                                        id: callButton
                                        anchors.centerIn: parent
                                        width: 64
                                        height: 64
                                        radius: width / 2
                                        border.width: 1
                                        border.color: MColors.tealBorder
                                        gradient: Gradient {
                                            GradientStop {
                                                position: 0
                                                color: MColors.marathonTealBright
                                            }
                                            GradientStop {
                                                position: 1
                                                color: MColors.marathonTealDark
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            radius: width / 2
                                            color: "transparent"
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.3)
                                        }

                                        Icon {
                                            anchors.centerIn: parent
                                            name: "phone"
                                            size: 28
                                            color: "#000000"
                                        }

                                        scale: callArea.pressed ? 0.94 : 1.0
                                        Behavior on scale {
                                            NumberAnimation {
                                                duration: 120
                                                easing.type: Easing.OutBack
                                            }
                                        }

                                        MouseArea {
                                            id: callArea
                                            anchors.fill: parent
                                            enabled: dialedNumber.length > 0
                                            onClicked: {
                                                HapticService.medium();
                                                makeCall();
                                            }
                                        }
                                    }
                                }

                                Item {
                                    width: parent.width / 3
                                    height: parent.height
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "x"
                                        size: 22
                                        color: dialedNumber.length > 0 ? MColors.textSecondary : MColors.textTertiary
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: dialedNumber.length > 0
                                        onClicked: {
                                            HapticService.light();
                                            deleteDigit();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

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
                                dialedNumber = historyField(modelData, "number", "");
                                parent.parent.parent.parent.currentIndex = 0;
                            }

                            Row {
                                width: parent.parent.width - MSpacing.md * 2
                                height: MSpacing.touchTargetLarge
                                spacing: MSpacing.md

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: historyField(modelData, "type", "") === "outgoing" ? "phone-outgoing" : historyField(modelData, "type", "") === "incoming" ? "phone-incoming" : "phone-missed"
                                    size: 20
                                    color: historyField(modelData, "type", "") === "missed" ? MColors.error : MColors.accent
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.spacing * 2 - 20 * 2
                                    spacing: MSpacing.xs

                                    Text {
                                        width: parent.width
                                        text: historyField(modelData, "contactName", "Unknown")
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: MTypography.weightDemiBold
                                        font.family: MTypography.fontFamily
                                        color: MColors.text
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        spacing: MSpacing.sm

                                        Text {
                                            text: historyField(modelData, "number", "")
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            color: MColors.textSecondary
                                        }

                                        Text {
                                            text: "•"
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            color: MColors.textSecondary
                                            visible: formatDuration(historyField(modelData, "duration", 0)) !== ""
                                        }

                                        Text {
                                            text: formatDuration(historyField(modelData, "duration", 0))
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                            color: MColors.textSecondary
                                            visible: text !== ""
                                        }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: formatTimestamp(historyField(modelData, "timestamp", 0))
                                    font.pixelSize: MTypography.sizeSmall
                                    font.family: MTypography.fontFamily
                                    color: MColors.textTertiary
                                }
                            }
                        }
                    }
                }

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
                                            text: modelData ? modelData.name || "" : ""
                                            font.pixelSize: MTypography.sizeBody
                                            font.weight: MTypography.weightDemiBold
                                            font.family: MTypography.fontFamily
                                            color: MColors.text
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData ? modelData.phone || "" : ""
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

            // Favorites — empty state until contact pinning is wired.
            Rectangle {
                color: MColors.background
                Column {
                    anchors.centerIn: parent
                    spacing: 14
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "star"
                        size: 36
                        color: MColors.textTertiary
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No favorites yet"
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeSubhead
                        font.weight: Font.Medium
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Star a contact to pin it here"
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                    }
                }
            }

            MTabBar {
                id: tabBar

                width: parent.width
                activeTab: parent.currentIndex
                // Emergency mode hides History/Contacts tabs entirely -- only the
                // dialer is reachable. The bar remains so the layout dimension
                // is consistent with non-emergency launch.
                visible: !phoneApp.emergencyOnly
                tabs: phoneApp.emergencyOnly ? [
                    {
                        "label": "Emergency",
                        "icon": "phone"
                    }
                ] : [
                    {
                        "label": "Dial",
                        "icon": "phone"
                    },
                    {
                        "label": "Recents",
                        "icon": "clock"
                    },
                    {
                        "label": "Contacts",
                        "icon": "user"
                    },
                    {
                        "label": "Favorites",
                        "icon": "star"
                    }
                ]
                onTabSelected: index => {
                    HapticService.light();
                    if (phoneApp.emergencyOnly) {
                        tabBar.parent.currentIndex = 0;
                        return;
                    }
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
            Component.onCompleted: phoneApp.incomingCallScreenRef = incomingCallScreen
            Component.onDestruction: {
                if (phoneApp.incomingCallScreenRef === incomingCallScreen)
                    phoneApp.incomingCallScreenRef = null;
            }
        }

        ActiveCallPage {
            id: activeCallPage

            anchors.fill: parent
            Component.onCompleted: phoneApp.activeCallPageRef = activeCallPage
            Component.onDestruction: {
                if (phoneApp.activeCallPageRef === activeCallPage)
                    phoneApp.activeCallPageRef = null;
            }
        }
    }
}
