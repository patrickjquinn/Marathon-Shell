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

ListView {
    id: root

    property int currentYear: new Date().getFullYear()

    property int _clickedYear
    property Item _contextMenu
    property int _selectedYear

    signal monthActivated(int month, int year)

    anchors.fill: parent
    orientation: Qt.Vertical

    model: ListModel {
        Component.onCompleted: {
            // range of -100 to +50 years, rounded to nearest decades
            var start = root.currentYear - 100
            var end = root.currentYear + 50
            start = Math.round(start / 10) * 10
            end = Math.round(end / 10) * 10
            for (var i = start; i <= end; i++) {
                append({"year": i})
            }
            root.positionViewAtIndex(root.currentYear - start, ListView.Center)
        }
    }

    delegate: BackgroundItem {
        id: delegateItem

        property bool menuOpen: root._contextMenu !== null && root._contextMenu._open
        width: root.width
        height: (root._contextMenu != null && root._contextMenu.parent == delegateItem)
                ? root._contextMenu.height + yearLabel.height
                : yearLabel.height
        highlighted: down || (menuOpen && root._selectedYear == model.year)
        _backgroundColor: _showPress && !menuOpen ? highlightedColor : "transparent"
        onClicked: {
            root._clickedYear = model.year
            if (root._contextMenu === null)
                root._contextMenu = contextMenuComponent.createObject(root)
            root._selectedYear = model.year
            root._contextMenu.open(delegateItem)
        }

        Label {
            id: yearLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: model.year
            font.pixelSize: Theme.fontSizeHuge
            color: model.year == root.currentYear || highlighted
                   ? palette.highlightColor
                   : palette.primaryColor
        }
    }

    Component {
        id: contextMenuComponent

        ContextMenu {
            Grid {
                id: monthGrid

                columns: screen.sizeCategory > Screen.Medium || !isPortrait ? 6 : 3

                Repeater {
                    model: ListModel {
                        Component.onCompleted: {
                            // Use the 2nd day of the month rather than the 1st, as converting the
                            // JS date to QDateTime loses timezone data, so using the 1st may result
                            // in passing the last date of the previous month instead
                            var dt = new Date(2000, 0, 2)
                            for (var i=0; i<12; i++) {
                                append({"name": Format.formatDate(dt, Format.MonthNameStandalone)})
                                dt.setMonth(dt.getMonth() + 1)
                            }
                        }
                    }

                    BackgroundItem {
                        width: root.width / monthGrid.columns
                        height: Theme.itemSizeHuge

                        onClicked: {
                            root._contextMenu.close()
                            root.monthActivated(model.index + 1, root._clickedYear)
                        }

                        Label {
                            id: monthNumberLabel

                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                verticalCenter: parent.verticalCenter
                                verticalCenterOffset: -monthNameLabel.height/2
                            }
                            font.pixelSize: Theme.fontSizeHuge
                            text: (model.index >= 9 ? "" : "0") + (model.index + 1)
                            color: palette.secondaryHighlightColor
                        }
                        Label {
                            id: monthNameLabel

                            anchors {
                                top: monthNumberLabel.bottom
                                horizontalCenter: parent.horizontalCenter
                            }
                            width: parent.width - Theme.paddingSmall
                            horizontalAlignment: Text.AlignHCenter
                            fontSizeMode: Text.HorizontalFit
                            font.pixelSize: Theme.fontSizeMedium
                            text: model.name
                            color: palette.secondaryHighlightColor
                        }
                    }
                }
            }
        }
    }
}
