pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0

Page {
    id: page

    property string query: ""

    TimeZoneList {
        id: zones
    }

    SilicaListView {
        id: view

        objectName: "zoneList"
        anchors.fill: parent
        model: zones.search(page.query)
        header: Column {
            width: view.width

            PageHeader {
                title: qsTr("Time zone")
            }
            SearchField {
                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search cities or regions")
                onTextChanged: page.query = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        delegate: ListItem {
            id: item

            required property var modelData
            readonly property bool selected: modelData.id === (Settings.timeZone || "UTC")

            objectName: "zone-" + modelData.id
            contentHeight: Theme.itemSizeMedium
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.city + ", " + modelData.region + ", " + modelData.offset
            Accessible.checked: selected
            onClicked: {
                Settings.timeZone = modelData.id;
                pageStack.pop();
            }

            Column {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: offset.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.modelData.city
                    truncationMode: TruncationMode.Fade
                    color: item.selected || item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.modelData.region
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.selected || item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
            Label {
                id: offset

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: item.modelData.offset
                font.pixelSize: Theme.fontSizeSmall
                color: item.selected || item.highlighted ? Theme.highlightColor : Theme.secondaryColor
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: view.count === 0
            text: qsTr("No matching time zones")
            hintText: qsTr("Try a nearby city or a region such as Europe or America")
        }

        VerticalScrollDecorator {}
    }
}
