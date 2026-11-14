// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sample app in the style of Harbour apps (SDK template layout), used by
// tst_compat_app.qml. Written for Keel; no third-party code.
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "firstPage"
    allowedOrientations: Orientation.All

    property alias listView: listView
    property alias pullDownMenu: pullDown

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: app.notes

        header: PageHeader {
            title: qsTr("Notes")
            description: listView.count + " " + qsTr("items")
        }

        PullDownMenu {
            id: pullDown
            MenuItem {
                objectName: "aboutItem"
                text: qsTr("About")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                objectName: "addItem"
                text: qsTr("Add note")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("AddDialog.qml"))
                    dialog.accepted.connect(function() {
                        app.addNote(dialog.noteTitle, dialog.priority, dialog.pinned)
                    })
                }
            }
        }

        delegate: ListItem {
            id: delegate
            objectName: "note_" + index
            contentHeight: Theme.itemSizeMedium
            menu: ContextMenu {
                MenuItem {
                    objectName: "removeItem"
                    text: qsTr("Remove")
                    onClicked: delegate.remorseDelete(function() { app.notes.remove(index) }, 100)
                }
            }
            onClicked: pageStack.push(Qt.resolvedUrl("DetailPage.qml"), { note: model.title })

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                anchors.verticalCenter: parent.verticalCenter
                text: model.title
                color: delegate.highlighted ? Theme.highlightColor : Theme.primaryColor
                truncationMode: TruncationMode.Fade
            }
            Label {
                anchors { right: parent.right; rightMargin: Theme.horizontalPageMargin; bottom: parent.bottom }
                text: model.priority
                font.pixelSize: Theme.fontSizeExtraSmall
                color: delegate.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No notes")
            hintText: qsTr("Pull down to add one")
        }
        VerticalScrollDecorator { }
    }
}
