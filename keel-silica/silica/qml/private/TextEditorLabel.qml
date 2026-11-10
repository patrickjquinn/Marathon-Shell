// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// TextEditorLabel: the label under a text field (`label` of TextField and
// TextArea). Silica's own file is not open (no BSD header in
// sailfishsilica-qt5 1.2.156); Keel's clean-room stand-in, created by
// Silica's BSD private/TextBase.qml with `editor` set to the text field.
// Hidden while the field is empty and hideLabelOnEmptyField is set (the
// placeholder shows the label then).
import QtQuick
import Sailfish.Silica 1.0

Label {
    property Item editor

    text: editor ? editor.label : ""
    color: editor && editor.errorHighlight ? palette.errorColor
           : (editor && editor.highlighted ? palette.secondaryHighlightColor : palette.secondaryColor)
    font.pixelSize: Theme.fontSizeSmall
    truncationMode: TruncationMode.Fade
    opacity: editor && editor._isEmpty && editor.hideLabelOnEmptyField ? 0.0 : 1.0
    Behavior on opacity { FadeAnimation {} }
}
