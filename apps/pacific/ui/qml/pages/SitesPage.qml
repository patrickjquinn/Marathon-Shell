// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Sites with their own settings, or the sites allowed over plain HTTP.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0

Page {
    id: page
    objectName: "sitesPage"

    property string kind: "sites"

    allowedOrientations: Orientation.All

    // A site's own settings in words: "Zoom 125%, Location blocked".
    function describe(json: var): var {
        var d = {};
        try {
            d = JSON.parse(json);
        } catch (e) {
            return "";
        }
        var parts = [];
        if (d.zoom !== null && d.zoom !== undefined)
            parts.push(qsTr("Zoom %1%").arg(Math.round(d.zoom * 100)));
        if (d.desktop === true)
            parts.push(qsTr("Desktop site"));
        if (d.javascript === false)
            parts.push(qsTr("JavaScript off"));
        if (d.blocking === false)
            parts.push(qsTr("Blocking off"));
        if (d.autoplay === true)
            parts.push(qsTr("Plays media"));
        var names = {
            location: qsTr("Location"),
            camera: qsTr("Camera"),
            microphone: qsTr("Microphone"),
            notifications: qsTr("Notifications"),
            "persistent-storage": qsTr("Storage"),
            clipboard: qsTr("Clipboard")
        };
        var perms = d.permissions || [];
        for (var i = 0; i < perms.length; ++i) {
            var name = names[perms[i][0]] || perms[i][0];
            if (perms[i][1] === "allow")
                parts.push(qsTr("%1 allowed").arg(name));
            else if (perms[i][1] === "deny")
                parts.push(qsTr("%1 blocked").arg(name));
        }
        return parts.join(", ");
    }

    SilicaListView {
        anchors.fill: parent
        header: PageHeader {
            title: page.kind === "sites" ? qsTr("Site settings") : qsTr("Sites allowed over HTTP")
        }
        model: PacificList {
            id: sites
            kind: page.kind
            revision: Pacific.revision
        }
        ViewPlaceholder {
            enabled: sites.count === 0 && !sites.loading
            text: page.kind === "sites" ? qsTr("No site has its own settings") : qsTr("Every site is loaded over HTTPS first")
        }
        delegate: ListItem {
            id: item
            required property string itemId
            required property string title
            required property string subtitle
            required property string detail
            // As tall as its lines need at a large text size.
            contentHeight: Math.max(Theme.itemSizeMedium, rowText.height + 2 * Theme.paddingSmall)
            menu: ContextMenu {
                MenuItem {
                    text: page.kind === "sites" ? qsTr("Reset") : qsTr("Remove")
                    onClicked: item.remorseDelete(function () {
                        if (page.kind === "sites")
                            Pacific.clearSiteSettings(item.itemId);
                        else
                            Pacific.removeHttpsException(item.itemId);
                    })
                }
            }
            Column {
                id: rowText
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    width: parent.width
                    text: item.title
                    textFormat: Text.PlainText
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    text: page.kind === "sites" ? page.describe(item.detail) : item.subtitle
                    textFormat: Text.PlainText
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
