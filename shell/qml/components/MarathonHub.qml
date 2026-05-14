import MarathonOS.Shell 1.0
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

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

    color: MColors.bb10Black

    // Background — Carbon-style minimal teal streak.
    Rectangle {
        anchors.fill: parent
        color: MColors.bb10Black
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: -40
            y: -40
            width: parent.width + 80
            height: 1
            rotation: -36
            color: MColors.tealHalo
            opacity: 0.15
        }
    }

    // ── Header (glass) ──────────────────────────────────────
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 132

        Rectangle {
            anchors.fill: parent
            color: MColors.glassActionbar
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: MColors.borderGlass
        }

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

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        id: titleText
                        text: "Hub"
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 32
                        font.weight: MTypography.weightLight
                        font.letterSpacing: -0.6
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: NotificationModel.unreadCount + " unread"
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                        font.features: ({
                                "tnum": 1
                            })
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 18

                    Icon {
                        name: "search"
                        size: 20
                        color: MColors.textSecondary
                    }
                    Icon {
                        name: "filter"
                        size: 19
                        color: MColors.textSecondary
                    }
                }
            }

            // Filter chip row
            Row {
                width: parent.width
                spacing: 6

                MFilterChip {
                    label: "All"
                    count: String(NotificationModel.count || 0)
                    active: hub.selectedCategory === "all"
                    onActivated: hub.selectedCategory = "all"
                }
                MFilterChip {
                    label: "Messages"
                    active: hub.selectedCategory === "messages"
                    onActivated: hub.selectedCategory = "messages"
                }
                MFilterChip {
                    label: "Mail"
                    active: hub.selectedCategory === "mail"
                    onActivated: hub.selectedCategory = "mail"
                }
                MFilterChip {
                    label: "Work"
                    active: hub.selectedCategory === "work"
                    onActivated: hub.selectedCategory = "work"
                }
                MFilterChip {
                    label: "Calls"
                    active: hub.selectedCategory === "call"
                    onActivated: hub.selectedCategory = "call"
                }
            }
        }
    }

    // ── List ────────────────────────────────────────────────
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        clip: true
        model: NotificationModel
        spacing: 0
        cacheBuffer: height * 2
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
            unread: !isRead
            avatarTint: hub.tintFor(appId)
            avatarText: hub.monogramFor(title, appId)
            avatarIcon: appId === "phone" ? "phone" : ""
            avatarUsesTealBorder: appId === "phone"
            avatarTextColor: hub.avatarTextFor(appId)
            name: title
            time: hub.relativeTime(timestamp)
            account: hub.accountFor(appId)
            snippet: body
            visible: hub.matchesCategory(appId)
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

    function accountFor(appId) {
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
        default:
            return appId;
        }
    }

    function matchesCategory(appId) {
        if (hub.selectedCategory === "all")
            return true;
        if (hub.selectedCategory === "messages")
            return appId === "messages" || appId === "imessage";
        if (hub.selectedCategory === "mail")
            return appId === "mail";
        if (hub.selectedCategory === "work")
            return appId === "linear" || appId === "github" || appId === "work";
        if (hub.selectedCategory === "call")
            return appId === "phone" || appId === "call";
        return false;
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
