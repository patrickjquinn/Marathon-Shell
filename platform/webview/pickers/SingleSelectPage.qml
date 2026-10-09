// SPDX-FileCopyrightText: 2013-2016 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (C) 2013-2016 Jolla Ltd.
** Contact: Dmitry Rozhkov <dmitry.rozhkov@jollamobile.com>
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: selectPage

    // input data
    property QtObject requestState
    property string requestId
    property var options
    property QtObject contentItem

    Component.onDestruction: {
        if (requestState) requestState.release()
    }

    function closeCancelledRequest() {
        if (requestState && !requestState.active
                && status === PageStatus.Active && !pageStack.busy) {
            contentItem.sendAsyncMessage("embedui:selectresponse", {"id": requestId, "result": -1})
            pageStack.pop()
        }
    }

    onStatusChanged: closeCancelledRequest()

    Connections {
        target: requestState
        function onActiveChanged() { selectPage.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }

    Connections {
        target: pageStack
        function onBusyChanged() { selectPage.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }

    Component.onCompleted: {
        for (var i=0; i < options.length; i++) {
            selectModel.append(options[i])
            if (options[i]["selected"]) {
                selectModel.selectedIndex = options[i]["index"]
            }
        }
    }

    function selected() {
        var result = []
        var item

        for (var i = 0; i < selectModel.count; i++) {
            item = selectModel.get(i)
            result.push({
                "selected": item.selected,
                "index": item.index
            })
        }
        contentItem.sendAsyncMessage("embedui:selectresponse", {"id": requestId, "result": result})
        pageStack.pop()
    }

    on_NavigationChanged: {
        if (_navigation == PageNavigation.Back) {
            // swiped back
            contentItem.sendAsyncMessage("embedui:selectresponse", {"id": requestId, "result": -1})
        }
    }

    ListModel {
        id: selectModel

        property int selectedIndex: -1
    }

    SilicaListView {
        id: listView

        anchors.fill: parent
        model: selectModel

        header: PageHeader {
            //% "Select"
            title: qsTrId("sailfish_components_webview_pickers-he-select")
        }

        section {
            property: "group"
            delegate: SectionHeader {
                text: section
            }
        }

        delegate: BackgroundItem {
            height: Math.max(Theme.itemSizeSmall, selecetLabel.height + Theme.paddingMedium)

            enabled: !disabled

            onClicked: {
                if (selectModel.selectedIndex !== index) {
                    selectModel.setProperty(index, "selected", true)
                    selectModel.setProperty(selectModel.selectedIndex, "selected", false)
                    selectModel.selectedIndex = index
                }
                selectPage.selected()
            }

            Label {
                id: selecetLabel

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x*2
                wrapMode: Text.Wrap
                text: label
                color: {
                    if (disabled) {
                        return selected ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    } else {
                        return highlighted || selected ? Theme.highlightColor : Theme.primaryColor
                    }
                }
            }
        }
    }
}
