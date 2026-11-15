// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The tab button's menu (press and hold it), as Safari's: a card at the
// bottom left, over the button, rising over the dimmed page, with a new
// tab, a new private tab, and closing every tab of the kind in front at
// once (with the remorse timer, as the tab switcher's). Tap the page or
// drag the card down to close it.
pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0

Item {
    id: menu

    property var browser
    property bool open: false
    // The page that shows the remorse popup.
    property Item remorseParent

    readonly property bool privateKind: browser ? browser.privateMode : false
    readonly property int count: browser ? browser.tabs.count : 0

    function show(): void { open = true }
    function hide(): void { open = false }

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: closed < 1

    // 1 closed, 0 open: the card's rise and the dimming.
    property real closed: open ? 0 : 1
    Behavior on closed { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

    readonly property real margin: Theme.paddingMedium
    readonly property real cornerRadius: Math.round(12 * Theme.pixelRatio)

    // The page, dimmed; a tap on it closes the menu.
    Rectangle {
        anchors.fill: parent
        color: Theme.overlayBackgroundColor
        opacity: Theme.opacityLow * (1 - menu.closed)
    }
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onClicked: menu.hide()
    }

    Item {
        id: card
        objectName: "tabsMenuCard"

        width: Math.min(menu.width - 2 * menu.margin, Math.max(Theme.paddingLarge * 18, 4 * Theme.itemSizeLarge))
        height: header.height + rows.height
        x: menu.margin
        y: menu.height - height - menu.margin + menu.closed * (height + menu.margin)

        // Taps inside the card stay in it.
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.fill: parent
            radius: menu.cornerRadius
            color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            Rectangle {
                anchors.fill: parent
                radius: menu.cornerRadius
                color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
            }
        }

        // The handle; dragging it down closes the menu.
        Item {
            id: header
            width: parent.width
            height: Theme.paddingLarge + Theme.paddingMedium
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                width: Theme.itemSizeLarge
                height: Theme.paddingSmall
                radius: height / 2
                color: Theme.primaryColor
            }
            MouseArea {
                anchors.fill: parent
                property real startY
                onPressed: function(mouse) { startY = mouse.y }
                onReleased: function(mouse) {
                    if (mouse.y - startY > Theme.paddingLarge)
                        menu.hide()
                }
            }
        }

        Column {
            id: rows
            anchors.top: header.bottom
            width: parent.width
            topPadding: Theme.paddingSmall
            bottomPadding: 2 * Theme.paddingSmall

            MenuButton {
                iconSource: "image://theme/icon-m-tab-new"
                text: qsTr("New tab")
                onClicked: { menu.hide(); menu.browser.newTab(false) }
            }
            MenuButton {
                iconSource: "image://theme/icon-m-incognito-new"
                text: qsTr("New private tab")
                onClicked: { menu.hide(); menu.browser.newTab(true) }
            }
            MenuButton {
                objectName: "closeAllTabs"
                iconSource: "image://theme/icon-m-cancel"
                //: %n is how many tabs close
                text: menu.privateKind ? qsTr("Close all %n private tab(s)", "", menu.count)
                                       : qsTr("Close all %n tab(s)", "", menu.count)
                enabled: menu.count > 0
                onClicked: {
                    var priv = menu.privateKind
                    menu.hide()
                    Remorse.popupAction(menu.remorseParent, priv ? qsTr("Closed all private tabs") : qsTr("Closed all tabs"),
                                        function() { menu.browser.closeAll(priv) })
                }
            }
        }
    }
}
