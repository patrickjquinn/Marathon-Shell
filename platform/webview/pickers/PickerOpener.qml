// SPDX-FileCopyrightText: 2016 Jolla Ltd
// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2016 Jolla Ltd.
** Contact: Raine Makelainen <raine.makelainen@jolla.com>
** Copyright (c) 2021 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.2
import Sailfish.WebEngine 1.0

QtObject {
    id: root

    property var pageStack
    property QtObject contentItem
    readonly property var listeners: [ "embed:colorpicker",
                                       "embed:datepicker",
                                       "embed:datepickerabort",
                                       "embed:filepicker",
                                       "embed:selectasync",
                                       "embed:selectabort",
                                       "embed:downloadpicker" ]

    // Defer compilation of picker components
    readonly property string _multiSelectComponentUrl: Qt.resolvedUrl("MultiSelectDialog.qml")
    readonly property string _singleSelectComponentUrl: Qt.resolvedUrl("SingleSelectPage.qml")
    readonly property string _colorPickerPageUrl: Qt.resolvedUrl("WebColorPickerPage.qml")
    readonly property string _datePickerDialogUrl: Qt.resolvedUrl("WebDatePickerDialog.qml")
    readonly property string _timePickerDialogUrl: Qt.resolvedUrl("WebTimePickerDialog.qml")
    readonly property string _filePickerComponentUrl: Qt.resolvedUrl("PickerCreator.qml")
    readonly property string _downloadPickerComponentUrl: Qt.resolvedUrl("DownloadPicker.qml")
    property Component _filePickerComponent

    property var _selectRequests: ({})
    property Component _selectRequestComponent: Component {
        QtObject {
            property bool active: true
            property string requestId

            function release() {
                delete root._selectRequests[requestId]
                destroy()
            }
        }
    }

    property var _dateRequests: ({})
    property Component _dateRequestComponent: Component {
        QtObject {
            property bool active: true
            property string requestId

            function release() {
                delete root._dateRequests[requestId]
                destroy()
            }
        }
    }

    signal downloadPickerClosed

    // Returns true if message is handled.
    function message(topic, data) {
        if (!handlesMessage(topic)) {
            return false
        }

        if (!contentItem) {
            console.warn("PickerOpener has no contentItem. Assign / Bind contentItem for each PickerOpener.")
            return false
        }

        if (!pageStack) {
            console.log("PickerOpener has no pageStack. Add missing binding.")
            return false
        }

        var winId = data.winId
        switch (topic) {
        case "embed:colorpicker": {
            pageStack.animatorPush(_colorPickerPageUrl,
                                   { "winId": winId,
                                     "contentItem": contentItem,
                                     "initialColor": data.initialColor,
                                     "defaultColors": data.defaultColors })
            break
        }
        case "embed:datepicker": {
            var dateRequestId = String(data.id)
            var dateRequest = _dateRequestComponent.createObject(root,
                                                                 { "requestId": dateRequestId })
            _dateRequests[dateRequestId] = dateRequest
            pageStack.animatorPush(data.type === "time" ? _timePickerDialogUrl : _datePickerDialogUrl,
                                   { "winId": winId,
                                     "requestId": dateRequestId,
                                     "requestState": dateRequest,
                                     "contentItem": contentItem,
                                     "initialValue": data.value,
                                     "minimumValue": data.min,
                                     "maximumValue": data.max,
                                     "stepValue": data.step,
                                     "stepBase": data.stepBase,
                                     "dateTime": !!data.dateTime,
                                     "timeValue": data.timeValue,
                                     "timeMinimum": data.timeMin,
                                     "timeMaximum": data.timeMax })
            break
        }
        case "embed:datepickerabort": {
            var cancelledDateRequest = _dateRequests[String(data.id)]
            if (cancelledDateRequest) cancelledDateRequest.active = false
            break
        }
        case "embed:selectasync": {
            var requestId = String(data.id)
            var request = _selectRequestComponent.createObject(root, { "requestId": requestId })
            _selectRequests[requestId] = request
            pageStack.animatorPush(
                        data.multiple ? _multiSelectComponentUrl : _singleSelectComponentUrl,
                        { "options": data.options, "contentItem": contentItem,
                          "requestId": requestId, "requestState": request })
            break
        }
        case "embed:selectabort": {
            var cancelledRequest = _selectRequests[String(data.id)]
            if (cancelledRequest) cancelledRequest.active = false
            break
        }
        case "embed:filepicker": {
            if (!_filePickerComponent) {
                _filePickerComponent = Qt.createComponent(_filePickerComponentUrl)
            }

            if (_filePickerComponent.status === Component.Ready) {
                _filePickerComponent.createObject(pageStack, {
                                                      "pageStack": pageStack,
                                                      "winId": winId,
                                                      "contentItem": contentItem,
                                                      "mimeType": data.mimeType,
                                                      "mode": data.mode})
            } else if (_filePickerComponent.status === Component.Error) {
                // Component development time issue, component creation should newer fail.
                console.warn("PickerOpener failed to create PickerOpener: ", _filePickerComponent.errorString())
            }
            break
        }
        case "embed:downloadpicker": {
            var page = pageStack.push(_downloadPickerComponentUrl, {
                                          "data": data,
                                          "closedCallback": function() {
                                              root.downloadPickerClosed()
                                          }
                                      })
            if (!page) {
                return false
            }
            break
        }
        }
        // If we end up here, message has been handled.
        return true
    }

    function handlesMessage(topic) {
        return listeners.indexOf(topic) >= 0
    }

    Component.onCompleted: {
        if (contentItem) {
            for (var i = 0; i < listeners.length; ++i) {
                contentItem.addMessageListener(listeners[i])
            }
        } else {
            console.log("PickerOpener has no contentItem. Each created WebView/WebPage",
                        "instance can have own PickerOpener. Add missing binding.")
        }
    }
}
