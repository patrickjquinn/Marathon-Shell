pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../CalendarLogic.js" as Logic
import "../components"

Page {
    id: page

    property var app
    readonly property var shown: Logic.sorted(app.events)

    SilicaListView {
        id: view

        objectName: "agendaView"
        anchors.fill: parent
        model: page.shown
        header: PageHeader {
            title: qsTr("All events")
        }

        PullDownMenu {
            MenuItem {
                objectName: "searchItem"
                text: qsTr("Search")
                onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"), { app: page.app })
            }
            MenuItem {
                objectName: "newEventItem"
                text: qsTr("New event")
                onClicked: page.app.newEvent(new Date())
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: page.shown.length === 0
            text: qsTr("No events")
            hintText: qsTr("Pull down to add one")
        }

        delegate: Column {
            id: entry

            required property var modelData
            required property int index

            width: view.width

            SectionHeader {
                visible: entry.index === 0 || page.shown[entry.index - 1].date !== entry.modelData.date
                text: page.app.dateText(entry.modelData)
            }
            EventItem {
                app: page.app
                modelData: entry.modelData
            }
        }

        VerticalScrollDecorator {}
    }
}
