// SPDX-FileCopyrightText: 2013 Jolla Ltd
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** All rights reserved.
** 
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
** 
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/DateGrid.qml

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import "DatePicker.js" as DatePickerScript

SilicaControl {
    id: root

    property int displayedYear
    property int displayedMonth
    property date selectedDate
    property var highlightedDate
    property int weekStart: Qt.locale().firstDayOfWeek

    property real weekColumnWidth
    property bool needsUpdate
    property alias daysVisible: weekDays.visible
    property bool monthYearVisible

    property Component modelComponent
    property QtObject customModel
    property alias delegate: dateController.delegate

    property int cellWidth
    property int cellHeight
    property int _displayedMonthStartIndex: -1

    // for week column highlight cannot use week number of date because numbering is ISO-8601.
    // -> if locale uses saturaday or sunday to start week, the first items will belong to
    // previous week but highlighting number from above column would be strange.
    // done by having grid start as midnight and selected date as noon. should work even with DST changes.
    property date _properSelectedDate: {
        return new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate(), 12, 0)
    }
    property date _gridStartDate
    readonly property int _selectedDateRow: (_properSelectedDate - _gridStartDate) / (7*24*60*60*1000)

    signal updateModel(variant modelObject, variant fromDate, variant toDate, int primaryMonth)

    onNeedsUpdateChanged: {
        if (needsUpdate)
            loadMonth(displayedMonth, displayedYear)
    }

    onSelectedDateChanged: _resetSelectedDateBox(selectedDate, selectedDateBox)
    onHighlightedDateChanged: _resetSelectedDateBox(highlightedDate, highlightedDateBox)

    function _resetSelectedDateBox(highlightDate, highlightItem) {
        if (highlightDate !== undefined
                && highlightDate.getFullYear() == displayedYear
                && highlightDate.getMonth() + 1 == displayedMonth) {
            var index = _displayedMonthStartIndex + (highlightDate.getDate() - 1)
            var itemToHighlight = dateController.itemAt(index)
            if (itemToHighlight !== null) {
                highlightItem.target = itemToHighlight
            } else {
                // grid has not yet loaded
                highlightWait.start()
            }
        } else {
            highlightItem.target = null
        }
    }

    Timer {
        id: highlightWait

        interval: 100
        onTriggered: {
            _resetSelectedDateBox(selectedDate, selectedDateBox)
            _resetSelectedDateBox(highlightedDate, highlightedDateBox)
        }
    }

    function loadMonth(month, year) {
        // set the dates in the calendar grid; display 6 weeks
        var fromDate = DatePickerScript._getStartDateForMonthView(year, month, root.weekStart)
        _loadDateGrid(fromDate, 7 * 6)       // we display 6 weeks

        _displayedMonthStartIndex = 0
        while (fromDate.getMonth() + 1 !== month) {
            fromDate.setDate(fromDate.getDate() + 1)
            _displayedMonthStartIndex++
        }

        // set the week numbers
        // find first monday on first row and get week numbers from that on. Note: iso-8601 week number also for en_US.
        // for locales starting week from sunday or saturday, this will mean first one or two items on a row will be
        // with wrong number.
        var firstMonday = DatePickerScript._getStartDateForMonthView(year, month, root.weekStart)
        while (firstMonday.getDay() != 1) {
            firstMonday.setDate(firstMonday.getDate() + 1)
        }

        DatePickerScript._loadWeekNumbers(weekNumberModel, firstMonday.getFullYear(),
                                          firstMonday.getMonth() + 1, firstMonday.getDate(), 6)

        var theMonth = new Date(year, month - 1, 1, 12)
        monthName.text = Format.formatDate(theMonth, Format.MonthNameStandaloneShort)
        monthYear.text = Qt.formatDateTime(theMonth, "yyyy")
    }

    function _loadDateGrid(fromDate, totalDays) {
        _gridStartDate = new Date(fromDate.getFullYear(), fromDate.getMonth(), fromDate.getDate())
        if (modelComponent !== null && customModel === null) {
            customModel = modelComponent.createObject(root)
        }
        if (customModel !== null) {
            var toDate = new Date(fromDate)
            toDate.setDate(toDate.getDate() + totalDays)
            root.updateModel(customModel, fromDate, toDate, root.displayedMonth)
        } else {
            var dt = new Date(fromDate)
            var i
            if (dateModel.count == 0) {
                for (i = 0; i < totalDays; i++) {
                    dateModel.append({'year': dt.getFullYear(),
                                      'month': dt.getMonth()+1,
                                      'day': dt.getDate(),
                                      'primaryMonth': root.displayedMonth})
                    dt.setDate(dt.getDate() + 1)
                }
            } else {
                for (i = 0; i < totalDays; i++) {
                    dateModel.set(i, {'year': dt.getFullYear(),
                                      'month': dt.getMonth()+1,
                                      'day': dt.getDate(),
                                      'primaryMonth': root.displayedMonth})
                    dt.setDate(dt.getDate() + 1)
                }
            }
        }
        _resetSelectedDateBox(selectedDate, selectedDateBox)
    }

    Label {
        id: monthName

        anchors {
            right: weekColumn.right
            top: weekColumn.top
            topMargin: root.cellHeight - font.pixelSize/2
        }
        visible: monthYearVisible
        color: palette.secondaryHighlightColor
    }

    Label {
        id: monthYear

        anchors {
            right: weekColumn.right
            top: weekColumn.top
            topMargin: root.cellHeight*2 - font.pixelSize/2
        }
        visible: monthYearVisible
        color: palette.secondaryHighlightColor
    }

    Column {
        id: weekColumn

        anchors.top: grid.top
        x: weeksVisible ? leftMargin : 0
        width: root.weekColumnWidth - Theme.paddingMedium

        Repeater {
            model: ListModel {
                id: weekNumberModel
            }

            onCountChanged: _resetSelectedDateBox(selectedDate, selectedDateBox)

            Item {
                width: weekColumn.width
                height: root.cellHeight

                Label {
                    id: weekLabel

                    //: Used to show week text and week number: %1 == weeknumber
                    //% "week %1"
                    text: qsTrId("components-la-week_and_weeknumber").arg(model.weekNumber.toLocaleString())
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: palette.highlightColor
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    opacity: model.index === _selectedDateRow ? 1.0 : Theme.opacityHigh
                }
            }
        }
    }

    ListModel {
        id: dateModel
    }

    Rectangle {
        id: selectedDateBox

        property Item target

        x: target ? grid.x + target.x + (cellWidth - target.width)/2 : 0
        y: target ? grid.y + target.y + (cellHeight - target.height)/2 : 0
        width: cellWidth
        height: cellHeight
        visible: !!target
        color: Theme.rgba(root.palette.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
        radius: 4
    }

    Rectangle {
        id: highlightedDateBox

        property Item target

        x: target ? grid.x + target.x + (cellWidth - target.width)/2 : 0
        y: target ? grid.y + target.y + (cellHeight - target.height)/2 : 0
        width: cellWidth
        height: cellHeight
        visible: !!target
        color: Theme.rgba(root.palette.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
        radius: 4
    }

    Row {
        id: weekDays

        anchors.left: grid.left

        Repeater {
            model: 7
            delegate: Label {
                // 2 Jan 2000 was a Sunday
                text: Qt.formatDateTime(new Date(2000, 0, 2 + root.weekStart + index, 12), "ddd")
                width: cellWidth
                font.pixelSize: Theme.fontSizeExtraSmall
                color: root.palette.highlightColor
                opacity: (new Date(2000, 0, 2 + root.weekStart + index, 12)).getDay() === selectedDate.getDay()
                         && selectedDate.getMonth()+1 == displayedMonth ? 1.0 : Theme.opacityHigh
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Grid {
        id: grid

        anchors {
            top: daysVisible ? weekDays.bottom : parent.top
            topMargin: daysVisible ? Theme.paddingMedium : 0
            left: weekColumn.right
            leftMargin: _gridLeftMargin
        }
        columns: 7

        Repeater {
            id: dateController
            model: root.customModel !== null ? root.customModel : dateModel
        }
    }
}
