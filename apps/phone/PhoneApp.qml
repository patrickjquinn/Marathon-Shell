import MarathonApp.Phone
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

    // First-use gate: prompt the moment the user opens a contacts-backed
    // tab (Contacts / Favorites) or the contacts shortcut, not on app
    // launch. The Dialer + Recents tabs render fine without contacts.
    function ensureContactsPermission() {
        if (emergencyOnly)
            return;
        if (hasContactsPermission)
            return;
        if (typeof PermissionManager === "undefined")
            return;
        if (PermissionManager.hasPermission(appId, "contacts")) {
            hasContactsPermission = true;
            return;
        }
        PermissionManager.requestPermission(appId, "contacts");
    }

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
            return;

        if (PermissionManager.hasPermission(appId, "contacts"))
            hasContactsPermission = true;
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
            onCurrentIndexChanged: {
                // Contacts (2) + Favorites (3) read ContactsManager; this is
                // where the first-use prompt belongs, not on app launch.
                if (currentIndex === 2 || currentIndex === 3)
                    phoneApp.ensureContactsPermission();
            }

            anchors.fill: parent
            spacing: 0

            // App header — "Phone" title + search · menu actions per JSX
            // screens-apps-1.jsx:PhoneDialer (TopBar).
            //
            // The Icons each get a MouseArea with -10 px margins so the
            // 22 px glyphs hit a 42 px tap target (matches Messages /
            // Notes / Mail patterns and clears the 44 px iOS HIG floor
            // with scaleFactor headroom). Without these the icons
            // rendered as decoration only — the user could never reach
            // them. Search lands a haptic placeholder until the slide-
            // in search row is wired (same shape as Messages); the
            // kebab opens a not-yet-implemented context menu so for
            // now it's a no-op haptic too — the buttons FEEL alive
            // even when the destinations are still empty.
            MTopBar {
                id: topBar
                width: parent.width
                title: "Phone"
                actions: [
                    Icon {
                        name: "search"
                        size: 28
                        color: MColors.textSecondary

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -12
                            onClicked: HapticService.light()
                        }
                    },
                    Icon {
                        name: "ellipsis-vertical"
                        size: 28
                        color: MColors.textSecondary

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -12
                            onClicked: HapticService.light()
                        }
                    }
                ]
            }

            StackLayout {
                width: parent.width
                // Was `parent.height - tabBar.height - 88`. The magic 88
                // (action-row 76 + 12 margin) was already accounted for
                // INSIDE dialerPane via the spacer at the bottom of the
                // dial-pad Column — subtracting it here too pushed the
                // bottom tab bar (Dial / Recents / Contacts / Favorites)
                // off the canvas by ~22 px and only the top of each
                // tab icon remained visible as a ghost fragment.
                height: parent.height - topBar.height - tabBar.height
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

                    // Action row is anchored as a sibling of this ColumnLayout
                    // (below) — anchored directly to dialerPane.bottom with
                    // an explicit 56 px margin so the call FAB sits clearly
                    // above the tab bar. Nesting it INSIDE the ColumnLayout
                    // made Layout.bottomMargin / anchors.bottomMargin both no-op
                    // on this surface (Qt 6.10 ColumnLayout vs. fillHeight
                    // sibling interaction).
                    ColumnLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: actionRow.top
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        anchors.topMargin: 20
                        anchors.bottomMargin: 16
                        spacing: 0

                        // Display: dialed number + contact match.
                        // 70 px is enough for a 36 px digit row with
                        // the 14 px contact-match subtitle below;
                        // anything taller showed as dead air above
                        // the first dial-pad row when no number was
                        // entered yet (the JSX canvas has a similarly
                        // tight display block).
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 70

                            Column {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    // Empty-state placeholder: the JSX canvas
                                    // hides this region when no number is
                                    // entered, but on a 720×1480 device that
                                    // leaves ~70 px of dead air above the dial
                                    // pad and the user has no anchor for where
                                    // their digits will land. A dimmed
                                    // placeholder keeps the visual rhythm and
                                    // hints at the input affordance.
                                    text: dialedNumber.length > 0 ? dialedNumber : qsTr("Enter number")
                                    color: dialedNumber.length > 0 ? MColors.textPrimary : MColors.textTertiary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: dialedNumber.length > 0 ? 36 : 24
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

                            Layout.alignment: Qt.AlignHCenter

                            // Key diameter scales with the available width
                            // (parent column width minus 2 × 18 px gaps).
                            // Was hard-clamped at 124, which on a 720 px
                            // device (≈672 px content width after the 24 px
                            // side padding) shrank the keys to ~140 px when
                            // there was room for ~212 px each. Now caps at
                            // 180 so they're chunky on phone-class screens
                            // but still leave headroom for the 4×3 grid +
                            // dial-number display + action row on the 1140
                            // logical-px canvas (~960 px tall content area).
                            readonly property real cellSize: Math.min(Math.floor((parent.width - 18 * 2) / 3), 180)

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
                                    // elev-1 over bb10Black was visually
                                    // invisible — 6 brightness units of
                                    // separation. Bumped to elev-2 with a
                                    // brighter border so the chip silhouette
                                    // is actually legible at a glance.
                                    color: keyArea.pressed ? MColors.bb10Card : MColors.elev2
                                    border.width: 1
                                    border.color: MColors.whiteOverlay08

                                    // The original "lit from above" highlight
                                    // was a 1 px straight horizontal Rectangle
                                    // sitting 2 px from the top of the circle.
                                    // On a round button the straight line
                                    // reads as a horizontal SLICE through the
                                    // top of the circle, not a curved
                                    // highlight — the chord doesn't follow
                                    // the silhouette. Removed; the elev-2
                                    // fill + whiteOverlay08 border already
                                    // gives enough visual separation.

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
                        // Layout.fillHeight on this empty Item makes
                        // ColumnLayout grant it every leftover pixel.
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }
                    }

                    // Action row — contacts shortcut · call · backspace.
                    // Anchored directly to dialerPane.bottom with a hard 56 px
                    // margin so the call FAB clears the bottom MTabBar; making
                    // it a sibling of the ColumnLayout means its position is
                    // not subject to ColumnLayout's fillHeight redistribution.
                    Item {
                        id: actionRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        anchors.bottomMargin: 56
                        height: 96

                        Row {
                            anchors.fill: parent

                            Item {
                                width: parent.width / 3
                                height: parent.height
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 56
                                    height: 56
                                    radius: width / 2
                                    color: contactsArea.pressed ? MColors.surface : "transparent"
                                    border.width: 1
                                    border.color: MColors.borderGlass

                                    Icon {
                                        anchors.centerIn: parent
                                        name: "user"
                                        size: 28
                                        color: MColors.textSecondary
                                    }
                                }
                                MouseArea {
                                    id: contactsArea
                                    anchors.fill: parent
                                    onClicked: dialerPane.parent.parent.currentIndex = 2
                                }
                            }

                            Item {
                                width: parent.width / 3
                                height: parent.height
                                Rectangle {
                                    id: callButton
                                    anchors.centerIn: parent
                                    width: 84
                                    height: 84
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
                                        size: 36
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
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 56
                                    height: 56
                                    radius: width / 2
                                    color: backspaceArea.pressed ? MColors.surface : "transparent"
                                    border.width: 1
                                    border.color: dialedNumber.length > 0 ? MColors.borderGlass : "transparent"
                                    opacity: dialedNumber.length > 0 ? 1 : 0.35

                                    Icon {
                                        anchors.centerIn: parent
                                        name: "delete"
                                        size: 28
                                        color: MColors.textSecondary
                                    }
                                }
                                MouseArea {
                                    id: backspaceArea
                                    anchors.fill: parent
                                    enabled: dialedNumber.length > 0
                                    onClicked: {
                                        HapticService.light();
                                        deleteDigit();
                                    }
                                    onPressAndHold: {
                                        HapticService.medium();
                                        dialedNumber = "";
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

                                    Item {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 36
                                        height: 36

                                        Icon {
                                            anchors.centerIn: parent
                                            name: "star"
                                            size: 20
                                            color: modelData.favorite ? MColors.marathonTealBright : MColors.textTertiary
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                // Tap doesn't bubble to the card's onClicked (we'd
                                                // open the editor instead of toggling). Persist via
                                                // ContactsManager so the favorite carries across
                                                // sessions; ContactsManager emits contactsChanged
                                                // and the `contacts` alias refreshes the GridView.
                                                HapticService.light();
                                                if (modelData && typeof ContactsManager !== "undefined")
                                                    ContactsManager.updateContact(modelData.id, {
                                                        "favorite": !modelData.favorite
                                                    });
                                            }
                                        }
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

            // Favorites — 3-col grid of starred contacts. Tap-to-call.
            // The empty state holds the line until at least one contact
            // is starred via the Contacts list star toggle.
            Rectangle {
                id: favoritesPane
                color: MColors.background

                readonly property var favoriteContacts: phoneApp.contacts.filter(c => c && c.favorite === true)

                MEmptyState {
                    anchors.centerIn: parent
                    width: parent.width - MSpacing.xl * 2
                    visible: favoritesPane.favoriteContacts.length === 0
                    iconName: "star"
                    title: "No favorites yet"
                    message: "Star a contact in Contacts to pin it here. Favorites give you one-tap calling."
                }

                GridView {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 16
                    visible: favoritesPane.favoriteContacts.length > 0
                    clip: true
                    cellWidth: width / 3
                    cellHeight: cellWidth + 18
                    model: favoritesPane.favoriteContacts

                    delegate: Item {
                        width: GridView.view.cellWidth
                        height: GridView.view.cellHeight

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.parent.width * 0.78
                                height: width
                                radius: width / 2
                                color: MColors.elev3
                                border.width: 1
                                border.color: MColors.tealBorder

                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        const n = modelData.name || "?";
                                        const parts = n.split(/\s+/).filter(p => p.length > 0);
                                        if (parts.length === 0)
                                            return "·";
                                        if (parts.length === 1)
                                            return parts[0].substring(0, 2).toUpperCase();
                                        return String(parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
                                    }
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: 20
                                    font.weight: Font.DemiBold
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: 2
                                    anchors.rightMargin: 2
                                    width: 18
                                    height: 18
                                    radius: width / 2
                                    color: MColors.marathonTealBright
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "star"
                                        size: 10
                                        color: "#000000"
                                    }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name || ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                width: parent.parent.width - 8
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                HapticService.medium();
                                if (modelData.phone) {
                                    dialedNumber = modelData.phone;
                                    TelephonyService.dial(modelData.phone);
                                    if (activeCallPageRef)
                                        activeCallPageRef.show(modelData.phone, modelData.name);
                                }
                            }
                        }
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
