pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQml.Models
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "../core/Agenda.js" as Agenda

// The Hub: today's date and calendar agenda,
// then the notifications by day, on the lightly frosted ambience. Like
// BB10's Hub it narrows to one source, here with a row of filter chips.
Rectangle {
    id: hub

    property bool isInPeekMode: false
    property var agenda: []
    // An app id narrows the list to that app; "" shows everything.
    property string filterApp: ""
    // The apps with notifications, newest first: { app, label, unread }.
    property var sources: []

    function refreshSources() {
        const apps = NotificationService.sources();
        sources = apps.map(s => ({
                    "app": s.appId,
                    "label": s.appId ? accountFor(s.appId) : qsTr("System"),
                    "unread": s.unread
                }));
        if (filterApp !== "" && !apps.some(s => s.appId === filterApp))
            filterApp = "";
    }

    // "Today", "Yesterday", a weekday within the week, then the date.
    function dayLabel(day) {
        const date = new Date(day + "T00:00:00");
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const days = Math.round((today - date) / 86400000);
        if (days <= 0)
            return qsTr("Today");
        if (days === 1)
            return qsTr("Yesterday");
        if (days < 7)
            return Qt.locale().dayName(date.getDay(), Locale.LongFormat);
        //: Qt date format pattern: keep the letters d, M, y; reorder or add separators only. Day and month for notification group headings, e.g. 26 October
        return Qt.formatDate(date, qsTr("d MMMM"));
    }
    readonly property bool overlayOpen: weatherSheet.open

    // Back: true when it closed the weather.
    function closeOverlay() {
        return weatherSheet.back();
    }

    function dismissOverlay() {
        weatherSheet.open = false;
    }

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

    onVisibleChanged: {
        if (visible) {
            list.contentY = list.originY;
            list.atTop = true;
            refreshAgenda();
            WeatherClient.refresh();
        } else {
            dismissOverlay();
        }
    }
    Component.onCompleted: {
        refreshAgenda();
        WeatherClient.refresh();
        refreshSources();
    }

    Connections {
        target: NotificationService
        function onRowsInserted() {
            Qt.callLater(hub.refreshSources);
        }
        function onRowsRemoved() {
            Qt.callLater(hub.refreshSources);
        }
        function onModelReset() {
            Qt.callLater(hub.refreshSources);
        }
    }

    Connections {
        target: AppModel
        function onCountChanged() {
            Qt.callLater(hub.refreshSources);
        }
    }

    SortFilterProxyModel {
        id: shownNotifications

        model: NotificationService
        filters: ValueFilter {
            roleName: "appId"
            value: hub.filterApp
            enabled: hub.filterApp !== ""
        }
    }

    // clickNotification opens the sender's app, if one is installed.
    function openNotification(notifId, appId) {
        NotificationService.clickNotification(notifId);
        NotificationService.markAsRead(notifId);
        if (appId && isInPeekMode)
            closed();
    }

    signal closed

    // The blurred ambience, opaque even over an app.
    color: "transparent"

    // The window's size, not the hub's: the peek animates the hub's width,
    // and each new size would reload the blurred wallpaper mid-animation.
    KeelAmbienceBackground {
        id: ambience

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
        model: shownNotifications
        spacing: 0
        // cacheBuffer must be non-negative — the height transition
        // through 0 during peek expand briefly produces an
        // intermediate that Qt complains about. Clamp to 0.
        cacheBuffer: Math.max(0, height * 2)
        reuseItems: true

        // At the top it stays at the top: a new row, or the filter chips
        // appearing once a second app posts, grow the list above its first
        // row and would push the date out of view.
        property bool atTop: true
        onMovementEnded: atTop = atYBeginning
        onOriginYChanged: if (atTop)
            Qt.callLater(() => list.contentY = list.originY)

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

        section.property: "day"
        section.delegate: Silica.SectionHeader {
            required property string section

            text: hub.dayLabel(section)
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
                //: Qt date format pattern: keep the letters d, M, y; reorder or add separators only. Weekday, day and month for the date heading, e.g. Monday, 26 October
                text: Qt.formatDate(SystemStatusStore.dateString ? new Date() : new Date(), qsTr("dddd, d MMMM"))
                color: Silica.Theme.secondaryHighlightColor
                font.pixelSize: Silica.Theme.fontSizeSmall
            }

            HubWeather {
                id: hubWeather

                width: parent.width
                onOpenRequested: {
                    weatherSheet.open = true;
                    weatherSheet.choosing = hubWeather.current === null;
                }
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

            // BB10's account list as chips: one per app, with what is
            // unread. Only when there is more than one app to choose from.
            Flickable {
                objectName: "hubFilters"
                width: parent.width + Silica.Theme.horizontalPageMargin
                height: Silica.Theme.itemSizeExtraSmall
                contentWidth: chips.width
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                visible: hub.sources.length > 1

                Row {
                    id: chips

                    Silica.FilterChip {
                        text: qsTr("All")
                        checked: hub.filterApp === ""
                        automaticCheck: false
                        onClicked: hub.filterApp = ""
                    }

                    Repeater {
                        model: hub.sources

                        Silica.FilterChip {
                            required property var modelData

                            text: modelData.unread > 0 ? modelData.label + " " + modelData.unread : modelData.label
                            checked: hub.filterApp === modelData.app
                            automaticCheck: false
                            onClicked: hub.filterApp = checked ? "" : modelData.app
                        }
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

        // In the pager the page bar sits over the bottom; the last row can
        // scroll clear of it.
        footer: Item {
            width: list.width
            height: hub.isInPeekMode ? Silica.Theme.paddingLarge : Silica.Theme.itemSizeMedium
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
            // People get their monogram; anything else its app, as BB10
            // marked each row with its service.
            readonly property bool fromPerson: ["messages", "phone", "call", "email", "mail"].indexOf(appKey) >= 0
            // AppModel.count: look again once the apps have loaded.
            readonly property string appIcon: fromPerson || AppModel.count === 0 ? "" : (AppModel.findById(appKey).icon || "")

            unread: !isRead
            avatarText: appIcon ? "" : hub.monogramFor(title, appKey)
            avatarIcon: appKey === "phone" ? "phone" : ""
            image: icon || appIcon
            glyphReplacesMonogram: appKey !== "messages"
            actions: model.actions || []
            actionIcons: !!model.actionIcons
            name: title
            time: hub.relativeTime(timestamp)
            account: hub.accountFor(appId)
            snippet: body
            ongoing: !!model.ongoing
            progress: model.ongoing ? model.progress : -1

            onActivated: hub.openNotification(model.id, appId)
            onDismissed: NotificationService.dismissNotification(model.id)
            onActionInvoked: key => NotificationService.triggerAction(model.id, key)
            onReplied: text => NotificationService.reply(model.id, text)
        }
    }

    // What scrolls up fades out under the status bar.
    Rectangle {
        width: parent.width
        height: Constants.statusBarHeight + Silica.Theme.paddingLarge
        gradient: Gradient {
            GradientStop {
                position: 0.6
                color: Silica.Theme.rgba("black", 0.85)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
        visible: !list.atYBeginning
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Silica.Theme.itemSizeMedium + Silica.Theme.paddingLarge
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 0.5
                color: Silica.Theme.rgba("black", 0.85)
            }
        }
        visible: !hub.isInPeekMode && !list.atYEnd
    }

    WeatherSheet {
        id: weatherSheet

        wallpaper: ambience.wallpaper
        lightAmbience: ambience.light
        width: parent.width
        height: parent.height
    }

    // ── Helpers ─────────────────────────────────────────────
    // Emoji, flags, variation selectors, ZWJ, symbols and punctuation give
    // no initial. V4 has no \p{L}, and its Array.from splits surrogates.
    function isSymbol(cp) {
        return (cp < 0x80 && !/[A-Za-z0-9]/.test(String.fromCodePoint(cp))) || (cp >= 0x2000 && cp <= 0x2BFF) || (cp >= 0x3000 && cp <= 0x303F) || (cp >= 0xFE00 && cp <= 0xFE0F) || (cp >= 0x1F000 && cp <= 0x1FAFF) || (cp >= 0xE0000 && cp <= 0xE007F);
    }

    function initialsOf(word) {
        const out = [];
        for (let i = 0; i < word.length; ) {
            const cp = word.codePointAt(i);
            const ch = String.fromCodePoint(cp);
            if (!hub.isSymbol(cp))
                out.push(ch.toUpperCase());
            i += ch.length;
        }
        return out;
    }

    function monogramFor(name, appId) {
        if (appId === "phone" || appId === "call")
            return "";
        const parts = (name || "").split(/\s+/).map(p => hub.initialsOf(p)).filter(p => p.length > 0);
        if (parts.length === 0)
            return "·";
        if (parts.length === 1)
            return parts[0].slice(0, 2).join("");
        return parts[0][0] + parts[parts.length - 1][0];
    }

    // The sending app's name from the registry; otherwise the sender's own
    // app_name, with a leading lower-case letter capitalised.
    function accountFor(rawAppId) {
        const raw = String(rawAppId || "");
        // Read again once the registry has loaded.
        if (AppModel.count === 0)
            return raw.charAt(0).toUpperCase() + raw.slice(1);
        const name = AppModel.findById(raw).name;
        if (name)
            return name;
        return raw.charAt(0).toUpperCase() + raw.slice(1);
    }

    function relativeTime(ts) {
        if (!ts)
            return "";
        const now = Date.now();
        const diff = now - ts;
        if (diff < 60 * 1000)
            //: Age of a notification under a minute
            return qsTr("now");
        if (diff < 60 * 60 * 1000)
            //: Age of a notification in minutes, e.g. 5m
            return qsTr("%1m").arg(Math.floor(diff / 60 / 1000));
        if (diff < 24 * 60 * 60 * 1000)
            //: Age of a notification in hours, e.g. 3h
            return qsTr("%1h").arg(Math.floor(diff / 60 / 60 / 1000));
        if (diff < 7 * 24 * 60 * 60 * 1000)
            //: Age of a notification in days, e.g. 2d
            return qsTr("%1d").arg(Math.floor(diff / 24 / 60 / 60 / 1000));
        return new Date(ts).toLocaleDateString();
    }
}
