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

Dialog {
    id: selectDialog

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
        function onActiveChanged() { selectDialog.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }

    Connections {
        target: pageStack
        function onBusyChanged() { selectDialog.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }

    onOpened: {
        for (var i=0; i < options.length; i++) {
            selectModel.append(options[i])
        }
    }

    onAccepted: {
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
    }

    onRejected: {
        contentItem.sendAsyncMessage("embedui:selectresponse", {"id": requestId, "result": -1})
    }

    ListModel {
        id: selectModel
    }

    SilicaListView {
        id: listView

        anchors.fill: parent
        model: selectModel

        header: DialogHeader {
            dialog: selectDialog
            //% "Select"
            acceptText: qsTrId("sailfish_components_webview_pickers-he-select")
            _glassOnly: true
        }

        section {
            property: "group"
            delegate: SectionHeader {
                text: section
            }
        }

        delegate: BackgroundItem {
            enabled: !disabled

            onClicked: selectModel.setProperty(index, "selected", !selected)

            Label {
                x: Theme.paddingLarge
                anchors.verticalCenter: parent.verticalCenter
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
