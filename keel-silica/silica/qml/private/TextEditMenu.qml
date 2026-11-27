// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The bar a long press on a text field opens, over the selection or the
// cursor: select all, cut, copy and paste, as the field allows. A field whose
// text is secret (a password) offers paste only. Keel's own: Silica copies a
// selection at once and leaves pasting to its keyboard.
import QtQuick
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0

Rectangle {
    id: menu

    property TextBase field
    readonly property Item editor: field ? field._editor : null
    readonly property bool hasSelection: editor !== null && editor.selectedText !== ""
    readonly property bool canCopy: hasSelection && !field._copyProtected
    readonly property bool canCut: canCopy && !editor.readOnly
    readonly property bool canPaste: editor !== null && !editor.readOnly && Clipboard.hasText
    readonly property bool canSelectAll: editor !== null && !field._copyProtected
                                         && editor.selectedText.length < editor.length
    readonly property bool hasActions: canSelectAll || canCut || canCopy || canPaste
    readonly property real _margin: Theme.paddingMedium
    property real _centre
    property real _top
    property real _bottom

    // Over the selection, or under it with no room above.
    function open(): void {
        const start = editor.positionToRectangle(hasSelection ? editor.selectionStart : editor.cursorPosition)
        const end = editor.positionToRectangle(hasSelection ? editor.selectionEnd : editor.cursorPosition)
        const centreX = start.y === end.y ? (start.x + end.x) / 2 : editor.width / 2
        _centre = editor.mapToItem(parent, centreX, 0).x
        _top = editor.mapToItem(parent, 0, start.y).y
        _bottom = editor.mapToItem(parent, 0, end.y + end.height).y
        visible = hasActions
    }

    function close(): void {
        visible = false
    }

    parent: field ? field.Window.contentItem : null
    // Above everything else in the window.
    z: 1000000
    visible: false
    x: Math.max(_margin, Math.min(parent ? parent.width - width - _margin : 0, _centre - width / 2))
    y: _top - height - Theme.paddingMedium >= _margin ? _top - height - Theme.paddingMedium
                                                      : _bottom + Theme.paddingLarge
    width: actions.width
    height: Theme.itemSizeExtraSmall
    radius: height / 2
    color: Theme.highlightDimmerColor
    onHasActionsChanged: if (!hasActions) close()

    component Action: MouseArea {
        id: action

        property alias text: label.text

        width: label.implicitWidth + 2 * Theme.paddingLarge
        height: parent.height

        Label {
            id: label

            anchors.centerIn: parent
            color: action.pressed ? Theme.highlightColor : Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    Row {
        id: actions

        height: parent.height

        Action {
            objectName: "selectAll"
            visible: menu.canSelectAll
            text: qsTr("Select all")
            onClicked: {
                menu.editor.selectAll()
                menu.open()
            }
        }
        Action {
            objectName: "cut"
            visible: menu.canCut
            text: qsTr("Cut")
            onClicked: {
                menu.editor.cut()
                menu.close()
            }
        }
        Action {
            objectName: "copy"
            visible: menu.canCopy
            text: qsTr("Copy")
            onClicked: {
                menu.editor.copy()
                menu.editor.deselect()
                menu.close()
            }
        }
        Action {
            objectName: "paste"
            visible: menu.canPaste
            text: qsTr("Paste")
            onClicked: {
                menu.editor.paste()
                menu.close()
            }
        }
    }

    InverseMouseArea {
        anchors.fill: parent
        enabled: menu.visible
        onPressedOutside: menu.close()
    }

    Connections {
        target: menu.editor
        function onTextChanged(): void { menu.close() }
        function onActiveFocusChanged(): void {
            if (!menu.editor.activeFocus)
                menu.close()
        }
    }
}
