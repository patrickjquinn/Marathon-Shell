import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic

Page {
    id: root

    property var app
    property string query: ""

    SilicaListView {
        id: list

        objectName: "addCityList"
        anchors.fill: parent
        model: Logic.filterCities(Logic.knownCities, root.query)

        header: Column {
            width: list.width

            PageHeader {
                title: qsTr("Add city")
            }
            SearchField {
                objectName: "citySearch"
                width: parent.width
                placeholderText: qsTr("Search cities")
                onTextChanged: root.query = text
            }
        }

        ViewPlaceholder {
            enabled: list.count === 0
            text: qsTr("No cities found")
            hintText: qsTr("Try the country or a nearby city")
        }

        delegate: ListItem {
            id: item

            required property var modelData

            objectName: "addCityItem"
            contentHeight: Theme.itemSizeMedium
            Accessible.name: qsTr("Add %1").arg(modelData.name)
            onClicked: {
                root.app.addCity(modelData);
                pageStack.pop();
            }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    text: Theme.highlightText(item.modelData.name, root.query.trim(), Theme.highlightColor)
                    textFormat: Text.StyledText
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.modelData.country || ""
                    visible: text !== ""
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
