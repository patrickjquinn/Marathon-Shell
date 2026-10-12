pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: root

    property var app
    readonly property var place: app.selectedPlace || ({ name: "", address: "", type: "", lat: 0, lon: 0 })
    readonly property bool routing: app.router.routing

    objectName: "placePage"

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Search again")
                onClicked: pageStack.replace(Qt.resolvedUrl("SearchPage.qml"), { app: root.app })
            }
            MenuItem {
                objectName: "showOnMap"
                text: qsTr("Show on map")
                onClicked: {
                    root.app.selectPlace(root.app.selectedPlace);
                    pageStack.pop();
                }
            }
            MenuItem {
                text: qsTr("Navigate")
                enabled: !root.routing
                onClicked: root.app.requestDirections()
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: root.place.name
                description: root.place.type
            }
            DetailItem {
                objectName: "addressItem"
                label: qsTr("Address")
                value: root.place.address
            }
            DetailItem {
                label: qsTr("Coordinates")
                value: root.place.lat.toFixed(5) + ", " + root.place.lon.toFixed(5)
            }
            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
            Button {
                objectName: "navigateButton"
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.routing ? qsTr("Finding a route") : qsTr("Navigate")
                enabled: !root.routing
                onClicked: root.app.requestDirections()
            }
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: root.routing
                visible: running
            }
        }

        VerticalScrollDecorator {}
    }
}
