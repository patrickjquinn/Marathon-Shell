pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var app

    SilicaListView {
        id: view

        objectName: "itemsView"
        anchors.fill: parent
        model: page.app.items
        header: PageHeader {
            title: qsTr("Template")
        }

        PullDownMenu {
            MenuItem {
                objectName: "addItem"
                text: qsTr("Add item")
                onClicked: page.app.addItem()
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: view.count === 0
            text: qsTr("No items")
            hintText: qsTr("Pull down to add one")
        }

        delegate: ListItem {
            id: item

            required property var modelData

            Accessible.name: modelData.text
            menu: ContextMenu {
                MenuItem {
                    objectName: "deleteItem"
                    text: qsTr("Delete")
                    onClicked: {
                        const id = item.modelData.id;
                        item.remorseDelete(() => page.app.removeItem(id));
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: item.modelData.text
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
