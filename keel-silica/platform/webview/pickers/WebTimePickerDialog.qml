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

Dialog {
    id: timePickerDialog

    property int winId
    property string requestId
    property QtObject requestState
    property QtObject contentItem
    property var initialValue
    property var minimumValue
    property var maximumValue
    property var timeValue
    property var timeMinimum
    property var timeMaximum
    property var stepValue
    property var stepBase
    property bool dateTime
    property date selectedDate
    property bool _completed
    property int _second
    property int _millisecond

    allowedOrientations: Orientation.All
    canAccept: _isSelectable(clock.hour, clock.minute)

    function _number(value) {
        return typeof value === "number" && isFinite(value) ? value : NaN
    }

    function _dayStart() {
        if (!dateTime) return 0
        var date = new Date(0)
        date.setUTCFullYear(selectedDate.getFullYear(), selectedDate.getMonth(),
                            selectedDate.getDate())
        date.setUTCHours(0, 0, 0, 0)
        return date.getTime()
    }

    function _valueMilliseconds() {
        var hour, minute, second, millisecond
        if (timeValue && typeof timeValue === "object") {
            hour = timeValue.hour
            minute = timeValue.minute
            second = timeValue.second || 0
            millisecond = timeValue.millisecond || 0
        } else {
            var match = /(?:T|^)(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?$/.exec(timeValue || "")
            if (match) {
                hour = Number(match[1])
                minute = Number(match[2])
                second = Number(match[3] || 0)
                millisecond = Number(((match[4] || "") + "000").slice(0, 3))
            }
        }
        if (!isFinite(hour) || !isFinite(minute)) {
            var now = new Date()
            hour = now.getHours()
            minute = now.getMinutes()
            second = millisecond = 0
        }
        return hour * 3600000 + minute * 60000 + second * 1000 + millisecond
    }

    function _initialTime() {
        var start = _dayStart()
        var value = start + _valueMilliseconds()
        var minimum = _number(timeMinimum)
        var maximum = _number(timeMaximum)
        var ranges = !dateTime && minimum > maximum
                ? [[start, maximum], [minimum, start + 86400000 - 1]]
                : [[isNaN(minimum) ? start : Math.max(start, minimum),
                    isNaN(maximum) ? start + 86400000 - 1 : Math.min(start + 86400000 - 1, maximum)]]
        var step = _number(stepValue)
        var base = _number(stepBase)
        if (isNaN(base)) base = 0
        var nearest = NaN
        for (var i = 0; i < ranges.length; ++i) {
            var lower = ranges[i][0]
            var upper = ranges[i][1]
            var candidate = value
            if (!isNaN(step) && step > 0) {
                lower = base + Math.ceil((lower - base) / step) * step
                upper = base + Math.floor((upper - base) / step) * step
                candidate = base + Math.round((value - base) / step) * step
            }
            if (lower > upper) continue
            candidate = Math.max(lower, Math.min(upper, candidate))
            if (isNaN(nearest) || Math.abs(candidate - value) < Math.abs(nearest - value)) {
                nearest = candidate
            }
        }
        return (isNaN(nearest) ? value : nearest) - start
    }

    function _isSelectable(hour, minute) {
        var value = _dayStart() + hour * 3600000 + minute * 60000
                + _second * 1000 + _millisecond
        var minimum = _number(timeMinimum)
        var maximum = _number(timeMaximum)
        var below = !isNaN(minimum) && value < minimum
        var above = !isNaN(maximum) && value > maximum
        if (!dateTime && minimum > maximum ? below && above : below || above) return false
        var step = _number(stepValue)
        var base = _number(stepBase)
        if (isNaN(base)) base = 0
        return isNaN(step) || step <= 0 || (value - base) % step === 0
    }

    function initialize(date) {
        selectedDate = date
        var milliseconds = _initialTime()
        _second = Math.floor(milliseconds / 1000) % 60
        _millisecond = milliseconds % 1000
        clock.hour = Math.floor(milliseconds / 3600000)
        clock.minute = Math.floor(milliseconds / 60000) % 60
    }

    function _finish(accepted) {
        if (_completed || !requestState) return
        _completed = true
        if (contentItem) {
            contentItem.sendAsyncMessage("embedui:datepickerresponse", {
                "winId": winId, "id": requestId, "accepted": accepted,
                "year": dateTime ? selectedDate.getFullYear() : 0,
                "month": dateTime ? selectedDate.getMonth() + 1 : 0,
                "day": dateTime ? selectedDate.getDate() : 0,
                "hour": clock.hour, "minute": clock.minute,
                "second": _second, "millisecond": _millisecond
            })
        }
    }

    function closeCancelledRequest() {
        if (requestState && !requestState.active
                && status === PageStatus.Active && !pageStack.busy) {
            _finish(false)
            pageStack.pop()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        Column {
            id: content

            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader { }

            TimePicker {
                id: clock

                anchors.horizontalCenter: parent.horizontalCenter

                Label {
                    anchors.centerIn: parent
                    text: clock.timeText
                    font.pixelSize: Theme.fontSizeExtraLarge
                }
            }
        }
    }

    Connections {
        target: requestState
        function onActiveChanged() { timePickerDialog.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }
    Connections {
        target: timePickerDialog
        function onStatusChanged() { timePickerDialog.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }
    Connections {
        target: pageStack
        function onBusyChanged() { timePickerDialog.closeCancelledRequest() } // Modified by Shipwright for Qt 6
    }

    onAccepted: _finish(true)
    onRejected: _finish(false)
    Component.onCompleted: initialize(selectedDate)
    Component.onDestruction: {
        if (!_completed) _finish(false)
        if (requestState) requestState.release()
    }
}
