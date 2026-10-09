/****************************************************************************************
**
** Copyright (C) 2019 - 2020 Open Mobile Platform LLC.
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

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import "Util.js" as Util

SilicaMouseArea {
    id: root

    property int tabIndex: (model && model.index !== undefined) ? model.index : -1
    property int tabCount: parent && parent.tabCount || 0
    property bool isCurrentTab: _tabView && _tabView.currentIndex >= 0 && _tabView.currentIndex === tabIndex

    property alias title: titleLabel.text
    property alias icon: highlightImage

    property int titleFontSize: parent && parent.buttonFontSize || Theme.fontSizeLarge
    property int count

    property Item _tabView: parent && parent.tabView || null

    readonly property Item _page: _tabView ? _tabView._page : null
    readonly property bool _portrait: _page && _page.isPortrait

    readonly property Item _tabItem: _tabView ? (_tabView.exposedItems, _tabView.itemAt(tabIndex)) : null
    property alias contentItem: contentColumn
    property real _extraMargin: parent && parent.extraMargin || 0
    // contentWidth is used to calculate TabButtonRow width except of extraMargin
    property real contentWidth: 2 * Theme.paddingLarge + contentColumn.implicitWidth
                                + (bubble.active && highlightImage.width === 0 ? bubble.width : 0)
    implicitWidth: contentWidth
                + (root.tabIndex == 0 ? _extraMargin : 0)
                + (root.tabIndex == root.tabCount - 1 ? _extraMargin : 0)

    implicitHeight: Math.max(_portrait ? Theme.itemSizeLarge : Theme.itemSizeSmall,
                             contentColumn.implicitHeight + 2 * (_portrait ? Theme.paddingLarge : Theme.paddingMedium))

    highlighted: pressed && containsMouse

    onClicked: {
        if (_tabView && tabIndex >= 0) {
            _tabView.moveTo(tabIndex)
        }
    }

    VariantInterpolator {
        id: colorInterpolator

        from: root.palette.primaryColor
        to: root.palette.highlightColor

        progress: {
            if (!root._tabView || !root._tabItem) {
                return 0
            } else if (isCurrentTab && !root._tabView.dragging) {
                return 1
            } else {
                return 1 - Math.abs(root._tabItem.x / (root._tabView.width + root._tabView.horizontalSpacing))
            }
        }
    }

    Column {
        id: contentColumn

        x: {
            if (root.tabCount > 1 && root.tabIndex == 0) {
                return root.width - width - Theme.paddingMedium
            } else if (root.tabCount > 1 && root.tabIndex == root.tabCount - 1) {
                return Theme.paddingMedium
            } else {
                return ((root.width - width) / 2)
                        - (highlightImage.status === Image.Ready ? bubble.width * 0.5 : 0)
            }
        }

        y: (root.height - height) / 2

        HighlightImage {
            id: highlightImage

            anchors.horizontalCenter: parent.horizontalCenter
            highlighted: root.highlighted || root.isCurrentTab
        }

        Label {
            id: titleLabel

            x: (contentColumn.width - width) / 2
            color: highlighted ? palette.highlightColor : colorInterpolator.value
            font.pixelSize: highlightImage.status === Image.Ready ? Theme.fontSizeTiny : root.titleFontSize
        }
    }

    Loader {
        id: bubble

        x: highlightImage.status === Image.Ready
                ? (contentColumn.width - width + highlightImage.width) / 2
                : contentColumn.x + contentColumn.width + Theme.dp(4)
        y: Theme.paddingLarge
        active: root.count > 0
        asynchronous: true
        opacity: root.highlighted ? 0.8 : 1.0

        sourceComponent: Component {
            Rectangle {
                color: root.palette.highlightBackgroundColor
                width: bubbleLabel.text ? Math.max(bubbleLabel.implicitWidth + Theme.paddingSmall*2, height)
                                        : Theme.paddingMedium + Theme.paddingSmall
                height: bubbleLabel.text ? bubbleLabel.implicitHeight : Theme.paddingMedium + Theme.paddingSmall
                radius: Theme.dp(2)

                Label {
                    id: bubbleLabel

                    text: {
                        if (root.count < 0) {
                            return ""
                        } else if (root.count > 99) {
                            return "99+"
                        } else {
                            return root.count
                        }
                    }

                    anchors.centerIn: parent
                    font.pixelSize: Theme.fontSizeTiny
                    font.bold: true
                }
            }
        }
    }
}
