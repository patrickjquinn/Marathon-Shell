pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// Marathon DS · Hub (§09) — unified inbox.
//
// Glass-headered list view sourced from NotificationModel. Filter
// chip row selects an account category (All / Messages / Mail /
// Work / Calls). Each row is an MHubRow — avatar + name+time /
// account / snippet, with an unread dot left of the avatar.
//
// Per-row tint colour is derived from the appId so contacts read
// at a glance — Messages blue, Mail rose, Linear violet,
// missed calls teal.
Rectangle {
    id: hub

    property bool isInPeekMode: false
    property string selectedCategory: "all"        // "all" | "messages" | "mail" | "work" | "call"

    signal closed
    signal notificationTapped(int id, string appId, string title)

    // Sailfish's Events view: the ambience shows through, dimmed.
    color: Silica.Theme.rgba(Silica.Theme.highlightDimmerColor, Silica.Theme.opacityHigh)

    // ── Header (glass) ──────────────────────────────────────
    // JSX HubScreen() positions the header at top: 28 so the status bar
    // (28 px) stays visible above. Without this offset the "Hub" title
    // is clipped by the status-bar overlay.
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight
        height: 132


        Column {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 14
            spacing: 14

            // Title row
            Item {
                width: parent.width
                height: titleText.implicitHeight

                // A Silica page header: title right-aligned in the highlight,
                // the unread count beneath it.
                Column {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        id: titleText
                        anchors.right: parent.right
                        text: qsTr("Events")
                        color: Silica.Theme.highlightColor
                        font.pixelSize: Silica.Theme.fontSizeLarge
                    }
                    Silica.Label {
                        anchors.right: parent.right
                        text: qsTr("%n unread", "", NotificationModel.unreadCount)
                        color: Silica.Theme.secondaryHighlightColor
                        font.pixelSize: Silica.Theme.fontSizeSmall
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 18

                    GlyphIcon {
                        name: "search"
                        size: 20
                        color: MColors.textSecondary
                    }
                    GlyphIcon {
                        name: "filter"
                        size: 19
                        color: MColors.textSecondary
                    }
                }
            }

            // Filter chip row — horizontally flickable.
            //
            // This was a bare Row of five fixed chips. Nothing clipped it and
            // nothing scrolled it, so once the chips exceeded the viewport the
            // last one was simply cut off at the screen edge: at
            // userScaleFactor 1.50 "Calls" rendered as "Ca" and was
            // unreachable. Flicking keeps every category reachable at any
            // scale, and clip stops the overflow bleeding into the pane
            // beside it.
            Flickable {
                width: parent.width
                height: chipRow.implicitHeight
                contentWidth: chipRow.implicitWidth
                contentHeight: chipRow.implicitHeight
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

            Row {
                id: chipRow
                spacing: Math.round(6 * (Constants.scaleFactor || 1.0))

                Silica.FilterChip {
                    text: "All " + (NotificationModel.count || 0)
                    checked: hub.selectedCategory === "all"
                    automaticCheck: false
                    onClicked: hub.selectedCategory = "all"
                }
                Silica.FilterChip {
                    text: "Messages " + hub.countForCategory("messages")
                    checked: hub.selectedCategory === "messages"
                    automaticCheck: false
                    onClicked: hub.selectedCategory = "messages"
                }
                Silica.FilterChip {
                    text: "Mail " + hub.countForCategory("mail")
                    checked: hub.selectedCategory === "mail"
                    automaticCheck: false
                    onClicked: hub.selectedCategory = "mail"
                }
                Silica.FilterChip {
                    text: "Work " + hub.countForCategory("work")
                    checked: hub.selectedCategory === "work"
                    automaticCheck: false
                    onClicked: hub.selectedCategory = "work"
                }
                Silica.FilterChip {
                    text: "Calls " + hub.countForCategory("call")
                    checked: hub.selectedCategory === "call"
                    automaticCheck: false
                    onClicked: hub.selectedCategory = "call"
                }
            }
            }
        }
    }

    // ── List ────────────────────────────────────────────────
    // JSX HubScreen() shows 'Today' / 'Yesterday' section bands
    // between rows (HubGroup component). That would require an
    // ageGroup role on NotificationModel — deferred until the C++
    // model exposes it. For now the rows render in
    // newest-first order without grouping.
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: list.verticalCenter
        spacing: Silica.Theme.paddingMedium
        visible: hub.countForCategory(hub.selectedCategory) === 0

        Silica.InfoLabel {
            text: hub.selectedCategory === "all" ? "All caught up" : hub.selectedCategory === "messages" ? "No messages" : hub.selectedCategory === "mail" ? "No mail" : hub.selectedCategory === "work" ? "No work items" : hub.selectedCategory === "call" ? "No call history" : "Nothing here"
        }

        Silica.Label {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            text: hub.selectedCategory === "all" ? "Notifications from your apps appear here." : "Switch a category above to see other notifications."
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Silica.Theme.secondaryHighlightColor
        }
    }

    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        clip: true
        model: NotificationModel
        spacing: 0
        // cacheBuffer must be non-negative — the height transition
        // through 0 during peek expand briefly produces an
        // intermediate that Qt complains about. Clamp to 0.
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true

        delegate: MHubRow {
            required property int index
            required property string appId
            required property string title
            required property string body
            required property string icon
            required property var timestamp
            required property bool isRead

            width: list.width

            // The freedesktop app_name is a display name picked by the
            // sender -- "Messages", "Thunderbird". Fold it once here so
            // every helper below compares against the same key.
            readonly property string appKey: String(appId || "").toLowerCase()

            unread: !isRead
            avatarTint: hub.tintFor(appKey)
            avatarText: hub.monogramFor(title, appKey)
            avatarIcon: appKey === "phone" ? "phone" : ""
            avatarUsesTealBorder: appKey === "phone"
            avatarTextColor: hub.avatarTextFor(appKey)
            name: title
            time: hub.relativeTime(timestamp)
            account: hub.accountFor(appId)
            snippet: body
            visible: hub.appIdInCategory(appKey, hub.selectedCategory)
            height: visible ? implicitHeight : 0

            onActivated: hub.notificationTapped(0, appId, title)
        }
    }

    // ── Helpers ─────────────────────────────────────────────
    function tintFor(appId) {
        switch (appId) {
        case "messages":
        case "imessage":
            return MColors.secBlue;
        case "mail":
            return MColors.secRose;
        case "linear":
        case "work":
            return MColors.secViolet;
        case "phone":
        case "call":
            return Qt.rgba(0, 0.537, 0.482, 0.18);
        default:
            return MColors.bb10Card;
        }
    }

    function avatarTextFor(appId) {
        return appId === "phone" || appId === "call" ? MColors.marathonTealBright : "#ffffff";
    }

    function monogramFor(name, appId) {
        if (appId === "phone" || appId === "call")
            return "";
        if (!name)
            return "·";
        const parts = name.split(/\s+/).filter(p => p.length > 0);
        if (parts.length === 0)
            return "·";
        if (parts.length === 1)
            return parts[0].substring(0, 2).toUpperCase();
        // Build the uppercased per-name initials first, then concatenate
        // — keeps each side as a typed string so qmllint can resolve
        // toUpperCase() without falling back to QJSPrimitiveValue.
        const first = parts[0].toUpperCase();
        const last = parts[parts.length - 1].toUpperCase();
        return first.charAt(0) + last.charAt(0);
    }

    // Takes the RAW app_name. The switch matches on a folded copy, but the
    // default branch echoes what the sender actually sent -- only
    // capitalising a leading lower-case letter -- so "GNOME Software" keeps
    // its interior capitals while "signal" still reads as "Signal".
    function accountFor(rawAppId) {
        const appId = String(rawAppId || "").toLowerCase();
        switch (appId) {
        case "messages":
        case "imessage":
            return "iMessage";
        case "mail":
            return "Mail";
        case "linear":
            return "Linear · Work";
        case "phone":
        case "call":
            return "Phone";
        case "github":
            return "GitHub";
        case "calendar":
            return "Calendar";
        case "work":
            return "Work";
        default:
            const raw = String(rawAppId || "");
            return raw.charAt(0).toUpperCase() + raw.slice(1);
        }
    }


    // The single membership predicate: it answers both which rows a chip
    // shows and what each chip counts. These used to be two independently
    // case-sensitive ladders, so the chips counted one way and the list
    // filtered another, and both missed real traffic entirely.
    function appIdInCategory(rawAppId, category) {
        if (category === "all")
            return true;
        const appId = String(rawAppId || "").toLowerCase();
        if (category === "messages")
            return appId === "messages" || appId === "imessage";
        if (category === "mail")
            return appId === "mail";
        if (category === "work")
            return appId === "linear" || appId === "github" || appId === "work";
        if (category === "call")
            return appId === "phone" || appId === "call";
        return false;
    }

    function countForCategory(category) {
        if (!NotificationModel.count)
            return 0;
        let n = 0;
        for (let i = 0; i < NotificationModel.count; ++i) {
            const idx = NotificationModel.index(i, 0);
            const appId = NotificationModel.data(idx, NotificationModel.roleId("appId"));
            if (hub.appIdInCategory(appId, category))
                n += 1;
        }
        return n;
    }

    function relativeTime(ts) {
        if (!ts)
            return "";
        const now = Date.now();
        const diff = now - ts;
        if (diff < 60 * 1000)
            return "now";
        if (diff < 60 * 60 * 1000)
            return Math.floor(diff / 60 / 1000) + "m";
        if (diff < 24 * 60 * 60 * 1000)
            return Math.floor(diff / 60 / 60 / 1000) + "h";
        if (diff < 7 * 24 * 60 * 60 * 1000)
            return Math.floor(diff / 24 / 60 / 60 / 1000) + "d";
        return new Date(ts).toLocaleDateString();
    }
}
