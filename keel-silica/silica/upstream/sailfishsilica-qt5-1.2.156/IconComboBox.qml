/****************************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
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
import "private"

ComboBox {
    id: iconComboBox

    property alias icon: icon

    value: currentItem
           ? currentItem.description || currentItem.text
           : ""
    labelMargin: leftMargin + icon.width + Theme.paddingMedium

    // Prevent icon position from jumping when value selection results in visual change between
    // one- and two-line layout.
    minimumContentHeight: Theme.itemSizeMedium + Theme.paddingSmall

    HighlightImage {
        id: icon

        anchors {
            left: parent.left
            leftMargin: iconComboBox.leftMargin
            top: iconComboBox._descriptionLabel
                 ? parent.top
                 : undefined
            topMargin: Theme.paddingLarge - Theme.paddingSmall
            verticalCenter: iconComboBox._descriptionLabel
                            ? undefined
                            : parent.verticalCenter
        }
        sourceSize.width: Theme.iconSizeMedium
        sourceSize.height: Theme.iconSizeMedium

        source: iconComboBox.currentItem && iconComboBox.currentItem.icon
                ? iconComboBox.currentItem.icon.source
                : ""
    }
}
