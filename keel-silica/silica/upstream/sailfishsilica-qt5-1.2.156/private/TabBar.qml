/****************************************************************************************
**
** Copyright (C) 2020 Open Mobile Platform LLC.
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

SilicaControl {
    id: root

    property alias model: _tabButtons.model
    property alias delegate: _tabButtons.delegate
    readonly property Item _tabView: Util.findParentWithProperty(root, '__silica_tab_view')
    property bool _oversize: flickable.contentWidth > flickable.width
    property bool _isFooter: _tabView && _tabView.hasFooter
    readonly property bool _vanillaStyle: !_styleConfig || _styleConfig.value === "vanilla"
    property QtObject _styleConfig
    readonly property int _currentIndex: _tabView ? _tabView.currentIndex : 0
    readonly property Item _currentTabButton: _currentIndex >= 0 && _currentIndex < _tabButtons.count
            ? (tabRow.children, _tabButtons.itemAt(_currentIndex))
            : null

    readonly property real _normalizedDragDistance: _tabView && _tabView.dragging
            ? _tabView._distance / _tabView.width + _tabView.horizontalSpacing
            : 0
    readonly property int _dragDirection: {
        if (_normalizedDragDistance < 0) {
            return -1
        } else if (_normalizedDragDistance > 0) {
            return 1
        }
        return 0
    }
    readonly property Item _anchoredTabButton: _dragDirection != 0
                                               && _currentIndex >= 0 && _currentIndex < _tabButtons.count
                                               ? _tabButtons.itemAt(_dragDirection < 0
                                                                    ? (_currentIndex + 1) % _tabButtons.count
                                                                    : (root._currentIndex + _tabButtons.count - 1)
                                                                      % _tabButtons.count)
                                               : null

    property string titleRole: "title"
    property string countRole: "count"
    property string iconRole: "icon"
    property int topMargin: (!_isFooter
                             && _tabView._page.orientation == Orientation.Portrait
                             && Screen.topCutout.height > 0)
                            ? Math.max(0, Screen.topCutout.height - Theme.paddingLarge)
                            : 0

    height: flickable.height

    Flickable {
        id: flickable

        width: parent.width
        height: tabRow.height + root.topMargin

        contentWidth: tabRow.width
        boundsBehavior: Flickable.StopAtBounds

        contentX: {
            var x = 0
            var tabButton = root._currentTabButton
            if (tabButton) {
                x = Math.max(0,
                             Math.min(contentWidth - width,
                                      tabButton.x + ((tabButton.width - width) / 2)))

                var anchoredButton = root._anchoredTabButton
                if (anchoredButton) {
                    var anchoredX = Math.max(0, Math.min(
                                contentWidth - width, anchoredButton.x + ((anchoredButton.width - width) / 2)))

                    x = (x * (1 - Math.abs(root._normalizedDragDistance)))
                            + (anchoredX * Math.abs(root._normalizedDragDistance))
                }
            }
            return x
        }

        Behavior on contentX {
            id: contentXBehavior

            enabled: root._tabView && root._tabView.moving

            SmoothedAnimation {
                duration: 250
                velocity: Theme.pixelRatio * 200
                easing.type: Easing.InOutQuad
            }
        }

        Row {
            id: tabRow

            readonly property alias tabView: root._tabView
            readonly property alias tabCount: _tabButtons.count
            readonly property real extraMargin: {
                var buttons = tabRow.children
                var buttonsWidth = 0
                for (var i = 0; i < buttons.length; i++) {
                    buttonsWidth += buttons[i].contentWidth || 0
                }
                return Math.max(0, flickable.width - buttonsWidth) / 2
            }
            readonly property int buttonFontSize: {
                if (root._tabView) {
                    var buttons = tabRow.children
                    var availableWidth = root._tabView.width
                    var largeWidth = 0
                    for (var i = 0; i < buttons.length; i++) {
                        var button = buttons[i]
                        largeWidth = largeWidth + largeFontMetrics.advanceWidth(button.title) + Theme.paddingMedium * 2
                                   + (button.count >= 0 ? tinyFontMetrics.advanceWidth(button.count) + Theme.paddingSmall * 2
                                                        : 0)
                        if (largeWidth > availableWidth) {
                            return Theme.fontSizeMedium
                        }
                    }
                }

                return Theme.fontSizeLarge
            }

            y: root.topMargin

            Repeater {
                id: _tabButtons

                TabButton {
                    id: tabButton

                    _tabView: root._tabView
                    _extraMargin: tabRow.extraMargin
                    tabCount: _tabButtons.count
                    titleFontSize: tabRow.buttonFontSize

                    title: model[root.titleRole] || ""
                    icon.source: model[root.iconRole] || ""
                    count: model[root.countRole] || 0
                }
            }
        }

        Rectangle {
            x: {
                if (!root._currentTabButton) {
                    return 0
                } else if (root._vanillaStyle) {
                   return root._currentTabButton.x + root._currentTabButton.contentItem.x
                }

                return root._currentTabButton.x
            }
            y: {
                if (!root._currentTabButton || !root._vanillaStyle) {
                    return root._isFooter ? 0 : flickable.height - height + root.topMargin

                } else if (root._isFooter) {
                    return root._currentTabButton.contentItem.y - height - Theme.paddingMedium
                }

                return root._currentTabButton.contentItem.y
                        + root._currentTabButton.contentItem.height
                        + Theme.paddingMedium
                        + root.topMargin
            }
            width: {
                if (!root._currentTabButton) {
                    return 0
                } else if (root._vanillaStyle) {
                    return root._currentTabButton.contentItem.width
                }

                return root._currentTabButton.width
            }

            height: Theme._lineWidth
            color: root.palette.highlightColor

            Behavior on x {
                enabled: contentXBehavior.enabled
                SmoothedAnimation { duration: 200; easing.type: Easing.InOutQuad }
            }
            Behavior on y {
                enabled: contentXBehavior.enabled
                SmoothedAnimation { duration: 200; easing.type: Easing.InOutQuad }
            }
            Behavior on width {
                enabled: contentXBehavior.enabled
                SmoothedAnimation { duration: 200; easing.type: Easing.InOutQuad }
            }
        }
    }

    OpacityRampEffect {
        id: leftRamp

        sourceItem: flickable
        enabled: root._oversize && flickable.contentX > 0

        direction: OpacityRamp.RightToLeft

        slope: Math.max(1 + 6 * root.width / Screen.width,
                        root.width / Math.max(1, flickable.contentX))
        offset: 1 - 1 / slope
    }

    OpacityRampEffect {
        sourceItem: leftRamp.enabled ? leftRamp : flickable
        enabled: root._oversize && flickable.contentX < flickable.contentWidth - flickable.width

        direction: OpacityRamp.LeftToRight

        slope: Math.max(1 + 6 * root.width / Screen.width,
                        root.width / Math.max(1, flickable.contentWidth - flickable.width - flickable.contentX))
        offset: 1 - 1 / slope
    }

    Rectangle {
        id: horizontalLine

        visible: !root._vanillaStyle
        color: Theme.rgba(root.palette.highlightColor, Theme.opacityLow)
        y: root._isFooter ? 0 : root.height - height
        width: root.width
        height: Theme._lineWidth

    }

    FontMetrics {
        id: largeFontMetrics
        font.pixelSize: Theme.fontSizeLarge
    }

    FontMetrics {
        id: tinyFontMetrics
        font.pixelSize: Theme.fontSizeTiny
    }

    Component.onCompleted: {
        // Avoid hard dependency to Configuration module
        _styleConfig = Qt.createQmlObject("import Nemo.Configuration 1.0;
                                        import QtQuick 2.0;

                                        ConfigurationValue {
                                            id: tabBarStyle
                                            key: '/desktop/sailfish/silica/tab_bar_style'
                                            defaultValue: 'vanilla'
                                        }", root, 'TabStyleConfig')
    }

}
