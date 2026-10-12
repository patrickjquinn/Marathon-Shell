pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var app

    SilicaListView {
        id: view

        objectName: "draftView"
        anchors.fill: parent
        model: page.app.drafts

        header: PageHeader {
            title: qsTr("Drafts")
        }

        ViewPlaceholder {
            enabled: view.count === 0
            text: qsTr("No drafts")
        }

        delegate: ListItem {
            id: item

            required property var modelData

            objectName: "draft-" + modelData.key
            contentHeight: Theme.itemSizeMedium
            Accessible.name: (modelData.subject || qsTr("(No subject)")) + ", " + (modelData.to || qsTr("No recipient"))
            onClicked: page.app.compose({ draftKey: modelData.key })
            menu: ContextMenu {
                MenuItem {
                    objectName: "deleteItem"
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(() => page.app.deleteDraft(item.modelData.key))
                }
            }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    text: item.modelData.subject || qsTr("(No subject)")
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: (item.modelData.to || qsTr("No recipient")) + (item.modelData.savedAt > 0 ? " · " + Format.formatDate(new Date(item.modelData.savedAt), Formatter.TimepointRelative) : "")
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
