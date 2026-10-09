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

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import "private"

Dialog {
    id: datePickerDialog

    // Items from the Harmattan component interface

    readonly property int year: date.getFullYear()
    readonly property int month: date.getMonth()+1
    readonly property int day: date.getDate()
    readonly property date selectedDate: !_showYearSelectionFirst && datePickerLoader.item
                                         ? datePickerLoader.item.selectedDate
                                         : new Date("")

    //property string acceptButtonText      // not supported
    //property string rejectButtonText      // not supported
    //property string titleText             // not supported
    //property int minimumYear              // not supported
    //property int maximumYear              // not supported

    property string dateText
    property date date

    property bool _showYearSelectionFirst: _invalidDate
    property bool _invalidDate: date.toString() === "Invalid Date"
    property Page _yearSelectionPage
    property date _initialDate: date
    property bool _initialDateSet
    property QtObject _revealAnim
    property bool _delayedLoadNonVisibleGrids
    property bool _largeScreen: screen.sizeCategory > Screen.Medium

    canAccept: !isNaN(selectedDate.getTime())
    forwardNavigation: _showYearSelectionFirst ? false : !_belowTop
    allowedOrientations: Orientation.All

    Loader {
        id: initialYearSelectionLoader

        width: parent.width
        height: parent.height
        sourceComponent: _showYearSelectionFirst ? yearSelectionViewComponent : undefined
    }

    Loader {
        id: datePickerLoader

        x: _showYearSelectionFirst ? parent.width : 0
        width: parent.width
        height: parent.height
        asynchronous: _showYearSelectionFirst
        sourceComponent: datePickerComponent
        onLoaded: {
            if (_delayedLoadNonVisibleGrids) {
                _delayedLoadNonVisibleGrids = false
                item.loadNonVisibleGrids()
            }
        }
    }

    onStatusChanged: {
        if (!_showYearSelectionFirst && status == PageStatus.Active) {
            if (datePickerLoader.status == Loader.Ready) {
                datePickerLoader.item.loadNonVisibleGrids()
            } else {
                _delayedLoadNonVisibleGrids = true
            }
        }
    }

    Component {
        id: revealAnimComponent

        SequentialAnimation {
            ParallelAnimation {
                NumberAnimation {
                    target: initialYearSelectionLoader
                    property: "x"
                    to: -datePickerDialog.width
                    duration: 500
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: datePickerLoader
                    property: "x"
                    to: 0
                    duration: 500
                    easing.type: Easing.OutQuad
                }
            }
            ScriptAction {
                script: {
                    datePickerDialog._showYearSelectionFirst = false
                    datePickerLoader.item.loadNonVisibleGrids()
                }
            }
        }
    }

    // This is shown when showYearSelectionFirst=true and this view needs to be shown first
    Component {
        id: yearSelectionViewComponent

        YearMonthMenu {
            anchors.fill: parent
            currentYear: _invalidDate ? new Date().getFullYear() : date.getFullYear()
            onMonthActivated: {
                _initialDate = new Date(year, month - 1, 1, 12, 0, 0)
                _initialDateSet = true
                if (_revealAnim == null) {
                    _revealAnim = revealAnimComponent.createObject(datePickerDialog)
                }
                _revealAnim.start()
            }
        }
    }

    // This is shown when the 'Year' ValueButton is clicked
    Component {
        id: yearSelectionPageComponent

        Page {
            property alias currentYear: menu.currentYear
            signal monthActivated(int month, int year)

            allowedOrientations: datePickerDialog.allowedOrientations

            YearMonthMenu {
                id: menu

                onMonthActivated: parent.monthActivated(month, year)
            }
        }
    }

    Component {
        id: datePickerComponent

        SilicaFlickable {
            id: contentFlickable

            anchors.fill: parent
            pressDelay: 0
            contentHeight: Math.max(yearPicker.y + yearPicker.height + Theme.paddingLarge, height)

            property alias selectedDate: datePicker.date
            property alias selectedDateText: datePicker.dateText
            property bool dateAboveGrid: _largeScreen || isPortrait

            function loadNonVisibleGrids() {
                datePicker._loadNonVisibleGrids()
            }

            VerticalScrollDecorator {}

            DialogHeader {
                id: header

                dialog: datePickerDialog
                spacing: !_largeScreen && isLandscape ? 0 : Theme.paddingLarge
            }

            BackgroundItem {
                id: yearPicker

                anchors {
                    top: header.bottom
                    left: dateAboveGrid ? parent.left : datePicker.right
                    right: parent.right
                }
                height: dateLabel.height + 2*Theme.paddingSmall

                onClicked: {
                    if (_yearSelectionPage == null) {
                        _yearSelectionPage = yearSelectionPageComponent.createObject(datePickerDialog,
                                {"currentYear": datePicker.year})
                        _yearSelectionPage.monthActivated.connect(function(month, year) {
                            datePicker.showMonth(month, year)
                            pageStack.pop()
                        })
                    } else {
                        _yearSelectionPage.currentYear = datePicker.year
                    }
                    pageStack.animatorPush(_yearSelectionPage)
                }

                Label {
                    id: dateLabel

                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: dateAboveGrid ? Theme.horizontalPageMargin : Theme.paddingMedium
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    font.pixelSize: _largeScreen ? Theme.fontSizeExtraLarge : Theme.fontSizeLarge
                    text: Format.formatDate(datePicker.date, Format.DateLong)
                    wrapMode: Text.Wrap
                    horizontalAlignment: dateAboveGrid ? Text.AlignHCenter : Text.AlignRight
                }
            }

            DatePicker {
                id: datePicker

                anchors {
                    top: dateAboveGrid ? yearPicker.bottom : header.bottom
                    topMargin: dateAboveGrid ? Theme.paddingLarge : 0
                    horizontalCenter: dateAboveGrid ? parent.horizontalCenter : undefined
                    left: dateAboveGrid ? undefined : parent.left
                }
                // Show week column on larger displays or smaller displays in landscape.
                weeksVisible: _largeScreen || isLandscape
                daysVisible: true
                monthYearVisible: false
                width: Math.min(parent.width, Screen.width + (_largeScreen
                                                              ? (isLandscape ? -Theme.horizontalPageMargin*2 : 0)
                                                              : (isLandscape ? weekColumnWidth : 0)))
                cellHeight: !_largeScreen && isLandscape ? Theme.itemSizeExtraSmall : cellWidth
                leftMargin: isLandscape ? Theme.horizontalPageMargin : (_largeScreen ? Theme.horizontalPageMargin*2 : 0)
                rightMargin: isLandscape ? Theme.horizontalPageMargin : (_largeScreen ? Theme.horizontalPageMargin*2 : 0)
                date: _initialDateSet
                      ? datePickerDialog._initialDate
                      : (datePickerDialog.date.toString() !== "Invalid Date") ? datePickerDialog.date : new Date()

                // Don't want the datepicker to scroll to the set date because we are already
                // animating the datepicker into view
                _changeWithoutAnimation: datePickerDialog._showYearSelectionFirst

                // Avoid stuttering when the dialog transitions into view
                _loadNonVisibleGridsImmediately: false
            }

            MouseArea {
                anchors {
                    top: dateAboveGrid ? datePicker.bottom : yearPicker.bottom
                    left: dateAboveGrid ? parent.left : yearPicker.left
                    right: parent.right
                    bottom: parent.bottom
                }
                onClicked: {
                    flickHintAnim.start()
                }
            }
            SequentialAnimation {
                id: flickHintAnim

                NumberAnimation {
                    target: contentFlickable
                    property: "contentX"
                    to: 30
                    duration: 300
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: contentFlickable
                    property: "contentX"
                    to: 0
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    onDone: {
        if (result == DialogResult.Accepted) {
            date = datePickerLoader.item.selectedDate
            dateText = datePickerLoader.item.selectedDateText
        }
    }
}
