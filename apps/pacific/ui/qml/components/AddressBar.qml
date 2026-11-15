// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The toolbar at the bottom of the screen, as in the Sailfish Browser:
//
//   [tabs] [back] [lock n]  site name  [reader | stop] [menu]
//
// On the browser's glass (Theme.overlayBackgroundColor, the stock
// toolbar's opacity). The tab button is Silica's tab icon with the count
// in it (the incognito icon for private tabs). Back appears when there is
// a page to go back to. The lock (a warning for an insecure page) carries
// the count of what was blocked and opens the site's page. The site name
// is the registrable domain; tapping it opens the address entry. While a
// page loads the bar fills with the highlight gradient from the left and
// a stop button shows; when the page has an article, the reader button.
// Reload, forward and the rest are in the menu.
//
// Gestures start on the site name: sideways moves between tabs (the page
// follows the finger and the neighbour slides in), upwards opens the tab
// overview. The bar reports them; BrowserPage animates.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0
import "../js/logic.js" as Logic

SilicaItem {
    id: bar

    property var browser
    property var tab: browser ? browser.currentTab : null
    readonly property bool privateTab: browser ? browser.privateMode : false
    property int tabCount: 0
    property int blockedCount: 0
    // Blocking is on but a filter list is not in force yet.
    property bool protectionIncomplete: false
    property bool readable: false

    signal addressClicked()
    signal tabsClicked()
    // Press and hold: the tab menu (new tab, new private tab, close all).
    signal tabsHeld()
    signal menuClicked()
    signal shieldClicked()
    signal readerClicked()
    // Gestures on the pill: dx, dy from the press; `velocity` px/s at release.
    signal dragStarted()
    signal dragMoved(real dx, real dy)
    signal dragEnded(real dx, real dy, real velocityX, real velocityY)

    readonly property var view: tab && tab.webView ? tab.webView : null
    // A page that could not be shown (certificate, HTTPS-only, load
    // error): the bar names the address that was asked for, not the page
    // still behind the panel.
    readonly property var problem: !tab ? null
                                   : (tab.certificateProblem || tab.interstitial || tab.loadError || null)
    readonly property string problemUrl: !problem ? "" : (problem.url || problem.http_url || "")
    readonly property string pageUrl: problemUrl !== "" ? problemUrl : (view ? String(view.url) : "")
    readonly property bool loading: view !== null && view.loading
    // A finished load counts as complete: the line fills to the end, then
    // fades (it used to drop to 0 the moment loading stopped, and shrank
    // back to the left as it faded).
    readonly property real progress: !view ? 0 : (loading ? view.loadProgress / 100 : 1)
    readonly property bool webPage: pageUrl.indexOf("http") === 0
    readonly property bool insecure: Logic.insecure(pageUrl) || (tab !== null && tab.certificateProblem !== null)
    readonly property string site: Pacific.siteOf(pageUrl)

    readonly property bool canGoBack: view !== null && view.canGoBack && problem === null
    readonly property bool reader: (readable && problem === null) || (tab !== null && tab.readerMode)

    // The stock browser's toolbar height (108 px at pixel ratio 1).
    height: Math.round(108 * Theme.pixelRatio)

    // The glass: frosted over what is behind it (`backdrop`, the pages),
    // the stock opaque glass without one.
    property Item backdrop
    property real backdropY: 0
    property bool frosted: true
    FrostedGlass {
        anchors.fill: parent
        backdrop: bar.backdrop
        backdropY: bar.backdropY
        active: bar.frosted
    }
    // Private tabs: the glass takes a highlight tint.
    Rectangle {
        anchors.fill: parent
        visible: bar.privateTab
        color: Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityFaint)
    }
    // Loading: the highlight gradient fills the bar from the left. It only
    // ever grows smoothly: a new load starts it again from its own value at
    // once, and a finished one fills it to the end before it fades.
    Rectangle {
        id: progressLine
        objectName: "progressLine"
        readonly property real target: bar.width * bar.progress
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: 0
        opacity: bar.loading || grow.running ? 1 : 0
        Behavior on opacity { FadeAnimation {} }
        onTargetChanged: {
            if (target < width) {
                grow.stop()
                width = target
            } else {
                grow.to = target
                grow.restart()
            }
        }
        SmoothedAnimation {
            id: grow
            target: progressLine
            property: "width"
            velocity: 1200
        }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityFaint) }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityHigh) }
        }
    }

    readonly property real buttonWidth: Theme.iconSizeMedium + Theme.paddingSmall

    Row {
        id: row
        anchors { left: parent.left; right: parent.right; leftMargin: Theme.paddingSmall; rightMargin: Theme.paddingSmall; verticalCenter: parent.verticalCenter }
        height: bar.height

        // Silica's tab icon with the count inside it.
        IconButton {
            id: tabsButton
            objectName: "tabsButton"
            width: bar.buttonWidth
            height: parent.height
            icon.source: bar.privateTab ? (bar.tabCount > 0 ? "image://theme/icon-m-incognito-selected" : "image://theme/icon-m-incognito")
                                        : "image://theme/icon-m-tabs"
            onClicked: bar.tabsClicked()
            onPressAndHold: bar.tabsHeld()

            // A tab opened or closed: the icon turns once, forwards for a
            // new tab and backwards for a closed one (as the Sailfish
            // Browser's does, in a third of the time) and the count pops,
            // so a tab opened behind the page is seen to arrive. Not for
            // jumps (a restored session, closing all, switching to private).
            property int _lastCount: -1
            readonly property int count: bar.tabCount
            onCountChanged: {
                var step = count - _lastCount
                if (_lastCount >= 0 && Math.abs(step) === 1 && bar.visible) {
                    turn.from = 0
                    turn.to = step > 0 ? 360 : -360
                    turn.restart()
                    pop.restart()
                }
                _lastCount = count
            }
            Connections {
                target: bar
                function onPrivateTabChanged() { tabsButton._lastCount = -1 }
            }
            RotationAnimator {
                id: turn
                target: tabsButton.icon
                duration: 500
                easing.type: Easing.OutCubic
            }
            SequentialAnimation {
                id: pop
                NumberAnimation { target: countLabel; property: "scale"; to: 1.5; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: countLabel; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
            }
            Label {
                id: countLabel
                objectName: "tabCount"
                anchors.centerIn: parent
                anchors.verticalCenterOffset: bar.privateTab ? Theme.paddingSmall / 2 : 0
                text: bar.tabCount > 99 ? "∞" : bar.tabCount
                font.pixelSize: Theme.fontSizeExtraSmall
                font.bold: true
                color: bar.privateTab ? Theme.overlayBackgroundColor
                                      : (tabsButton.highlighted ? Theme.highlightColor : Theme.primaryColor)
            }
        }

        IconButton {
            id: backButton
            objectName: "backButton"
            width: bar.canGoBack ? bar.buttonWidth : 0
            height: parent.height
            opacity: bar.canGoBack ? 1 : 0
            enabled: bar.canGoBack
            clip: true
            Behavior on width { NumberAnimation { duration: 150 } }
            icon.source: "image://theme/icon-m-back"
            onClicked: bar.view.goBack()
        }

        // The connection and what was blocked: opens the site's page.
        BackgroundItem {
            id: siteButton
            objectName: "shield"
            visible: bar.webPage
            width: siteRow.width + 2 * Theme.paddingSmall
            height: parent.height
            _showPress: false
            onClicked: bar.shieldClicked()
            Row {
                id: siteRow
                anchors.centerIn: parent
                spacing: Theme.paddingSmall / 2
                // The lock, with the count of what was blocked at its top
                // right corner as a badge (beside it, a small digit read as
                // a footnote to the site name).
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: lockIcon.width + (blockedCount.visible ? blockedCount.width - Theme.paddingSmall : 0)
                    height: lockIcon.height
                    Icon {
                        id: lockIcon
                        source: bar.insecure ? "image://theme/icon-s-filled-warning" : "image://theme/icon-s-outline-secure"
                        color: bar.insecure ? Theme.errorColor : (siteButton.highlighted ? Theme.highlightColor : Theme.primaryColor)
                    }
                    Label {
                        id: blockedCount
                        objectName: "blockedCount"
                        x: lockIcon.width - Theme.paddingSmall
                        y: -Theme.paddingSmall
                        visible: bar.blockedCount > 0 && bar.problem === null && !bar.protectionIncomplete
                        text: bar.blockedCount > 99 ? "99+" : bar.blockedCount
                        font.pixelSize: Theme.fontSizeTiny
                        font.bold: true
                        color: Theme.highlightColor
                    }
                }
                Icon {
                    objectName: "protectionIncomplete"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bar.protectionIncomplete && bar.problem === null
                    source: "image://theme/icon-s-filled-warning"
                    color: Theme.secondaryHighlightColor
                }
            }
        }

        // The site name; taps open the address entry, drags switch tabs.
        Item {
            id: urlArea
            objectName: "addressPill"
            width: row.width - tabsButton.width - backButton.width - (siteButton.visible ? siteButton.width : 0)
                   - (actionButton.visible ? actionButton.width : 0) - menuButton.width
            height: parent.height

            MouseArea {
                id: gesture
                objectName: "addressArea"
                anchors.fill: parent
                preventStealing: dragging
                property real startX
                property real startY
                property real lastX
                property real lastY
                property double lastT
                property real vx
                property real vy
                property bool dragging: false

                onPressed: function(mouse) {
                    startX = mouse.x; startY = mouse.y
                    lastX = mouse.x; lastY = mouse.y
                    lastT = Date.now(); vx = 0; vy = 0
                    dragging = false
                }
                onPositionChanged: function(mouse) {
                    var now = Date.now()
                    var dt = Math.max(1, now - lastT)
                    vx = 0.7 * vx + 0.3 * (mouse.x - lastX) * 1000 / dt
                    vy = 0.7 * vy + 0.3 * (mouse.y - lastY) * 1000 / dt
                    lastX = mouse.x; lastY = mouse.y; lastT = now
                    var dx = mouse.x - startX, dy = mouse.y - startY
                    if (!dragging && Math.abs(dx) + Math.abs(dy) > Theme.startDragDistance) {
                        dragging = true
                        bar.dragStarted()
                    }
                    if (dragging)
                        bar.dragMoved(dx, dy)
                }
                onReleased: function(mouse) {
                    if (dragging)
                        bar.dragEnded(mouse.x - startX, mouse.y - startY, vx, vy)
                    else
                        bar.addressClicked()
                    dragging = false
                }
                onCanceled: {
                    if (dragging)
                        bar.dragEnded(0, 0, 0, 0)
                    dragging = false
                }
            }

            Label {
                id: siteLabel
                objectName: "siteLabel"
                anchors { left: parent.left; right: parent.right; leftMargin: siteButton.visible ? 0 : Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                textFormat: Text.PlainText
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeMedium
                text: {
                    if (!bar.view || Logic.displayUrl(bar.pageUrl, "") === "")
                        return qsTr("Search or address")
                    // Reader mode: the site the article came from.
                    if (bar.tab && bar.tab.readerMode && bar.tab.url.indexOf("http") === 0)
                        return Pacific.siteOf(bar.tab.url)
                    var t = Logic.barText(bar.pageUrl, bar.problem ? "" : bar.view.title, bar.site)
                    return bar.insecure ? qsTr("Not secure · %1").arg(t) : t
                }
                color: gesture.pressed ? Theme.highlightColor
                                       : (!bar.view || Logic.displayUrl(bar.pageUrl, "") === "" ? Theme.secondaryColor : Theme.primaryColor)
            }
        }

        IconButton {
            id: actionButton
            objectName: bar.reader ? "readerButton" : "stopButton"
            visible: bar.reader || bar.loading
            width: bar.buttonWidth
            height: parent.height
            icon.source: bar.reader && !bar.loading ? "image://theme/icon-m-file-document-light" : "image://theme/icon-m-reset"
            highlighted: down || (bar.tab !== null && bar.tab.readerMode)
            onClicked: {
                if (bar.loading)
                    bar.view.stop()
                else
                    bar.readerClicked()
            }
        }

        IconButton {
            id: menuButton
            objectName: "menuButton"
            width: bar.buttonWidth
            height: parent.height
            icon.source: "image://theme/icon-m-menu"
            onClicked: bar.menuClicked()
        }
    }
}
