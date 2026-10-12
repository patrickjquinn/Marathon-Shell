pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../CalendarLogic.js" as Logic
import "../components"

Page {
    id: page

    property var app
    property string query: ""
    readonly property var results: Logic.search(app.events, query)

    SilicaListView {
        id: view

        objectName: "searchView"
        anchors.fill: parent
        model: page.results
        header: Column {
            width: view.width

            PageHeader {
                title: qsTr("Search")
            }
            SearchField {
                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search events")
                focus: true
                onTextChanged: page.query = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: page.results.length === 0
            text: page.query.trim() === "" ? qsTr("Search your events") : qsTr("No matching events")
            hintText: page.query.trim() === "" ? qsTr("Type part of an event's title") : qsTr("Try a different word")
        }

        delegate: EventItem {
            app: page.app
            showDate: true
        }

        VerticalScrollDecorator {}
    }
}
