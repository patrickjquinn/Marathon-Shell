pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MapsLogic.js" as Logic

Page {
    id: root

    property var app
    readonly property bool active: app.routingMode === "active"
    readonly property var route: app.currentRoute

    objectName: "routePage"
    // Ending the route leaves nothing to show.
    onRouteChanged: if (!route && status === PageStatus.Active) pageStack.pop()

    SilicaListView {
        id: view

        objectName: "maneuverView"
        anchors.fill: parent
        model: root.app.maneuvers

        header: Column {
            width: view.width
            // Long values wrap after the first layout; keep the header in view.
            onHeightChanged: if (!view.moving && view.contentY < view.originY + height) view.positionViewAtBeginning()

            PageHeader {
                title: root.active ? qsTr("Directions") : qsTr("Route")
                description: root.app.router.routing ? qsTr("Finding a route…") : root.app.selectedPlace ? root.app.selectedPlace.name : ""

                BusyIndicator {
                    parent: parent.extraContent
                    anchors.verticalCenter: parent.verticalCenter
                    size: BusyIndicatorSize.Small
                    running: root.app.router.routing
                }
            }
            DetailItem {
                objectName: "durationItem"
                label: root.active ? qsTr("Time left") : qsTr("Time")
                value: root.route ? Logic.formatDuration(root.active ? root.app.remainingRoute.time : root.route.duration) : ""
            }
            DetailItem {
                label: root.active ? qsTr("Distance left") : qsTr("Distance")
                value: root.route ? Logic.formatDistance(root.active ? root.app.remainingRoute.distance : root.route.distance) : ""
            }
            DetailItem {
                visible: value !== ""
                label: qsTr("Via")
                value: Logic.via(root.app.maneuvers)
            }
            ComboBox {
                id: modeBox

                readonly property var modes: ["auto", "pedestrian", "bicycle"]

                objectName: "modes"
                visible: !root.active
                enabled: !root.app.router.routing
                label: qsTr("Travel by")
                // The combo writes its own index on load, which would drop a
                // plain binding.
                Binding on currentIndex {
                    value: modeBox.modes.indexOf(root.app.currentMode)
                }
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Drive")
                        onClicked: root.app.setMode("auto")
                    }
                    MenuItem {
                        objectName: "walkMode"
                        text: qsTr("Walk")
                        onClicked: root.app.setMode("pedestrian")
                    }
                    MenuItem {
                        text: qsTr("Cycle")
                        onClicked: root.app.setMode("bicycle")
                    }
                }
            }
            Item {
                width: parent.width
                height: Theme.paddingLarge
                visible: !root.active
            }
            Button {
                objectName: "startButton"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.active
                enabled: !root.app.router.routing
                text: qsTr("Start navigation")
                onClicked: root.app.startNavigation()
            }
            SectionHeader {
                text: qsTr("Directions")
            }
        }

        PullDownMenu {
            MenuItem {
                objectName: "endItem"
                text: root.active ? qsTr("End navigation") : qsTr("Clear route")
                onClicked: root.app.endNavigation()
            }
            MenuItem {
                text: qsTr("Show on map")
                onClicked: pageStack.pop(pageStack.find(p => p.objectName === "mapPage"))
            }
        }

        delegate: ListItem {
            id: item

            required property var modelData
            required property int index
            readonly property bool current: root.active && index === root.app.currentManeuverIndex + 1
            readonly property bool done: root.active && index <= root.app.currentManeuverIndex

            contentHeight: Math.max(Theme.itemSizeMedium, text.height + 2 * Theme.paddingMedium)
            opacity: root.app.router.routing ? Theme.opacityLow : done ? Theme.opacityHigh : 1
            Accessible.name: modelData.instruction + (modelData.length > 0 ? ", " + Logic.formatDistance(modelData.length * 1000) : "")

            Icon {
                id: icon

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: Logic.maneuverIcon(item.modelData.type)
                color: item.current || item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Column {
                id: text

                anchors {
                    left: icon.right
                    leftMargin: Theme.paddingMedium
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.modelData.instruction
                    wrapMode: Text.Wrap
                    color: item.current || item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    visible: item.modelData.length > 0
                    text: Logic.formatDistance(item.modelData.length * 1000)
                    color: item.current || item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
