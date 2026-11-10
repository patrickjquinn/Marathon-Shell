// SPDX-FileCopyrightText: 2026 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2026 Jolla Mobile Ltd
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.6
import Sailfish.Silica 1.0

DatePickerDialog {
    id: datePickerDialog

    property int winId
    property string requestId
    property QtObject requestState
    property QtObject contentItem
    property var initialValue
    property var minimumValue
    property var maximumValue
    property var stepValue
    property var stepBase
    property bool dateTime
    property var timeValue
    property var timeMinimum
    property var timeMaximum
    property bool _completed

    date: _initialDate()
    canAccept: _isSelectable(selectedDate)
    acceptDestination: dateTime ? Qt.resolvedUrl("WebTimePickerDialog.qml") : undefined
    acceptDestinationAction: PageStackAction.Replace
    acceptDestinationProperties: ({ "winId": winId, "requestId": requestId,
                                   "dateTime": true, "selectedDate": selectedDate,
                                   "timeValue": timeValue, "timeMinimum": timeMinimum,
                                   "timeMaximum": timeMaximum, "stepValue": stepValue,
                                   "stepBase": stepBase })

    function closeCancelledRequest() {
        if (requestState && !requestState.active
                && status === PageStatus.Active && !pageStack.busy) {
            _finish(false, new Date(NaN))
            pageStack.pop()
        }
    }

    function _number(value) {
        return typeof value === "number" && isFinite(value) ? value : NaN
    }

    function _dateMilliseconds(year, month, day) {
        if (Math.floor(year) !== year || Math.floor(month) !== month
                || Math.floor(day) !== day || year < 1 || month < 1 || month > 12
                || day < 1 || day > 31) {
            return NaN
        }

        var result = new Date(0)
        result.setUTCFullYear(year, month - 1, day)
        result.setUTCHours(0, 0, 0, 0)
        if (result.getUTCFullYear() !== year || result.getUTCMonth() !== month - 1
                || result.getUTCDate() !== day) {
            return NaN
        }
        return result.getTime()
    }

    function _localDate(milliseconds) {
        var utcDate = new Date(milliseconds)
        var localDate = new Date(0)
        localDate.setFullYear(utcDate.getUTCFullYear(), utcDate.getUTCMonth(),
                              utcDate.getUTCDate())
        localDate.setHours(12, 0, 0, 0)
        return localDate
    }

    function _valueMilliseconds() {
        var year
        var month
        var day
        if (initialValue && typeof initialValue === "object") {
            year = Number(initialValue.year)
            month = Number(initialValue.month)
            day = Number(initialValue.day)
        } else {
            var match = /^(\d{4,})-(\d{2})-(\d{2})$/.exec(String(initialValue || ""))
            if (match) {
                year = Number(match[1])
                month = Number(match[2])
                day = Number(match[3])
            }
        }
        return _dateMilliseconds(year, month, day)
    }

    function _nearestSelectable(milliseconds) {
        // A datetime day need not have a valid midnight. Keep it if any time
        // within its bounds is selectable, rather than rounding into yesterday.
        if (_isSelectable(_localDate(milliseconds))) return milliseconds

        var minimum = _number(dateTime ? timeMinimum : minimumValue)
        var maximum = _number(dateTime ? timeMaximum : maximumValue)
        var step = _number(stepValue)
        var base = _number(stepBase)
        if (isNaN(base)) base = 0
        if (!isNaN(step) && step > 0) {
            minimum = base + Math.ceil((minimum - base) / step) * step
            maximum = base + Math.floor((maximum - base) / step) * step
            milliseconds = base + Math.round((milliseconds - base) / step) * step
        }
        if (!isNaN(minimum)) milliseconds = Math.max(milliseconds, minimum)
        if (!isNaN(maximum)) milliseconds = Math.min(milliseconds, maximum)
        return milliseconds
    }

    function _initialDate() {
        var milliseconds = _valueMilliseconds()
        if (isNaN(milliseconds)) {
            var today = new Date()
            milliseconds = _dateMilliseconds(today.getFullYear(), today.getMonth() + 1,
                                               today.getDate())
        }
        return _localDate(_nearestSelectable(milliseconds))
    }

    function _isSelectable(value) {
        if (!value || isNaN(value.getTime())) {
            return false
        }

        var milliseconds = _dateMilliseconds(value.getFullYear(), value.getMonth() + 1,
                                              value.getDate())
        var minimum = _number(dateTime ? timeMinimum : minimumValue)
        var maximum = _number(dateTime ? timeMaximum : maximumValue)
        var first = milliseconds
        var last = milliseconds + (dateTime ? 86400000 - 1 : 0)
        if (!isNaN(minimum)) first = Math.max(first, minimum)
        if (!isNaN(maximum)) last = Math.min(last, maximum)

        var step = _number(stepValue)
        if (!isNaN(step) && step > 0) {
            var base = _number(stepBase)
            if (isNaN(base)) {
                base = 0
            }
            first = base + Math.ceil((first - base) / step) * step
        }
        return first <= last
    }

    function _sendResponse(accepted, value) {
        if (contentItem) {
            contentItem.sendAsyncMessage("embedui:datepickerresponse",
                                         {
                                             "winId": winId,
                                             "id": requestId,
                                             "accepted": accepted,
                                             "year": accepted ? value.getFullYear() : 0,
                                             "month": accepted ? value.getMonth() + 1 : 0,
                                             "day": accepted ? value.getDate() : 0
                                         })
        }
    }

    function _finish(accepted, value) {
        if (_completed) {
            return
        }
        _completed = true
        _sendResponse(accepted, value)
    }

    Connections {
        target: requestState
        function onActiveChanged() { datePickerDialog.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }

    Connections {
        target: datePickerDialog
        function onStatusChanged() { datePickerDialog.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }

    Connections {
        target: pageStack
        function onBusyChanged() { datePickerDialog.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }

    Component.onDestruction: {
        if (!_completed) {
            _finish(false, new Date(NaN))
        }
        if (requestState) requestState.release()
    }

    onAccepted: {
        if (dateTime) {
            // Silica may destroy/recreate the preview when the year menu opens.
            // Only the accepted clock takes ownership of the live web request.
            acceptDestinationInstance.initialize(selectedDate)
            acceptDestinationInstance.contentItem = contentItem
            acceptDestinationInstance.requestState = requestState
            requestState = null
            _completed = true
        } else {
            _finish(true, selectedDate)
        }
    }

    onRejected: {
        _finish(false, new Date(NaN))
    }
}
