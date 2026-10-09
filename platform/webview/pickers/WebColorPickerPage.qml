// SPDX-FileCopyrightText: 2026 Jolla Mobile Ltd
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

ColorPickerPage {
    id: colorPickerPage

    property int winId
    property QtObject contentItem
    property string initialColor: "#000000"
    property var defaultColors: []
    property bool _completed

    color: _cssColor(initialColor) || "#000000"

    function _cssColor(value) {
        var color = String(value).toLowerCase()
        if (color.length === 9 && color.charAt(0) === "#") {
            color = "#" + color.substring(3)
        }
        if (color.length !== 7 || color.charAt(0) !== "#") {
            return ""
        }

        for (var i = 1; i < color.length; ++i) {
            if ("0123456789abcdef".indexOf(color.charAt(i)) < 0) {
                return ""
            }
        }
        return color
    }

    function _sendResponse(accepted, selectedColor) {
        if (contentItem) {
            contentItem.sendAsyncMessage("embedui:colorpickerresponse",
                                         {
                                             "winId": winId,
                                             "accepted": accepted,
                                             "color": accepted ? selectedColor : ""
                                         })
        }
    }

    Component.onCompleted: {
        if (defaultColors && defaultColors.length > 0) {
            colors = defaultColors
        }
    }

    Component.onDestruction: {
        if (!_completed) {
            _completed = true
            _sendResponse(false, "")
        }
    }

    onColorClicked: {
        var selectedColor = _cssColor(color)
        _completed = true
        _sendResponse(selectedColor.length > 0, selectedColor)
        pageStack.pop()
    }

    on_NavigationChanged: {
        if (_navigation == PageNavigation.Back && !_completed) {
            _completed = true
            _sendResponse(false, "")
        }
    }
}
