// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The tab button's menu (press and hold it), as Safari's: the toolbar's
// sheet, as the page menu, with a new tab, a new private tab, and closing
// every tab of the kind in front at once (with the remorse timer, as the
// tab switcher's). Tap the page or drag the sheet down to close it.
pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0

Item {
    id: menu

    property var browser
    property bool open: false
    // The page that shows the remorse popup.
    property Item remorseParent
    // The toolbar's height on screen: the sheet rises from its top edge.
    property real bottomMargin: 0

    readonly property bool privateKind: browser ? browser.privateMode : false
    readonly property int count: browser ? browser.tabs.count : 0

    function show(): void {
        open = true;
    }
    function hide(): void {
        open = false;
    }

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: closed < 1

    // 1 closed, 0 open: the sheet's rise.
    property real closed: open ? 0 : 1
    Behavior on closed {
        NumberAnimation {
            duration: 200
            easing.type: Easing.InOutQuad
        }
    }

    // A tap on the page closes the menu.
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onClicked: menu.hide()
    }

    // Above the toolbar, so the sheet rises from its top edge.
    Item {
        width: parent.width
        height: parent.height - menu.bottomMargin
        clip: true

        Item {
            objectName: "tabsMenuCard"

            width: parent.width
            height: rows.height
            y: parent.height - height + menu.closed * height

            // Taps inside the sheet stay in it; dragging it down closes it.
            MouseArea {
                anchors.fill: parent
                property real startY
                onPressed: function (mouse) {
                    startY = mouse.y;
                }
                onReleased: function (mouse) {
                    if (mouse.y - startY > Theme.paddingLarge)
                        menu.hide();
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            }

            Column {
                id: rows
                width: parent.width
                topPadding: Theme.paddingMedium
                bottomPadding: Theme.paddingMedium

                MenuButton {
                    iconSource: "image://theme/icon-m-tab-new"
                    text: qsTr("New tab")
                    onClicked: {
                        menu.hide();
                        menu.browser.newTab(false);
                    }
                }
                MenuButton {
                    iconSource: "image://theme/icon-m-incognito-new"
                    text: qsTr("New private tab")
                    onClicked: {
                        menu.hide();
                        menu.browser.newTab(true);
                    }
                }
                MenuButton {
                    objectName: "closeAllTabs"
                    iconSource: "image://theme/icon-m-cancel"
                    //: %n is how many tabs close
                    text: menu.privateKind ? qsTr("Close all %n private tab(s)", "", menu.count) : qsTr("Close all %n tab(s)", "", menu.count)
                    enabled: menu.count > 0
                    onClicked: {
                        var priv = menu.privateKind;
                        menu.hide();
                        Remorse.popupAction(menu.remorseParent, priv ? qsTr("Closed all private tabs") : qsTr("Closed all tabs"), function () {
                            menu.browser.closeAll(priv);
                        });
                    }
                }
            }

            GlowLine {
                width: parent.width
            }
        }
    }
}
