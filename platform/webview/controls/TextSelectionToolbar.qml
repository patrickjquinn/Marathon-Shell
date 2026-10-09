// SPDX-FileCopyrightText: 2016 - 2020 Jolla Ltd
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2016 - 2020 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.WebView.Controls 1.0

Row {
    id: root

    property TextSelectionController controller

    property bool isPhoneNumber: controller && controller.isPhoneNumber
    property bool hasSearch: controller && controller.searchUri !== ""
    property bool selectAllEnabled
    property bool portrait: true

    readonly property var defaultButtons: {
        var buttons = []

        if (isPhoneNumber) {
            buttons.push({
                "icon": "image://theme/icon-m-answer",
                //% "Call"
                "label": qsTrId("sailfish_components_webview_textselection-la-call"),
                "action": function () {
                    clear()
                    call()
                }
            })
        }
        buttons.push({
            "icon": "image://theme/icon-m-share",
            //% "Share"
            "label": qsTrId("sailfish_components_webview_textselection-la-share"),
            "action": function () {
                clear()
                share()
            }
        })

        if (selectAllEnabled) {
            buttons.push(
                {
                    "icon": "image://theme/icon-m-select-all",
                    //% "Select All"
                    "label": qsTrId("sailfish_components_webview_textselection-la-select_all"),
                    "action": selectAll
                })
        }

        if (hasSearch) {
            buttons.push({
                "icon": "image://theme/icon-m-search",
                //% "Search"
                "label": qsTrId("sailfish_components_webview_textselection-la-search"),
                "action": function () {
                    clear()
                    search()
                }
            })
        }
        buttons.push({
            "icon": "image://theme/icon-m-input-remove",
            //% "Clear"
            "label": qsTrId("sailfish_components_webview_textselection-la-clear"),
            "action": clear
        })

        return buttons
    }

    property var buttons: defaultButtons

    property int fontSize: {
        var size = Theme.fontSizeTiny

        if (!portrait && size > Theme.fontSizeTinyBase) {
            var string = ""
            for (var i = 0; i < buttons.length; ++i) {
                string = string + (buttons[i].label || "")
            }

            var requiredWidth = metrics.advanceWidth(string) + (buttons.length * (Theme.itemSizeSmall + (2 * horizontalSpacing)))

            if (requiredWidth >= width - leftPadding - rightPadding) {
                size = Theme.fontSizeTinyBase
            }
        }
        return size
    }
    property real horizontalSpacing

    signal call
    signal search
    signal share

    function selectAll() {
        if (controller) {
            controller.selectAll()
        }
    }

    function clear() {
        if (controller) {
            controller.clearSelection()
        }
    }

    height: Theme.itemSizeSmall

    FontMetrics {
        id: metrics
        font.pixelSize: Theme.fontSizeTiny
    }

    Repeater {
        id: repeater

        model: root.buttons
        delegate: root.portrait ? portraitButtonDelegate : landscapeButtonDelegate
    }

    Component {
        id: portraitButtonDelegate

        IconButton {
            id: portraitButton

            width: (root.width - root.leftPadding - root.rightPadding) / Math.max(1, repeater.count)
            height: root.height
            icon.source: modelData.icon
            icon.anchors.verticalCenterOffset: -(portraitLabel.baselineOffset - Theme.paddingSmall) / 2
            onClicked: root.buttons[index].action()

            Label {
                id: portraitLabel

                x: (portraitButton.width - width) / 2
                y: portraitButton.icon.y + portraitButton.icon.height - Theme.paddingSmall

                text: modelData.label
                font.pixelSize: root.fontSize
            }
        }
    }
    Component {
        id: landscapeButtonDelegate

        IconButton {
            id: landscapeButton

            width: (root.width - root.leftPadding - root.rightPadding) / Math.max(1, repeater.count)
            height: root.height
            icon.source: modelData.icon
            icon.anchors.horizontalCenterOffset: -(Math.min(landscapeLabel.width,
                                                            landscapeLabel.implicitWidth) + root.horizontalSpacing) / 2

            onClicked: root.buttons[index].action()

            Label {
                id: landscapeLabel

                x: landscapeButton.icon.x + landscapeButton.icon.width + root.horizontalSpacing
                y: (landscapeButton.height - height) / 2
                width: landscapeButton.width - landscapeButton.icon.width - (2 * root.horizontalSpacing)
                text: modelData.label
                font.pixelSize: root.fontSize
                truncationMode: TruncationMode.Fade
            }
        }
    }
}
