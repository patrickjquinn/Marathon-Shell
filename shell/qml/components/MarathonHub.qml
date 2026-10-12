pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "../core/Agenda.js" as Agenda

// The Hub, as Sailfish's Events view: today's date and calendar agenda,
// then the notifications, on the lightly frosted ambience.
Rectangle {
    id: hub

    property bool isInPeekMode: false
    property var agenda: []

    function refreshAgenda() {
        let events = SettingsManagerCpp.get("calendar/events", []);
        if (typeof events === "string") {
            try {
                events = JSON.parse(events);
            } catch (e) {
                events = [];
            }
        }
        hub.agenda = Agenda.forDay(events, new Date());
    }

    onVisibleChanged: if (visible) refreshAgenda()
    Component.onCompleted: refreshAgenda()

    signal closed
    signal notificationTapped(int id, string appId, string title)

    // Sailfish's Events view: the blurred ambience, opaque even over an app.
    color: "transparent"

    // The window's size, not the hub's: the peek animates the hub's width,
    // and each new size would reload the blurred wallpaper mid-animation.
    KeelAmbienceBackground {
        width: hub.Window.width
        height: hub.Window.height
        wallpaper: AmbienceService.wallpaperUrl
        toneOpacity: 0.4
        light: AmbienceService.light
    }

    // ── Today: the date, then the calendar's agenda ─────────
    Column {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight + Silica.Theme.paddingLarge
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        spacing: Silica.Theme.paddingMedium
        bottomPadding: Silica.Theme.paddingLarge

        Silica.Label {
            width: parent.width
            text: Qt.formatDate(new Date(), "dddd, d MMMM")
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
        }

        Repeater {
            model: hub.agenda

            Item {
                id: entry

                required property var modelData

                width: header.width
                height: entryTitle.height + Silica.Theme.paddingSmall * 2

                Rectangle {
                    width: Math.max(2, Math.round(Silica.Theme.paddingSmall / 3))
                    height: parent.height
                    color: Silica.Theme.highlightColor
                }
                Silica.Label {
                    id: entryTime

                    x: Silica.Theme.paddingMedium
                    width: Silica.Theme.itemSizeLarge
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.allDay ? qsTr("All day") : entry.modelData.time
                    color: Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                }
                Silica.Label {
                    id: entryTitle

                    anchors.left: entryTime.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.title
                    truncationMode: Silica.TruncationMode.Fade
                }
            }
        }
    }

    // Only when there is nothing at all: one quiet line.
    Silica.Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        visible: hub.agenda.length === 0 && NotificationModel.count === 0
        text: qsTr("Nothing new")
        color: Silica.Theme.secondaryColor
        font.pixelSize: Silica.Theme.fontSizeSmall
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
            avatarText: hub.monogramFor(title, appKey)
            avatarIcon: appKey === "phone" ? "phone" : ""
            name: title
            time: hub.relativeTime(timestamp)
            account: hub.accountFor(appId)
            snippet: body

            onActivated: hub.notificationTapped(0, appId, title)
        }
    }

    // ── Helpers ─────────────────────────────────────────────
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
