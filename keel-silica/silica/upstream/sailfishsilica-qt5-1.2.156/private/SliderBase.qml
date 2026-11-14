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

import QtQuick 2.4
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0

SilicaMouseArea {
    id: slider

    property real maximumValue: 1.0
    property real minimumValue: 0.0
    property real stepSize
    property real value: 0.0
    readonly property real sliderValue: Math.max(minimumValue, Math.min(maximumValue, value))
    property bool handleVisible: true
    property string valueText
    property alias label: labelText.text
    property bool down: pressed && !DragFilter.canceled && !_cancel
    property real leftMargin: Math.round(Screen.width/8)
    property real rightMargin: Math.round(Screen.width/8)

    property int colorScheme: palette.colorScheme
    property color color: Theme.lightPrimaryColor
    property color backgroundColor: palette.secondaryColor
    property color highlightColor: palette.highlightColor

    property color secondaryHighlightColor: palette.secondaryHighlightColor
    property color valueLabelColor: palette.primaryColor

    property bool _hasValueLabel: false
    property Item _valueLabel
    property real _oldValue
    property real _precFactor: 1.0

    property real _grooveWidth: Math.max(0, width - leftMargin - rightMargin)
    property bool _widthChanged
    property bool animateValue: true
    property bool _cancel

    property bool _componentComplete
    property int _extraPadding: Math.max(height - implicitHeight, 0) / 2

    property Item _highlightItem
    property Item _backgroundItem
    property Item _progressBarItem

    property int _backgroundBottomPadding: (Theme.itemSizeSmall - _backgroundItem.height) / 2
    // ascent enough to keep text in slider area
    property int _backgroundTopPadding: (slider._valueLabel != null && slider._valueLabel.visible)
                                        ? fontMetrics.ascent : _backgroundBottomPadding

    property real _highlightPadding

    property real _highlightX: leftMargin + _highlightPadding - _highlightItem.width/2
                               + (maximumValue > minimumValue
                                  ? (sliderValue - minimumValue) / (maximumValue - minimumValue)
                                    * (_grooveWidth - 2 * _highlightPadding)
                                  : 0)
    Behavior on _highlightX {
        enabled: !_widthChanged && animateValue
        SmoothedAnimation {
            duration: 300
            velocity: Theme.dp(1500)
        }
    }

    property real _progressBarWidth: (sliderValue - minimumValue)
                                     / (maximumValue - minimumValue)
                                     * (_backgroundItem.width - _progressBarItem.height) + _progressBarItem.height
    Behavior on _progressBarWidth {
        enabled: !_widthChanged && animateValue
        SmoothedAnimation {
            duration: 300
            velocity: Theme.dp(1500)
        }
    }

    highlighted: down

    DragFilter.orientations: Qt.Vertical
    onPreventStealingChanged: if (preventStealing) slider.DragFilter.end()

    onStepSizeChanged: {
        // Avoid rounding errors.  We assume that the range will
        // be sensibly related to stepSize
        var decimial = Math.floor(stepSize) - stepSize
        if (decimial < 0.001) {
            _precFactor = Math.pow(10, 7)
        } else if (decimial < 0.1) {
            _precFactor = Math.pow(10, 4)
        } else {
            _precFactor = 1.0
        }
    }

    implicitHeight: labelText.visible ? (_backgroundTopPadding + _backgroundItem.height / 2
                                         + 2 * Theme.paddingMedium + labelText.height)
                                      : (_backgroundTopPadding + _backgroundItem.height + _backgroundBottomPadding)

    onWidthChanged: updateWidth()
    onLeftMarginChanged: updateWidth()
    onRightMarginChanged: updateWidth()

    // changing the width of the slider shouldn't animate the slider bar/handle
    function updateWidth() {
        _widthChanged = true
        _grooveWidth = Math.max(0, width - leftMargin - rightMargin)
        _widthChanged = false
    }

    function cancel() {
        _cancel = true
        value = _oldValue
    }

    drag {
        target: draggable
        minimumX: leftMargin - _highlightItem.width/2
        maximumX: slider.width - rightMargin - _highlightItem.width/2
        axis: Drag.XAxis
        onActiveChanged: if (drag.active && !slider.DragFilter.canceled) slider.DragFilter.end()
    }

    function _updateValueToDraggable() {
        if (width > (leftMargin + rightMargin)) {
            var pos = draggable.x + _highlightItem.width/2 - leftMargin
            value = _calcValue((pos / _grooveWidth) * (maximumValue - minimumValue) + minimumValue)
        }
    }

    function _calcValue(newVal) {
        if (newVal <= minimumValue) {
            return minimumValue
        }

        if (stepSize > 0.0) {
            var offset = newVal - minimumValue
            var intervals = Math.round(offset / stepSize)
            newVal = Math.round((minimumValue + (intervals * stepSize)) * _precFactor) / _precFactor
        }

        if (newVal > maximumValue) {
            return maximumValue
        }

        return newVal
    }

    onPressed: {
        slider.DragFilter.begin(mouse.x, mouse.y)
        _cancel = false
        _oldValue = value
        draggable.x = Math.min(Math.max(drag.minimumX, mouseX - _highlightItem.width/2), drag.maximumX)
    }

    onReleased: {
        if (!_cancel) {
            _updateValueToDraggable()
            _oldValue = value
        }
    }

    onCanceled: {
        slider.DragFilter.end()
        value = _oldValue
    }

    onValueTextChanged: {
        if (valueText && !_hasValueLabel) {
            _hasValueLabel = true
            var valueIndicatorComponent = Qt.createComponent("SliderValueLabel.qml")
            if (valueIndicatorComponent.status === Component.Ready) {
                _valueLabel = valueIndicatorComponent.createObject(slider, { "slider": slider })
            } else {
                console.log(valueIndicatorComponent.errorString())
            }
        }
    }

    FontMetrics {
        id: fontMetrics
        font.pixelSize: Theme.fontSizeHuge
    }

    Item {
        id: draggable

        width: _highlightItem.width
        height: _highlightItem.height
        onXChanged: {
            if (_cancel || slider.DragFilter.canceled) {
                return
            }
            if (slider.drag.active) {
                _updateValueToDraggable()
            }
        }
    }

    Label {
        id: labelText

        visible: text.length
        font.pixelSize: Theme.fontSizeSmall
        color: slider.highlighted ? slider.secondaryHighlightColor : slider.backgroundColor
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: _backgroundItem.verticalCenter
        anchors.topMargin: Theme.paddingMedium
        width: Math.min(paintedWidth, parent.width - 2*Theme.paddingMedium)
        truncationMode: TruncationMode.Fade
    }

    states: State {
        name: "invalidRange"
        when: _componentComplete && minimumValue >= maximumValue
        PropertyChanges {
            target: _progressBarItem
            width: _progressBarItem.height
        }
        PropertyChanges {
            target: slider
            enabled: false
            opacity: Theme.opacityHigh
        }
        StateChangeScript {
            script: console.log("Warning: Slider.maximumValue needs to be higher than Slider.minimumValue")
        }
    }

    Component.onCompleted: {
        _componentComplete = true
    }
}
