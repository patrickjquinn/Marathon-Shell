/****************************************************************************************
**
** Copyright (C) 2013-2018 Jolla Ltd.
** Copyright (C) 2020 Open Mobile Platform LLC.
**
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

/*

With labelVisible: true (default)

  -------------------------
  |                       |
  |     textTopMargin     |
  |                       |
  | - - - - - - - - - - - |
  |                       |
  |                       |
  |      contentItem      |
  |                       |
  |                       |
  ------------------------- background rule
  |  Theme.paddingSmall   |
  | - - - - - - - - - - - |
  |                       |
  |       labelItem       |
  |                       |
  | - - - - - - - - - - - |
  |  Theme.paddingSmall   |
  -------------------------


With labelVisible: false

  -------------------------
  |                       |
  |     textTopMargin     |
  |                       |
  | - - - - - - - - - - - |
  |                       |
  |                       |
  |                       |
  |     contentItem       |
  |                       |
  |                       |
  |                       |
  ------------------------- background rule
  |  Theme.paddingSmall   |
  | - - - - - - - - - - - |
  |  Theme.paddingSmall   |
  -------------------------

*/

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import "Util.js" as Util

TextBaseItem {
    id: textBase

    property string label
    property color color: textBase.highlighted ? palette.highlightColor : palette.primaryColor

    property color cursorColor: palette.primaryColor
    property alias placeholderText: placeholderTextLabel.text
    property alias placeholderColor: placeholderTextLabel.color

    property string description

    // internal
    property alias placeholderAnimationEnabled: placeholderBehavior.enabled
    property bool softwareInputPanelEnabled: true
    property bool errorHighlight: false
    // margins indicate the area around filled or underlined editor area
    property real textMargin: Theme.horizontalPageMargin
    property real textLeftMargin: textMargin + (leftItemContainer.active ? leftItemContainer.width + Theme.paddingMedium : 0)
    property real textRightMargin: textMargin

    property real textTopMargin: Theme.paddingSmall
    // paddings indicate how much space there is around text to the filled or underlined area
    property real textTopPadding: _filled ? Theme.paddingMedium : 0
    property real textLeftPadding: _filled ? Theme.paddingMedium : 0
    // note: not applied to rightItem.
    // if it's interactive, it can make sense to cover all the area to the end of the underline
    property real textRightPadding: _filled ? Theme.paddingMedium : 0

    // TODO: Change to use "placeholderTextLabel.lineHeight once merge request #298 is merged.
    readonly property real textVerticalCenterOffset: _totalTopMargins + placeholderTextLabel.height / 2
    property int selectionMode: TextInput.SelectCharacters
    property alias font: placeholderTextLabel.font
    property int focusOutBehavior: FocusBehavior.ClearItemFocus
    property bool autoScrollEnabled: true
    property int backgroundStyle: TextEditor.UnderlineBackground

    property Component background: Rectangle {
        x: textLeftMargin
        anchors.top: contentContainer.bottom
        width: parent.width - x - textRightMargin
        height: Math.round(Theme.pixelRatio)
        color: Theme.rgba(textBase._colorWithError, Theme.opacityHigh)
        visible: backgroundStyle != TextEditor.NoBackground

        Rectangle {
            id: focusHighlight

            property real focusLevel

            color: textBase._colorWithError
            height: parent.height + (_editor.activeFocus
                                     ? Math.round(Theme.pixelRatio) + (palette.colorScheme === Theme.DarkOnLight ? 1 : 0)
                                     : 0)
            width: focusLevel * parent.width
            states: State {
                name: "focused"
                when: _editor.activeFocus
                PropertyChanges {
                    target: focusHighlight
                    focusLevel: 1.0
                }
            }
            transitions: Transition {
                to: "focused"
                NumberAnimation { property: "focusLevel"; duration: 150 }
            }
        }

        Rectangle {
            visible: textBase._filled
            anchors.bottom: parent.top
            width: parent.width
            height: contentContainer.height
            color: _editor.activeFocus ? Theme.highlightColor : Theme.primaryColor
            opacity: 0.1
        }
    }

    property alias leftItem: leftItemContainer.item
    property alias rightItem: rightItemContainer.item

    // TODO: Remove this wrongly-formulated property name once users have been migrated, and version incremented
    property alias enableSoftwareInputPanel: textBase.softwareInputPanelEnabled

    property bool _suppressPressAndHoldOnText
    property Item _backgroundItem
    readonly property bool _filled: backgroundStyle == TextEditor.FilledBackground
    property QtObject _feedbackEffect
    property var _appWindow: __silica_applicationwindow_instance
    property Item _flickable
    property alias _errorIcon: errorIcon

    property alias _flickableDirection: flickable.flickableDirection
    property rect _autoScrollCursorRect: Qt.rect(0, 0, 0, 0)

    property Item _scopeItem: textBase
    property alias editor: textBase._editor  //XXX Deprecated

    // JB#45671: Deprecate labelVisible
    property bool labelVisible: true
    property bool hideLabelOnEmptyField: true

    property Component labelComponent: defaultLabelComponent

    property Component defaultLabelComponent: Component {
        TextEditorLabel {
            width: parent.width
            editor: textBase
        }
    }

    property Item _labelItem
    readonly property color _colorWithError: textBase.errorHighlight ? palette.errorColor : color

    default property alias _children: contentContainer.data
    property alias contentItem: contentContainer
    property alias _placeholderTextLabel: placeholderTextLabel
    property bool focusOnClick: !readOnly
    property bool _singleLine
    readonly property bool _isEmpty: text.length === 0 && !_editor.inputMethodComposing
    readonly property real _bottomMargin: Theme.paddingSmall
                                          + (labelVisible
                                             ? labelItemContainer.height + labelItemContainer.anchors.bottomMargin
                                             : Theme.paddingSmall)
                                          + descriptionLabel.height

    function forceActiveFocus() { _editor.forceActiveFocus() }
    function cut() { _editor.cut() }
    function copy() { _editor.copy() }
    function paste() { _editor.paste() }
    function select(start, end) { _editor.select(start, end) }
    function selectAll() { _editor.selectAll() }
    function selectWord() { _editor.selectWord() }
    function deselect() { _editor.deselect() }
    function positionAt(mouseX, mouseY) {
        var translatedPos = mapToItem(_editor, mouseX, mouseY)
        return _editor.positionAt(translatedPos.x, translatedPos.y)
    }
    function positionToRectangle(position) {
        var rect = _editor.positionToRectangle(position)
        var translatedPos = mapFromItem(_editor, rect.x, rect.y)
        rect.x = translatedPos.x
        rect.y = translatedPos.y
        return rect
    }

    function _fixupScrollPosition() {
        scrollProxy.HorizontalAutoScroll.fixup()
        scrollProxy.VerticalAutoScroll.fixup()
        VerticalAutoScroll.fixup()
    }

    onHorizontalAlignmentChanged: {
        if (explicitHorizontalAlignment) {
            placeholderTextLabel.horizontalAlignment = horizontalAlignment
        }
    }
    onExplicitHorizontalAlignmentChanged: {
        if (explicitHorizontalAlignment) {
            placeholderTextLabel.horizontalAlignment = horizontalAlignment
        } else {
            placeholderTextLabel.horizontalAlignment = undefined
        }
    }

    function _updateBackground() {
        if (_backgroundItem) {
            _backgroundItem.destroy()
            _backgroundItem = null
        }
        if (!readOnly && background && background.status) {
            _backgroundItem = background.createObject(textBase)
            _backgroundItem.z = -1
        }
    }

    VerticalAutoScroll.keepVisible: activeFocus && autoScrollEnabled

    // If the TextArea/Field has an implicit height we may need to scroll an external flickable to
    // keep the cursor in view.
    VerticalAutoScroll.cursorRectangle: {
        if (!autoScrollEnabled || !activeFocus) {
            return undefined
        }
        var cursor = _editor.cursorRectangle
        var left = Math.max(0, contentContainer.x + _editor.x + cursor.x - (Theme.paddingLarge / 2))
        var right = Math.min(width, left + cursor.width + Theme.paddingLarge)
        var top = Math.max(0, contentContainer.y + _editor.y + cursor.y - (Theme.paddingLarge / 2))
        var bottom = Math.min(height, top + cursor.height + Theme.paddingLarge)

        return Qt.rect(left, top , right - left, bottom - top)
    }

    function _updateLabelItem() {
        if (_labelItem) {
            _labelItem.destroy()
            _labelItem = null
        }

        _labelItem = labelComponent.createObject(labelItemContainer)
    }

    signal clicked(variant mouse)
    signal pressAndHold(variant mouse)

    highlighted: _editor.activeFocus

    opacity: enabled ? 1.0 : Theme.opacityLow

    property int _totalTopMargins: textTopMargin + textTopPadding
    property int _totalLeftMargins: textLeftMargin + textLeftPadding
    property int _totalRightMargins: textRightMargin + textRightPadding
    property int _rightItemWidth: rightItemContainer.active ? rightItemContainer.width : 0
    property int _totalVerticalMargins: Theme.paddingMedium + _totalTopMargins
                                        + (labelVisible ? labelItemContainer.height : 0)
                                        + (descriptionLabel.text.length > 0 ? descriptionLabel.height : Theme.paddingSmall)

    implicitHeight: _editor.height + _totalVerticalMargins
    implicitWidth: parent ? parent.width : Screen.width

    _keyboardPalette: {
        if (palette.colorScheme !== Theme.colorScheme
                    || palette.highlightColor !== Theme.highlightColor) {
            return JSON.stringify({
                "colorScheme": palette.colorScheme,
                "highlightColor": palette.highlightColor.toString()
            })
        } else {
            return ""
        }
    }

    onBackgroundChanged: _updateBackground()
    onLabelComponentChanged: _updateLabelItem()
    Component.onCompleted: {
        if (!_backgroundItem) {
            _updateBackground()
        }
        if (!_labelItem) {
            _updateLabelItem()
        }

        // Avoid hard dependency to feedback - NOTE: Qt5Feedback doesn't support TextSelection effect
        _feedbackEffect = Qt.createQmlObject("import QtQuick 2.0; import QtFeedback 5.0; ThemeEffect { effect: ThemeEffect.PressWeak }",
                                             textBase, 'ThemeEffect')

        // calling ThemeEffect.supported initializes the feedback backend,
        // without the initialization here the first playback drops few frames
        if (_feedbackEffect && !_feedbackEffect.supported) {
            _feedbackEffect = null
        }
    }

    // This is the container item for the editor.  It is not the flickable because we want mouse
    // interaction to extend to the full bounds of the item but painting to be clipped so that
    // it doesn't exceed the margins or overlap with the label text.
    Item {
        id: contentContainer

        property alias contentX: flickable.contentX
        property alias contentY: flickable.contentY

        clip: flickable.interactive

        anchors {
            fill: parent
            leftMargin: textLeftMargin
            topMargin: textTopMargin
            rightMargin: textRightMargin + _rightItemWidth
            bottomMargin: textBase._bottomMargin
        }
    }

    Label {
        id: placeholderTextLabel

        text: textBase.label
        color: textBase.highlighted ? palette.secondaryHighlightColor : palette.secondaryColor

        opacity: textBase._isEmpty ? 1.0 : 0.0
        Behavior on opacity {
            id: placeholderBehavior
            FadeAnimation {}
        }
        truncationMode: TruncationMode.Fade
        anchors {
            left: parent.left; top: parent.top; right: parent.right
            leftMargin: _totalLeftMargins
            topMargin: _totalTopMargins
            rightMargin: _totalRightMargins + _rightItemWidth
        }
    }

    OpacityRampEffect {
        id: rampEffect

        offset: 1 - 1 / slope
        states: [
            State {
                name: "verticalOpacityRamp"
                when: flickable.verticalFlick
                PropertyChanges {
                    target: rampEffect
                    sourceItem: contentItem
                    transformOrigin: Item.Center
                    slope: 1 + 10 * textBase.width / Screen.width
                    direction: {
                        if (flickable.contentY === flickable.originY) {
                            return OpacityRamp.TopToBottom
                        } else if (flickable.contentHeight - flickable.height <= flickable.contentY) {
                            return OpacityRamp.BottomToTop
                        } else {
                            return OpacityRamp.BothEnds
                        }
                    }
                }
            },
            State {
                name: "horizontalOpacityRamp"
                when: flickable.horizontalFlick
                PropertyChanges {
                    target: rampEffect
                    sourceItem: contentItem
                    slope: 1 + 20 * textBase.width / Screen.width
                    direction: {
                        if (flickable.contentX === flickable.originX) {
                            return OpacityRamp.LeftToRight
                        } else if (flickable.contentWidth - flickable.width <= flickable.contentX) {
                            return OpacityRamp.RightToLeft
                        } else {
                            return OpacityRamp.BothSides
                        }
                    }
                }
            }
        ]
    }

    Flickable {
        id: flickable

        readonly property bool verticalFlick: _editor.height > (contentContainer.height - textTopPadding)
        readonly property bool horizontalFlick: _editor.width > (contentContainer.width - textLeftPadding - textRightPadding)

        anchors {
            fill: parent
            leftMargin: textLeftMargin
            topMargin: textTopMargin
            rightMargin: textRightMargin + _rightItemWidth
        }

        pixelAligned: true
        contentHeight: scrollProxy.height + textBase._bottomMargin
        contentWidth: scrollProxy.width + Theme.paddingSmall
        interactive: verticalFlick || horizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Item {
            id: scrollProxy

            width: textBase._editor.width + textLeftPadding + textRightPadding
            height: textBase._editor.height + textTopPadding

            HorizontalAutoScroll.animated: false
            HorizontalAutoScroll.cursorRectangle: textBase._editor.activeFocus && autoScrollEnabled
                                                  ? textBase._editor.cursorRectangle
                                                  : undefined
            HorizontalAutoScroll.leftMargin: Math.max(0, Math.min(
                        Theme.paddingLarge + Theme.paddingSmall,
                        textBase._editor.cursorRectangle.x))
            HorizontalAutoScroll.rightMargin: Math.max(0, Math.min(
                        Theme.paddingLarge + Theme.paddingSmall,
                        width - textBase._editor.cursorRectangle.x - textBase._editor.cursorRectangle.width))
                    + Theme.paddingSmall
            VerticalAutoScroll.animated: false
            VerticalAutoScroll.cursorRectangle: textBase._editor.activeFocus && autoScrollEnabled
                                                ? textBase._editor.cursorRectangle
                                                : undefined
            VerticalAutoScroll.topMargin: Math.max(0, Math.min(
                        Theme.paddingLarge / 2,
                        textBase._editor.cursorRectangle.y))
            VerticalAutoScroll.bottomMargin: Math.max(0, Math.min(
                        Theme.paddingLarge / 2,
                        height - textBase._editor.cursorRectangle.y - textBase._editor.cursorRectangle.height))
                    + textBase._bottomMargin // The interactive area of the flickable extends to the bottom of the root item. This part of the margin ensures the cursor never ventures into that space.
        }
    }

    MouseArea {
        id: mouseArea

        property real initialMouseX
        property real initialMouseY
        property bool hasSelection: _editor !== null && _editor.selectedText != ""
        property bool cursorHit
        property bool cursorGrabbed
        property bool handleGrabbed
        property bool textSelected
        property Item selectionStartHandle
        property Item selectionEndHandle
        property int cursorStepThreshold: Theme.itemSizeSmall / 2
        property real scaleFactor: 2
        property int scaleOffset: Theme.itemSizeSmall / 2
        property int scaleTopMargin: Theme.paddingLarge
        property int touchAreaSize: Theme.itemSizeExtraSmall
        property int moveThreshold: Theme.paddingMedium
        property int touchOffset

        function positionAt(mouseX, mouseY) {
            var clippedX = Math.min(Math.max(parent.anchors.leftMargin, mouseX), parent.width + parent.anchors.leftMargin)
            var clippedY = Math.min(Math.max(parent.anchors.topMargin, mouseY), parent.height + parent.anchors.topMargin)
            var translatedPos = mapToItem(_editor, clippedX, clippedY)
            translatedPos.x = Math.max(0, Math.min(_editor.width - 1, translatedPos.x))
            translatedPos.y = Math.max(0, Math.min(_editor.height - 1 , translatedPos.y))
            return _editor.positionAt(translatedPos.x, translatedPos.y)
        }

        function positionHit(position, mouseX, mouseY) {
            var rect = _editor.positionToRectangle(position)
            var translatedPos = mapToItem(_editor, mouseX, mouseY)
            return translatedPos.x > rect.x - touchAreaSize / 2
                    && translatedPos.x < rect.x + touchAreaSize / 2
                    && translatedPos.y > rect.y
                    && translatedPos.y < rect.y + Math.max(rect.height, touchAreaSize)
        }

        function moved(mouseX, mouseY) {
            return (Math.abs(initialMouseX - mouseX) > moveThreshold
                    || Math.abs(initialMouseY - mouseY) > moveThreshold)
        }

        function updateTouchOffsetAndScaleOrigin(reset) {
            if (_appWindow !== undefined) {
                var cursorRect = _editor.cursorRectangle
                var translatedPos = mapToItem(_appWindow._rotatingItem, mouseX, mouseY)
                var offset = Math.min(cursorRect.height / 2 + scaleOffset / scaleFactor,
                                      (translatedPos.y - scaleTopMargin) / scaleFactor - cursorRect.height / 2)
                if (reset || offset > touchOffset) {
                    touchOffset = offset
                }

                var cursorPos = _editor.mapToItem(_appWindow._rotatingItem, cursorRect.x, cursorRect.y)

                var originX = mouseArea.mapToItem(_appWindow._rotatingItem, mouseX, 0).x
                var originY = 0
                if (reset) {
                    originY = (cursorPos.y < (scaleFactor - 1) * cursorRect.height + scaleOffset + scaleTopMargin)
                            ? (scaleFactor * cursorPos.y - scaleTopMargin) / (scaleFactor - 1)
                            : cursorPos.y + cursorRect.height + scaleOffset / (scaleFactor - 1)
                } else {
                    var mappedOrigin = _appWindow.contentItem.mapToItem(_appWindow._rotatingItem,
                                                                        _appWindow._contentScale.origin.x,
                                                                        _appWindow._contentScale.origin.y)
                    var scaledCursorHeight = cursorRect.height * scaleFactor / (scaleFactor - 1)
                    if (cursorPos.y < scaleTopMargin) {
                        originY = Math.max(0, mappedOrigin.y - scaledCursorHeight)
                    } else if (cursorPos.y + scaleFactor * cursorRect.height + Theme.paddingMedium
                               > _appWindow._rotatingItem.height) {
                        originY = Math.min(_appWindow._rotatingItem.height, mappedOrigin.y + scaledCursorHeight)
                    } else {
                        originY = mappedOrigin.y
                    }
                }

                var mappedPos = _appWindow._rotatingItem.mapToItem(_appWindow.contentItem, originX, originY)
                _appWindow._contentScale.origin.x = mappedPos.x
                _appWindow._contentScale.origin.y = mappedPos.y
            }
        }

        function reset() {
            selectionTimer.stop()
            cursorHit = false
            cursorGrabbed = false
            handleGrabbed = false
            preventStealing = false
            textSelected = false
        }

        parent: flickable
        width: textBase.width
        height: textBase.height
        x: -parent.anchors.leftMargin
        y: -parent.anchors.topMargin
        enabled: textBase.enabled

        onPressed: {
            if (!_editor.activeFocus) {
                return
            }
            initialMouseX = mouseX
            initialMouseY = mouseY
            if (!hasSelection) {
                if (positionHit(_editor.cursorPosition, mouseX, mouseY)) {
                    cursorHit = true
                }
            } else if (positionHit(_editor.selectionStart, mouseX, mouseY)) {
                var selectionStart = _editor.selectionStart
                _editor.cursorPosition = _editor.selectionEnd
                _editor.moveCursorSelection(selectionStart, TextInput.SelectCharacters)
                handleGrabbed = true
                preventStealing = true
            } else if (positionHit(_editor.selectionEnd, mouseX, mouseY)) {
                var selectionEnd = _editor.selectionEnd
                _editor.cursorPosition = _editor.selectionStart
                _editor.moveCursorSelection(selectionEnd, TextInput.SelectCharacters)
                handleGrabbed = true
                preventStealing = true
            }
            if (!handleGrabbed) {
                selectionTimer.resetAndRestart()
            }
        }

        onClicked: {
            textBase.clicked(mouse)
        }
        onPressAndHold: {
            if (!_editor.activeFocus || !_suppressPressAndHoldOnText) {
                textBase.pressAndHold(mouse)
            }
        }

        onPositionChanged: {
            if (!handleGrabbed && !cursorGrabbed && moved(mouseX, mouseY)) {
                selectionTimer.stop()
                if (cursorHit) {
                    cursorGrabbed = true
                    preventStealing = true
                    Qt.inputMethod.commit()
                }
            }
            if (handleGrabbed || cursorGrabbed) {
                if (_appWindow !== undefined && _appWindow._contentScale.animationRunning) {
                    // Don't change the cursor position during animation
                    return
                }
                updateTouchOffsetAndScaleOrigin(false)
                var cursorPosition = mouseArea.positionAt(mouseX, mouseY - mouseArea.touchOffset)
                if (handleGrabbed) {
                    _editor.moveCursorSelection(cursorPosition, textBase.selectionMode)
                } else {
                    _editor.cursorPosition = cursorPosition
                }
            }
        }

        onReleased: {
            if (!handleGrabbed && !textSelected && !cursorGrabbed && containsMouse
                    && (focusOnClick || _editor.activeFocus)) {
                Qt.inputMethod.commit()
                var translatedPos = mouseArea.mapToItem(_editor, mouseX, mouseY)
                var cursorRect = _editor.positionToRectangle(_editor.cursorPosition)
                var cursorPosition = _editor.cursorPosition

                // TODO: RTL text should mirror these. at RTL/LTR text block borders should
                // avoid jumping cursor visually far away
                if (translatedPos.x < cursorRect.x && translatedPos.x > cursorRect.x - cursorStepThreshold
                        && translatedPos.y > cursorRect.y && translatedPos.y < cursorRect.y + cursorRect.height) {
                    // step one character backward (unless at line start)
                    if (cursorPosition > 0 && (_editor.positionToRectangle(cursorPosition - 1).x < cursorRect.x)) {
                        cursorPosition = _editor.cursorPosition - 1
                    }
                } else if (translatedPos.x > cursorRect.x + cursorRect.width
                           && translatedPos.x < cursorRect.x + cursorRect.width + cursorStepThreshold
                           && translatedPos.y > cursorRect.y && translatedPos.y < cursorRect.y + cursorRect.height) {
                    // step one character forward
                    if (_editor.positionToRectangle(cursorPosition + 1).x > cursorRect.x) {
                        cursorPosition = _editor.cursorPosition + 1
                    }
                }

                if (cursorPosition === _editor.cursorPosition) {
                    cursorPosition = mouseArea.positionAt(mouseX, mouseY)
                    // NOTE: check for line change might fail, but currently don't care for such minor case
                    if (cursorPosition > 1
                            && _editor.positionToRectangle(cursorPosition - 1).y === _editor.positionToRectangle(cursorPosition).y
                            && _editor.text.charAt(cursorPosition - 1) == ' '
                            && _editor.text.charAt(cursorPosition - 2) != ' '
                            && cursorPosition !== _editor.text.length) {
                        // space hit, move to the end of the previous word
                        cursorPosition--
                    }
                }
                _editor.cursorPosition = cursorPosition
                if (_editor.activeFocus) {
                    if (textBase.softwareInputPanelEnabled) {
                        Qt.inputMethod.show()
                    }
                } else {
                    _editor.forceActiveFocus()
                }
            }
            reset()
        }

        onCanceled: reset()

        onHasSelectionChanged: {
            if (selectionStartHandle === null) {
                selectionStartHandle = handleComponent.createObject(_editor)
                selectionStartHandle.start = true
            }
            if (selectionEndHandle === null) {
                selectionEndHandle = handleComponent.createObject(_editor)
                selectionEndHandle.start = false
            }
        }

        onHandleGrabbedChanged: {
            if (!handleGrabbed && _editor.selectedText !== "") {
                _editor.copy()
            }
        }
    }

    InverseMouseArea {
        anchors.fill: parent
        enabled: _editor.activeFocus && textBase.softwareInputPanelEnabled
        onClickedOutside: focusLossTimer.start()
    }

    Item {
        id: labelItemContainer

        anchors {
            left: parent.left; bottom: descriptionLabel.top; right: parent.right
            leftMargin: _totalLeftMargins
            rightMargin: _totalRightMargins
            bottomMargin: {
                if (descriptionLabel.text.length > 0) {
                    return 0
                } else {
                    return readOnly ? Theme.paddingMedium : Theme.paddingSmall
                }
            }
        }
        visible: labelVisible
        height: children.length > 0 ? children[0].height : 0
    }

    onDescriptionChanged: if (description.length > 0) descriptionLabel.text = description

    Label {
        id: descriptionLabel

        text: description
        wrapMode: Text.Wrap

        color: textBase.errorHighlight ? palette.errorColor
                                       : placeholderTextLabel.color

        font.pixelSize: Theme.fontSizeExtraSmall

        opacity: description.length > 0 ? 1.0 : 0.0
        Behavior on opacity { FadeAnimator {}}
        height: description.length > 0 ? implicitHeight : 0
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        bottomPadding: readOnly ? Theme.paddingMedium : Theme.paddingSmall
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: _totalLeftMargins
            rightMargin: textRightMargin
            bottomMargin: description.length > 0 && (textBase._isEmpty && textBase.hideLabelOnEmptyField)
                          ? labelItemContainer.height
                          : 0
        }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
    }

    Timer {
        id: selectionTimer

        property int counter

        repeat: true

        function resetAndRestart() {
            counter = 0
            interval = 800
            restart()
        }

        function positionAfter(position, mouseX, mouseY) {
            var rect = _editor.positionToRectangle(position)
            return mouseY > rect.y + Math.max(rect.height, mouseArea.touchAreaSize)
                    || (mouseY >= rect.y
                        && mouseX > rect.x + rect.width + mouseArea.touchAreaSize / 2)
        }

        onTriggered: {
            var origSelectionStart = _editor.selectionStart
            var origSelectionEnd = _editor.selectionEnd
            var translatedPos = mouseArea.mapToItem(_editor, mouseArea.initialMouseX, mouseArea.initialMouseY)
            if (counter == 0) {
                if (_suppressPressAndHoldOnText) {
                    Qt.inputMethod.commit()
                    if (_editor.length == 0 || positionAfter(_editor.length - 1, translatedPos.x, translatedPos.y)) {
                        // This selection is outside the text itself - deselect and pass through as press-and-hold
                        _editor.deselect()
                        mouseArea.reset()
                        textBase.pressAndHold({ 'x': mouseArea.initialMouseX, 'y': mouseArea.initialMouseY })
                        return
                    }
                }

                _editor.cursorPosition = mouseArea.positionAt(mouseArea.initialMouseX, mouseArea.initialMouseY)
                _editor.selectWord()
                if (origSelectionStart != _editor.selectionStart || origSelectionEnd != _editor.selectionEnd) {
                    if (mouseArea.selectionStartHandle !== null)
                        mouseArea.selectionStartHandle.showAnimation.restart()
                    if (mouseArea.selectionEndHandle !== null)
                        mouseArea.selectionEndHandle.showAnimation.restart()
                }
                interval = 600
                // single line editor to skip choosing visible area
                if (textBase._singleLine) {
                    counter++
                }
            } else if (counter == 1) {
                _editor.select(mouseArea.positionAt(0, translatedPos.y),
                               mouseArea.positionAt(_editor.width, translatedPos.y))
            } else {
                _editor.cursorPosition = _editor.text.length
                _editor.selectAll()
                stop()
            }
            if (origSelectionStart != _editor.selectionStart || origSelectionEnd != _editor.selectionEnd) {
                if (_feedbackEffect) {
                    _feedbackEffect.play()
                }
                if (_editor.selectedText !== "") {
                    _editor.copy()
                }
                mouseArea.textSelected = true
            }
            mouseArea.cursorHit = false
            counter++
        }
    }

    Timer {
        id: focusLossTimer

        interval: 1
        onTriggered: {
            // Note: textBase.focus.  Removing focus from the editor item breaks the focus
            // inheritence chain making it impossible for the editor to regain focus without
            // using forceActiveFocus()
            if (!textBase.activeFocus) {
            } else if (textBase.focusOutBehavior === FocusBehavior.ClearItemFocus) {
                textBase.focus = false
            } else if (textBase.focusOutBehavior === FocusBehavior.ClearPageFocus) {
                // Just remove the focus from the application window (that is a focus scope).
                // This allows an item to clear its active focus without breaking the focus
                // chain within a page.
                if (_appWindow !== undefined) {
                    _appWindow.focus = false
                } else {
                    textBase.focus = false // fallback
                }
            } else if (!_editor.activeFocus) {
                // Happens e.g. when keyboard is closed
                textBase.focus = false
            } else {
                _editor.deselect()
            }
            _editor.focus = true
        }
    }

    Icon {
        id: errorIcon

        parent: null
        color: Theme.errorColor
        highlightColor: Theme.errorColor
        source: textBase.errorHighlight ? "image://theme/icon-splus-error" : ""
    }

    FontMetrics {
        id: fontMetrics

        font: _editor.font
    }

    TextBaseExtensionContainer {
        id: leftItemContainer

        x: textBase.textLeftMargin - (leftItemContainer.active ? leftItemContainer.width + Theme.paddingMedium : 0)
        y: (fontMetrics.height + _totalVerticalMargins - height)/2
        parent: textBase
    }

    TextBaseExtensionContainer {
        id: rightItemContainer

        y: ((_editor.y - textTopPadding) + fontMetrics.height)/2 - height/2 + _totalTopMargins
        parent: textBase
        anchors {
            right: parent.right
            rightMargin: textBase.textRightMargin
        }

        item: errorHighlight ? errorIcon : null
    }

    StateGroup {
        states: State {
            when: (mouseArea.handleGrabbed || mouseArea.cursorGrabbed) && _appWindow !== undefined
            PropertyChanges {
                target: _appWindow ? _appWindow._contentScale : null
                xScale: mouseArea.scaleFactor
                yScale: mouseArea.scaleFactor
            }
            StateChangeScript {
                script: {
                    mouseArea.updateTouchOffsetAndScaleOrigin(true)
                }
            }
        }
    }

    Connections {
        ignoreUnknownSignals: true
        target: _editor
        onActiveFocusChanged: {
            if (_editor.activeFocus) {
                if (textBase.softwareInputPanelEnabled) {
                    Qt.inputMethod.show()
                }
            } else {
                // When keyboard is explicitly closed (by swipe down) only _editor.focus is cleared.
                // Need to use focusLossTimer for clearing the focus of the parent.
                // (See the comments in focusLossTimer.)
                focusLossTimer.start()
            }
        }
    }

    Component {
        id: handleComponent

        Rectangle {
            id: handleId

            property bool start
            property var cursorRect: {
                _editor.width // creates a binding. we want to refresh the cursor rect e.g. on orientation change
                _editor.positionToRectangle(start ? _editor.selectionStart : _editor.selectionEnd)
            }
            property alias showAnimation: showAnimationId
            property int xAnimationLength: Theme.itemSizeExtraLarge

            color: textBase.cursorColor
            parent: _editor
            x: Math.round(cursorRect.x + cursorRect.width / 2 - width / 2)
            y: Math.round(cursorRect.y + cursorRect.height / 2 - height / 2)
            width: Math.round(Theme.iconSizeSmall / 4) * 2 // ensure even number
            height: width
            radius: width / 2
            smooth: true
            visible: mouseArea.hasSelection && textBase.activeFocus

            states: State {
                when: mouseArea.handleGrabbed
                name: "grabbed"
                PropertyChanges {
                    target: handleId
                    width: 2
                    height: cursorRect.height
                    radius: 0
                }
            }

            transitions: Transition {
                to: "grabbed"
                reversible: true
                SequentialAnimation {
                    NumberAnimation { property: "width"; duration: 100 }
                    PropertyAction { property: "radius" }
                    NumberAnimation { property: "height"; duration: 100 }
                }
            }

            ParallelAnimation {
                id: showAnimationId

                FadeAnimation {
                    target: handleId
                    from: 0
                    to: 1
                }
                NumberAnimation {
                    target: handleId
                    property: "x"
                    from: start ? handleId.x - xAnimationLength : handleId.x + xAnimationLength
                    to: handleId.x
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }
}
