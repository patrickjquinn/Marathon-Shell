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

    // As the notification banner's tap: open the sender, or just mark read.
    function openNotification(notifId, appId) {
        NotificationService.clickNotification(notifId);
        NotificationModel.markAsRead(notifId);
        if (!appId)
            return;
        NavigationRouter.navigateToDeepLink(appId, "", {
            "notificationId": notifId,
            "action": "view",
            "from": "hub"
        });
        if (isInPeekMode)
            closed();
    }

    signal closed

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

    Silica.SilicaListView {
        id: list

        objectName: "hubList"
        anchors.fill: parent
        clip: true
        model: NotificationModel
        spacing: 0
        // cacheBuffer must be non-negative — the height transition
        // through 0 during peek expand briefly produces an
        // intermediate that Qt complains about. Clamp to 0.
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: MMotion.durationFor("entrance")
                easing.type: Easing.OutCubic
            }
        }

        // Rows make room for a new one; an interrupted add still ends opaque.
        // A dismissed row animates its own exit (MHubRow).
        displaced: Transition {
            NumberAnimation {
                property: "y"
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "opacity"
                to: 1
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
            }
        }

        Silica.PullDownMenu {
            visible: list.count > 0

            Silica.MenuItem {
                objectName: "clearNotifications"
                text: qsTr("Clear notifications")
                onClicked: NotificationService.dismissAllNotifications()
            }
        }

        // ── Today: the date, then the calendar's agenda ─────────
        header: Column {
            id: header

            x: Silica.Theme.horizontalPageMargin
            width: list.width - 2 * x
            topPadding: Constants.statusBarHeight + Silica.Theme.paddingLarge
            spacing: Silica.Theme.paddingMedium
            bottomPadding: Silica.Theme.paddingLarge

            Silica.Label {
                width: parent.width
                // Re-read when the date string turns over at midnight.
                text: Qt.formatDate(SystemStatusStore.dateString ? new Date() : new Date(), "dddd, d MMMM")
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

            // Only when there is nothing at all: one quiet line.
            Silica.Label {
                width: parent.width
                visible: hub.agenda.length === 0 && list.count === 0
                text: qsTr("Nothing new")
                color: Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeSmall
            }
        }

        delegate: MHubRow {
            required property var model
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

            onActivated: hub.openNotification(model.id, appId)
            onDismissed: NotificationService.dismissNotification(model.id)
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

    // The sending app's name from the registry; otherwise the sender's own
    // app_name, with a leading lower-case letter capitalised.
    function accountFor(rawAppId) {
        const raw = String(rawAppId || "");
        const name = AppStore.getAppName(raw);
        if (name !== raw)
            return name;
        return raw.charAt(0).toUpperCase() + raw.slice(1);
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
