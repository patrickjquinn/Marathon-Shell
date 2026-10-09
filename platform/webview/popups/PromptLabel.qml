// SPDX-FileCopyrightText: 2013-2016 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (C) 2013-2016 Jolla Ltd.
** Contact: Raine Makelainen <raine.makelainen@jollamobile.com>
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: root

    property bool largeFont: true
    property alias text: label.text

    height: label.height + (largeFont ? Theme.itemSizeSmall : Theme.paddingLarge)
    width: parent.width

    Label {
        id: label

        x: Theme.horizontalPageMargin
        y: root.largeFont ? Theme.itemSizeSmall : Theme.paddingLarge
        width: parent.width - 2 * x

        font.pixelSize: largeFont ? Theme.fontSizeExtraLarge : Theme.fontSizeMedium
        color: Theme.highlightColor

        onContentWidthChanged: function() { // Modified by Shipwright for Qt 6: no injected parameter
            // We want to get contentWidth text width only once. When wrapping
            // goes enabled we get contentWidth that is less than width.
            // Greater than ~ three liner will be rendered with smaller font.
            if (contentWidth > width * 3 && wrapMode == Text.NoWrap) {
                root.largeFont = false
                wrapMode = Text.Wrap
            } else if (contentWidth > width && wrapMode == Text.NoWrap) {
                wrapMode = Text.Wrap
            }
        }
    }
}
