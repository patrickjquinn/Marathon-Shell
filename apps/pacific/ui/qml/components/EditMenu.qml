// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A long press in a web page's text field: select all, cut, copy and paste,
// as a field in the rest of the system offers them (Keel's TextEditMenu);
// a password field offers Paste only. A tap anywhere else closes it.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific.WebView 1.0

Item {
    id: menu

    property var tab
    property var info: ({})
    readonly property var webView: tab ? tab.webView : null
    readonly property bool secret: info && info.secret === true
    property bool selected
    readonly property bool canSelectAll: !secret && info && info.hasText === true
    readonly property bool canCopy: !secret && selected
    readonly property bool canPaste: Clipboard.hasText
    readonly property point _at: webView ? webView.mapToItem(menu, info.x || 0, info.y || 0) : Qt.point(0, 0)

    function open(tab: var, info: var): void {
        menu.tab = tab;
        menu.info = info;
        menu.selected = info.selected === true;
        menu.visible = canSelectAll || canCopy || canPaste;
    }

    function run(command: int): void {
        menu.webView.executeEditingCommand(command);
        menu.visible = false;
    }

    visible: false

    MouseArea {
        anchors.fill: parent
        onClicked: menu.visible = false
    }

    Connections {
        target: menu.webView
        function onInputMethodStateChanged(): void {
            if (!menu.webView.editableFocused)
                menu.visible = false;
        }
    }

    Rectangle {
        objectName: "editBar"
        x: Math.max(Theme.paddingMedium, Math.min(menu.width - width - Theme.paddingMedium, menu._at.x - width / 2))
        y: menu._at.y - height - Theme.paddingLarge >= Theme.paddingMedium ? menu._at.y - height - Theme.paddingLarge : menu._at.y + Theme.paddingLarge
        width: actions.width
        height: Theme.itemSizeExtraSmall
        radius: height / 2
        color: Theme.highlightDimmerColor

        component Action: MouseArea {
            id: action

            property alias text: label.text

            width: label.implicitWidth + 2 * Theme.paddingLarge
            height: parent.height

            Label {
                id: label

                anchors.centerIn: parent
                color: action.pressed ? Theme.highlightColor : Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Row {
            id: actions

            height: parent.height

            Action {
                objectName: "selectAll"
                visible: menu.canSelectAll && !menu.selected
                text: qsTr("Select all")
                onClicked: {
                    menu.webView.executeEditingCommand(WebView.SelectAll);
                    menu.selected = true;
                }
            }
            Action {
                objectName: "cut"
                visible: menu.canCopy
                text: qsTr("Cut")
                onClicked: menu.run(WebView.Cut)
            }
            Action {
                objectName: "copy"
                visible: menu.canCopy
                text: qsTr("Copy")
                onClicked: menu.run(WebView.Copy)
            }
            Action {
                objectName: "paste"
                visible: menu.canPaste
                text: qsTr("Paste")
                onClicked: menu.run(WebView.Paste)
            }
        }
    }
}
