// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The site of the page in front: its connection; its shields (ad and tracker
// blocking and cookie-banner answers, one switch, for a site that breaks);
// what was blocked on the page; and its own settings (JavaScript, desktop
// site, autoplay, zoom, permissions).

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "protectionPage"

    property var browser
    property var tab
    readonly property string pageUrl: tab ? String(tab.webView.url) : ""
    readonly property string site: Logic.host(pageUrl)
    property var stats: tab ? JSON.parse(Pacific.pageStats(tab.tabId)) : ({})
    property var siteSettings: ({})
    property bool showAllBlocked: false

    allowedOrientations: Orientation.All

    function value(key: var, fallback: var): var {
        var v = siteSettings[key]
        return v === null || v === undefined ? fallback : v
    }
    function permission(name: var): var {
        var p = siteSettings.permissions || []
        for (var i = 0; i < p.length; ++i)
            if (p[i][0] === name)
                return p[i][1]
        return "ask"
    }
    function set(key: var, v: var): void {
        Pacific.setSiteSetting(pageUrl, key, v, tab.isPrivate)
    }

    Component.onCompleted: Pacific.loadSiteSettings(pageUrl, tab ? tab.isPrivate : false)

    Connections {
        target: Pacific
        function onSiteSettingsLoaded(url, json) {
            if (url === page.pageUrl)
                page.siteSettings = JSON.parse(json)
        }
        function onPageStatsChanged(tabId) {
            if (page.tab && tabId === page.tab.tabId)
                page.stats = JSON.parse(Pacific.pageStats(tabId))
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Reset this site's settings")
                onClicked: Remorse.popupAction(page, qsTr("Reset this site's settings"), function() { Pacific.clearSiteSettings(page.site) })
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: page.site
                description: page.pageUrl.indexOf("https:") === 0 ? qsTr("Secure connection") : qsTr("Not secure: this connection isn't encrypted")
            }

            // Shields: this site's ad and tracker blocking and cookie-banner
            // answers, together, the switch to reach for when a site breaks.
            TextSwitch {
                id: shields
                objectName: "shields"
                readonly property bool globalOn: page.browser.settings.blocking
                text: !globalOn ? qsTr("Shields are off")
                      : checked ? qsTr("Shields are up for this site")
                      : qsTr("Shields are down for this site")
                description: !globalOn ? qsTr("Ad and tracker blocking is turned off in Settings.")
                             : page.tab && page.tab.isPrivate ? qsTr("Change this site's shields in a normal tab.")
                             : checked ? qsTr("Ads, trackers and cookie banners are blocked here. If the site doesn't work, put shields down.")
                             : qsTr("Nothing is blocked here and cookie banners are left alone.")
                enabled: globalOn && page.tab !== null && !page.tab.isPrivate
                checked: globalOn && page.value("blocking", true)
                automaticCheck: false
                onClicked: {
                    var up = !checked
                    // Shown at once: the settings come back only after the
                    // filters are made again, seconds later.
                    var s = Object.assign({}, page.siteSettings)
                    s.blocking = up
                    page.siteSettings = s
                    page.set("blocking", up ? "1" : "0")
                    // The filters are made again without (or with) this
                    // site; the page reloads once they are in place.
                    page.browser.reloadAfterRefilter()
                }
            }

            Label {
                objectName: "protectionIncompleteNote"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: page.browser.protectionIncomplete && shields.checked
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Still preparing %n filter list(s). Some ads and trackers may get through until then.", "", page.browser.missingFilters.length)
            }

            SectionHeader {
                text: qsTr("On this page")
                visible: shields.checked
            }

            // The page's tally: the count large, what else was done below it.
            Row {
                visible: shields.checked
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                spacing: Theme.paddingMedium
                Label {
                    id: blockedCount
                    objectName: "blockedCount"
                    text: page.stats.blocked !== undefined ? page.stats.blocked : 0
                    font.pixelSize: Theme.fontSizeHuge
                    color: Theme.highlightColor
                }
                Label {
                    anchors.baseline: blockedCount.baseline
                    width: parent.width - blockedCount.width - parent.spacing
                    wrapMode: Text.Wrap
                    text: qsTr("ads and trackers blocked")
                    color: Theme.highlightColor
                }
            }
            Column {
                visible: shields.checked
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                topPadding: Theme.paddingSmall
                bottomPadding: Theme.paddingMedium
                Label {
                    visible: page.stats.cookie_banner_handled === true
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                    text: qsTr("Cookie banner rejected for you")
                }
                Label {
                    visible: page.stats.https_upgraded === true
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                    text: qsTr("Connection upgraded to HTTPS")
                }
            }

            // Who was blocked, most first: the site on the left, how many
            // requests on the right. The six largest, then the rest on request.
            Repeater {
                model: shields.checked ? (page.stats.by_site || []).slice(0, page.showAllBlocked ? 20 : 6) : []
                Item {
                    required property var modelData
                    width: column.width
                    height: Theme.itemSizeExtraSmall
                    Label {
                        anchors { left: parent.left; leftMargin: Theme.horizontalPageMargin; right: count.left; rightMargin: Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                        text: parent.modelData[0]
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.highlightColor
                    }
                    Label {
                        id: count
                        anchors { right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                        text: parent.modelData[1]
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }
            BackgroundItem {
                objectName: "showAllBlocked"
                visible: shields.checked && !page.showAllBlocked && (page.stats.by_site || []).length > 6
                height: Theme.itemSizeSmall
                onClicked: page.showAllBlocked = true
                Label {
                    anchors { left: parent.left; leftMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                    text: qsTr("Show all %n", "", (page.stats.by_site || []).length)
                    font.pixelSize: Theme.fontSizeSmall
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }

            SectionHeader { text: qsTr("This site") }

            TextSwitch {
                text: qsTr("JavaScript")
                checked: page.value("javascript", page.browser.settings.javascript)
                onClicked: page.set("javascript", checked ? "1" : "0")
            }
            TextSwitch {
                text: qsTr("Desktop version")
                checked: page.value("desktop", page.browser.settings.desktop_mode)
                onClicked: page.set("desktop", checked ? "1" : "0")
            }
            TextSwitch {
                text: qsTr("Play media without a tap")
                checked: page.value("autoplay", page.browser.settings.autoplay)
                onClicked: page.set("autoplay", checked ? "1" : "0")
            }
            // Zoom for this site (100% clears it), applied at once.
            Slider {
                objectName: "siteZoom"
                width: parent.width
                label: qsTr("Zoom")
                minimumValue: 50
                maximumValue: 200
                stepSize: 10
                value: Math.round((page.tab ? page.tab.webView.zoomFactor : 1) * 100)
                valueText: Math.round(value) + "%"
                onReleased: {
                    var z = value / 100
                    page.tab.webView.zoomFactor = z
                    page.set("zoom", Math.abs(z - 1) < 0.001 ? "" : String(z))
                }
            }

            SectionHeader { text: qsTr("Permissions") }

            Repeater {
                model: [
                    { key: "location", text: qsTr("Location") },
                    { key: "camera", text: qsTr("Camera") },
                    { key: "microphone", text: qsTr("Microphone") },
                    { key: "notifications", text: qsTr("Notifications") }
                ]
                ComboBox {
                    id: combo
                    required property var modelData
                    label: modelData.text
                    currentIndex: ["ask", "allow", "deny"].indexOf(page.permission(modelData.key))
                    menu: ContextMenu {
                        MenuItem { text: qsTr("Ask"); onClicked: page.set("perm." + combo.modelData.key, "ask") }
                        MenuItem { text: qsTr("Allow"); onClicked: page.set("perm." + combo.modelData.key, "allow") }
                        MenuItem { text: qsTr("Block"); onClicked: page.set("perm." + combo.modelData.key, "deny") }
                    }
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
