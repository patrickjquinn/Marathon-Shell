// SPDX-FileCopyrightText: 2013 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) DatePicker.qml
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places).
// Modified by Shipwright for Qt 6: directory imports ("private", "..") import the module by name.
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (4 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: the day delegate's colour tolerates a null `model` or `datePicker` (Qt 6 re-evaluates it while the delegate is destroyed).

import QtQuick 2.0
import Sailfish.Silica 1.0
import "private/DatePicker.js" as DatePickerScript
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: was import "private"
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below


// Note DatePicker uses month range 1-12, while JS Date uses month range 0-11,
// so the month must be converted accordingly in all uses of JS Date values.

SilicaControl {
    id: datePicker

    readonly property int year: date.getFullYear()
    readonly property int month: date.getMonth()+1
    readonly property int day: date.getDate()
    property real leftMargin: screen.sizeCategory > KeelSilica.Screen.Medium ? Theme.horizontalPageMargin : 0
    property real rightMargin: screen.sizeCategory > KeelSilica.Screen.Medium ? Theme.horizontalPageMargin : 0

    property date date: new Date()
    property string dateText: Qt.formatDate(date)
    property alias viewMoving: view.viewMovingImmediate

    property bool daysVisible
    property bool weeksVisible: screen.sizeCategory > KeelSilica.Screen.Medium
    property bool monthYearVisible: true
    readonly property int weekColumnWidth: weekLabel.width + Theme.paddingMedium
    readonly property int dayRowHeight: weekLabel.height + Theme.paddingMedium
    readonly property int cellWidth: (width - leftMargin - rightMargin - (weeksVisible ? weekColumnWidth : 0)) / 7
    property int cellHeight: cellWidth

    property Component modelComponent
    property Component delegate: Component {
        MouseArea {
            width: datePicker.cellWidth
            height: datePicker.cellHeight

            Label {
                anchors.centerIn: parent
                text: model.day.toLocaleString()
                font.bold: model.day === datePicker._today.getDate()
                            && model.month === datePicker._today.getMonth()+1
                            && model.year === datePicker._today.getFullYear()
                color: {
                    if (!model || !datePicker) return palette.secondaryColor // Modified by Shipwright for Qt 6: `model` and `datePicker` are null while the delegate is destroyed
                    if (pressed && containsMouse || model.day === datePicker.day
                            && model.month === datePicker.month
                            && model.year === datePicker.year) {
                        return palette.highlightColor
                    } else if (model.month === model.primaryMonth) {
                        return palette.primaryColor
                    }
                    return palette.secondaryColor
                }
            }

            function updateHighlight() {
                datePicker._highlightedDate = pressed && containsMouse
                        ? new Date(model.year, model.month-1, model.day,12,0,0)
                        : undefined
            }

            onPressedChanged: updateHighlight()
            onContainsMouseChanged: updateHighlight()
            onClicked: datePicker.date = new Date(model.year, model.month-1, model.day,12,0,0)
        }
    }

    default property alias pickerContent: viewChild.data

    property date _today: new Date()
    property var _highlightedDate
    property bool _changingDate
    property bool _changeWithoutAnimation
    property bool _loadNonVisibleGridsImmediately: true
    property real _gridLeftMargin: weeksVisible ? Theme.paddingMedium : leftMargin + Theme.paddingMedium
    property alias _gridView: view  // for testing

    signal updateModel(variant modelObject, variant fromDate, variant toDate, int primaryMonth)

    function showMonth(month, year) {
        if (month < 1 || month > 12) {
            console.log("DatePicker: showMonth() given invalid month:", month)
            return
        }
        if (month == datePicker.month && year == datePicker.year) {
            return
        }
        date = _validDate(year, month, day)
    }

    function _showMonth(month, year) {
        for (var i = 0; i < monthModel.count; i++) {
            var y = monthModel.get(i).year
            var m = monthModel.get(i).month
            if (y === year && m === month) {
                if (i === view.currentIndex) {
                    return
                }

                if (view.pathItemCount == 1) {
                    break
                }

                var prevIndex = ((view.currentIndex - 1) + view.count) % view.count
                if (i === prevIndex) {
                    if (_changeWithoutAnimation) {
                        view.positionViewAtIndex(prevIndex, PathView.Center)
                        _changeWithoutAnimation = false
                    } else {
                        interactivityPrevention.restart()
                        view.decrementCurrentIndex()
                    }
                    return
                }
                var nextIndex = (view.currentIndex + 1) % view.count
                if (i === nextIndex) {
                    if (_changeWithoutAnimation) {
                        view.positionViewAtIndex(nextIndex, PathView.Center)
                        _changeWithoutAnimation = false
                    } else {
                        interactivityPrevention.restart()
                        view.incrementCurrentIndex()
                    }
                    return
                }
            }
        }
        // the month is not one of current/prev/next displayed months, just reload all the views
        monthModel.update(view.currentIndex, year, month)
    }

    function _validDate(year, month, day) {
        return new Date(year, month - 1, Math.min(day, DatePickerScript._maxDaysForMonth(month, year)), 12, 0, 0)
    }

    function _loadNonVisibleGrids() {
        view.loadNonVisibleGrids()
    }

    onDateChanged: {
        _changingDate = true
        var _year = date.getFullYear()
        var _month = date.getMonth() + 1
        _showMonth(_month, _year)
        _changingDate = false
    }

    width: KeelSilica.Screen.width
    height: cellHeight * 6 + (daysVisible ? dayRowHeight : 0)

    Timer {
        id: interactivityPrevention

        interval: view.highlightMoveDuration
    }

    // This label is used only to determine the width of the week column
    Label {
        id: weekLabel

        //: Used to show week text and week number: %1 == weeknumber
        //% "week %1"
        text: qsTrId("components-la-week_and_weeknumber").arg(52)
        font.pixelSize: Theme.fontSizeExtraSmall
        visible: false
    }

    ListModel {
        id: monthModel

        function update(fromIndex, fromYear, fromMonth) {
            if (fromMonth < 1 || fromMonth > 12) {
                console.warn("DatePicker: date is invalid")
                return
            }
            // show current month and the next
            var index = fromIndex
            var m = fromMonth
            var y = fromYear
            for (var i = 0; i < count - 1; i++) {
                _updateMonth(index, y, m)
                index = (index + 1) % count
                m += 1
                if (m > 12) {
                    y += 1
                    m = 1
                }
            }
            // previous item shows the previous month
            index = ((fromIndex - 1) + count) % count
            m = fromMonth - 1
            if (m >= 1) {
                _updateMonth(index, fromYear, m)
            } else {
                _updateMonth(index, fromYear - 1, 12)
            }
        }

        function _updateMonth(index, y, m) {
            var data = get(index)
            if (data.year === y && data.month === m) {
                return
            }
            // needsUpdate helps avoid painting twice for two property changes
            setProperty(index, 'needsUpdate', false)
            set(index, {'year': y, 'month': m})
            setProperty(index, 'needsUpdate', true)
        }

        ListElement { year: -1; month: -1; needsUpdate: false }
        ListElement { year: -1; month: -1; needsUpdate: false }
        ListElement { year: -1; month: -1; needsUpdate: false }
    }

    SlideshowView {
        id: view

        property bool viewMovingImmediate: view.moving || ((view.offset - Math.floor(view.offset)) != 0.)
        property bool noUpdateDelegate

        function loadNonVisibleGrids() {
            if (pathItemCount == 1) {
                // tell PathView to generate the rest of the grid delegates
                pathItemCount = 3
            }
        }

        clip: true

        // prevent double tap from stopping just initiated month change
        interactive: !interactivityPrevention.running

        // Prevent PathView from generating all three calendar grids initially; just create the current grid
        pathItemCount: 1

        // We must slightly delay setting noUpdateDelegate back to false using a timer, as viewMovingImmediate
        // becomes false before the final view frame is painted.  So, if we don't delay, we get a jump on the
        // final frame
        onViewMovingImmediateChanged: {
            if (viewMovingImmediate == false)
                noUpdateDelegateTimer.restart()
            else
                noUpdateDelegate = true
        }

        Timer {
            id: noUpdateDelegateTimer

            interval: 32
            onTriggered: {
                if (false == view.viewMovingImmediate)
                    view.noUpdateDelegate = false
            }
        }

        width: parent.width
        height: parent.height
        itemWidth: view.width + (weeksVisible ? 0 : weekColumnWidth) - (leftMargin + rightMargin)/2 + Theme.paddingLarge
        itemHeight: view.height
        model: monthModel

        preferredHighlightBegin: pathItemCount == 1 ? (weeksVisible ? 0.9999 : 1.0 - weekColumnWidth / 2 / itemWidth)
                                                    : (weeksVisible ? 0.5 : 0.5 - weekColumnWidth / 2 / (itemWidth * 3))
        preferredHighlightEnd: preferredHighlightBegin

        Timer {
            id: createNonVisibleGridsTimer

            interval: 100
            onTriggered: {
                view.loadNonVisibleGrids()
            }
        }

        Component.onCompleted: {
            monthModel.update(view.currentIndex, datePicker.year, datePicker.month)
            if (datePicker._loadNonVisibleGridsImmediately) {
                createNonVisibleGridsTimer.start()
            }
        }

        delegate: DateGrid {
            id: gridDelegate

            property bool modelNeedsUpdate: model.needsUpdate
            property bool viewMoving: view.noUpdateDelegate

            Binding {
                target: gridDelegate
                property: "needsUpdate"
                when: model.index == 0      // update initially displayed grid immediately
                      || (view.pathItemCount == 3 && gridDelegate.PathView.onPath)  // update other grids when rendered
                value: gridDelegate.modelNeedsUpdate
                       && (!gridDelegate.viewMoving || (gridDelegate.x <= view.width && (gridDelegate.x + gridDelegate.width) > 0))
            }

            width: view.width + (weeksVisible ? 0 : weekColumnWidth)
            height: view.height
            weekColumnWidth: datePicker.weekColumnWidth
            daysVisible: datePicker.daysVisible
            monthYearVisible: datePicker.monthYearVisible
            displayedYear: model.year
            displayedMonth: model.month
            selectedDate: datePicker.date
            cellWidth: datePicker.cellWidth
            cellHeight: datePicker.cellHeight
            highlightedDate: datePicker._highlightedDate
            modelComponent: datePicker.modelComponent
            delegate: datePicker.delegate

            // Modified by Shipwright for Qt 6: signal parameter declared
            onUpdateModel: function(modelObject, fromDate, toDate, primaryMonth) { datePicker.updateModel(modelObject, fromDate, toDate, primaryMonth) }
        }

        onCurrentIndexChanged: {
            var data = monthModel.get(currentIndex)
            monthModel.update(currentIndex, data.year, data.month)
            if (!_changingDate) {
                datePicker.date = _validDate(data.year, data.month, datePicker.day)
            }
        }

        children: Item {
            id: viewChild

            anchors.fill: parent
            z: view.count + 1
        }
    }
}
