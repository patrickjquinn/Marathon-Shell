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

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import "private"

TextBase {
    id: textArea

    property alias text: preeditText.text
    property alias textWidth: textEdit.width
    property alias readOnly: textEdit.readOnly
    property alias inputMethodHints: textEdit.inputMethodHints
    property alias inputMethodComposing: textEdit.inputMethodComposing
    property alias cursorPosition: textEdit.cursorPosition
    property alias wrapMode: textEdit.wrapMode
    property alias verticalAlignment: textEdit.verticalAlignment
    property alias selectedText: textEdit.selectedText
    property alias selectionStart: textEdit.selectionStart
    property alias selectionEnd: textEdit.selectionEnd
    property alias length: textEdit.length

    onHorizontalAlignmentChanged: {
        if (explicitHorizontalAlignment) {
            textEdit.horizontalAlignment = horizontalAlignment
        }
    }
    onExplicitHorizontalAlignmentChanged: {
        if (explicitHorizontalAlignment) {
            textEdit.horizontalAlignment = horizontalAlignment
        } else {
            textEdit.horizontalAlignment = undefined
        }
    }

    _editor: textEdit

    onReadOnlyChanged: _updateBackground()

    _flickableDirection: Flickable.VerticalFlick

    TextEdit {
        id: textEdit
        objectName: "textEditor"

        onHorizontalAlignmentChanged: textArea.setImplicitHorizontalAlignment(horizontalAlignment)

        x: -parent.contentX + textArea.textLeftPadding
        y: -parent.contentY + textArea.textTopPadding
        width: textArea.width - Theme.paddingSmall - textArea._totalLeftMargins
               - textArea._totalRightMargins - textArea._rightItemWidth
        focus: true
        activeFocusOnPress: false
        activeFocusOnTab: !readOnly
        color: textArea.color
        selectionColor: Theme.rgba(textArea.palette.primaryColor, 0.3)
        selectedTextColor: textArea.palette.highlightColor
        font: textArea.font
        cursorDelegate: Cursor {
            color: textArea.cursorColor
            preedit: preeditText
        }
        wrapMode: TextEdit.Wrap

        // Note: need to disable if textFormat is ever allowed to be more than TextEdit.PlainText
        PreeditText {
            id: preeditText

            onTextChanged: textArea._fixupScrollPosition()
        }
    }
}
