pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MapsLogic.js" as Logic

Page {
    id: root

    property var app

    readonly property string mode: app.routingMode
    readonly property color panelColor: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay)

    function openRoute() {
        pageStack.push(Qt.resolvedUrl("RoutePage.qml"), {
            app: root.app
        });
    }

    function openPlace() {
        pageStack.push(Qt.resolvedUrl("PlacePage.qml"), {
            app: root.app
        });
    }

    objectName: "mapPage"

    Loader {
        objectName: "mapLoader"
        anchors.fill: parent
        source: root.app.mapSource
        onLoaded: root.app.attachMap(item)
    }

    BusyLabel {
        running: !root.app.mapReady && root.app.mapError === ""
        text: qsTr("Loading map")
    }

    Rectangle {
        objectName: "mapError"
        anchors.fill: parent
        visible: root.app.mapError !== "" && !root.app.mapUnavailable
        color: Theme.overlayBackgroundColor

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Theme.paddingLarge

            InfoLabel {
                text: qsTr("Can't show the map")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeMedium
                text: qsTr("The map couldn't start its graphics. Try again, or close and reopen Maps.")
            }
            Button {
                objectName: "retryMap"
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Try again")
                onClicked: root.app.retryMap()
            }
        }
    }

    // Without WebGL the map can never draw, but search and spoken directions
    // still work.
    Column {
        objectName: "mapUnavailable"
        anchors.bottom: bottomPanel.visible ? bottomPanel.top : parent.bottom
        anchors.bottomMargin: Theme.paddingLarge
        width: parent.width
        spacing: Theme.paddingLarge
        visible: root.app.mapUnavailable

        InfoLabel {
            text: qsTr("This phone can't draw the map yet")
        }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeMedium
            text: qsTr("You can still search for places and get spoken directions.")
        }
    }

    // Next maneuver, readable at a glance while driving.
    Rectangle {
        objectName: "navBanner"
        x: Theme.horizontalPageMargin
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: banner.height
        radius: Theme.paddingSmall
        visible: root.mode === "active"
        color: root.panelColor

        BackgroundItem {
            id: banner

            width: parent.width
            height: Math.max(maneuverIcon.height, bannerText.height) + 2 * Theme.paddingLarge
            Accessible.name: (root.app.arrived ? "" : distanceLabel.text + ", ") + instructionLabel.text
            Accessible.description: qsTr("Shows all directions")
            onClicked: root.openRoute()

            Icon {
                id: maneuverIcon

                x: Theme.paddingLarge
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeLarge
                height: width
                source: root.app.nextManeuver ? Logic.maneuverIcon(root.app.nextManeuver.type) : ""
                color: Theme.highlightColor
            }
            Column {
                id: bannerText

                anchors {
                    left: maneuverIcon.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.paddingLarge
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    id: distanceLabel

                    objectName: "navDistance"
                    visible: !root.app.arrived
                    text: Logic.formatDistance(root.app.distanceToNext)
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeHuge
                }
                Label {
                    id: instructionLabel

                    objectName: "navInstruction"
                    width: parent.width
                    text: root.app.nextManeuver ? root.app.nextManeuver.instruction : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeLarge
                }
            }
        }
    }

    Rectangle {
        objectName: "startHint"
        x: Theme.horizontalPageMargin
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: hintLabel.height + 2 * Theme.paddingLarge
        radius: Theme.paddingSmall
        visible: root.app.awaitingStartPoint
        color: root.panelColor

        Label {
            id: hintLabel

            x: Theme.paddingLarge
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - hintCancel.width - Theme.paddingMedium
            wrapMode: Text.Wrap
            color: Theme.highlightColor
            text: qsTr("Your location isn't known yet. Tap the map where the route should start.")
        }
        IconButton {
            id: hintCancel

            anchors.right: parent.right
            anchors.rightMargin: Theme.paddingMedium
            anchors.verticalCenter: parent.verticalCenter
            icon.source: "image://theme/icon-m-cancel"
            Accessible.name: qsTr("Cancel")
            onClicked: root.app.awaitingStartPoint = false
        }
    }

    // Search sits on the map, as in the design; the chosen place shows in it.
    Rectangle {
        id: searchBar

        x: Theme.horizontalPageMargin
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: Theme.itemSizeMedium
        radius: Theme.paddingSmall
        color: root.panelColor
        visible: root.mode === "idle" && !root.app.awaitingStartPoint

        BackgroundItem {
            objectName: "searchButton"
            anchors.fill: parent
            Accessible.name: root.app.selectedPlace ? qsTr("Search places. Showing %1").arg(root.app.selectedPlace.name) : qsTr("Search places")
            onClicked: root.app.openSearch()

            Icon {
                id: searchIcon

                x: Theme.paddingLarge
                anchors.verticalCenter: parent.verticalCenter
                source: "image://theme/icon-m-search"
                color: Theme.secondaryColor
            }
            Column {
                anchors {
                    left: searchIcon.right
                    leftMargin: Theme.paddingMedium
                    right: parent.right
                    rightMargin: Theme.paddingLarge
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: root.app.selectedPlace ? root.app.selectedPlace.name : qsTr("Search places")
                    color: root.app.selectedPlace ? Theme.primaryColor : Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    visible: root.app.selectedPlace !== null
                    text: root.app.selectedPlace ? root.app.selectedPlace.address : ""
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
        }
    }

    Rectangle {
        anchors {
            right: searchBar.right
            top: searchBar.bottom
            topMargin: Theme.paddingLarge
        }
        width: Theme.itemSizeSmall
        height: width
        radius: Theme.paddingSmall
        color: root.panelColor
        visible: root.mode !== "active" && !root.app.awaitingStartPoint

        IconButton {
            objectName: "locateButton"
            anchors.fill: parent
            icon.source: "image://theme/icon-m-gps"
            icon.color: Theme.highlightColor
            Accessible.name: qsTr("Show my location")
            onClicked: root.app.locateMe()
        }
    }

    Rectangle {
        id: bottomPanel

        objectName: "bottomPanel"
        x: Theme.horizontalPageMargin
        anchors {
            bottom: parent.bottom
            bottomMargin: Theme.paddingLarge
        }
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: panel.height
        radius: Theme.paddingSmall
        color: root.panelColor
        visible: root.mode !== "idle" || root.app.selectedPlace !== null || root.app.resumable !== null

        Column {
            id: panel

            width: parent.width

            // A route cut short when the app was closed.
            Item {
                width: parent.width
                height: Theme.itemSizeLarge
                visible: root.mode === "idle" && root.app.selectedPlace === null && root.app.resumable !== null

                BackgroundItem {
                    objectName: "resumeItem"
                    width: parent.width - dismissResume.width
                    height: parent.height
                    Accessible.name: root.app.resumable ? qsTr("Resume route to %1").arg(root.app.resumable.place.name) : ""
                    onClicked: root.app.resumeDirections()

                    Icon {
                        id: resumeIcon

                        x: Theme.paddingLarge
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-navigate"
                        color: Theme.highlightColor
                    }
                    Column {
                        anchors {
                            left: resumeIcon.right
                            leftMargin: Theme.paddingMedium
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }

                        Label {
                            id: resumeLabel

                            width: parent.width
                            text: qsTr("Resume route")
                            color: Theme.highlightColor
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            text: root.app.resumable ? root.app.resumable.place.name : ""
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeSmall
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
                IconButton {
                    id: dismissResume

                    objectName: "dismissResume"
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-clear"
                    Accessible.name: qsTr("Dismiss")
                    onClicked: root.app.dismissResume()
                }
            }

            // The chosen place, with what can be done with it.
            Column {
                width: parent.width
                visible: root.mode === "idle" && root.app.selectedPlace !== null

                BackgroundItem {
                    id: placeCard

                    objectName: "placeCard"
                    width: parent.width
                    height: placeText.height + 2 * Theme.paddingLarge
                    Accessible.name: placeName.text
                    Accessible.description: qsTr("Shows details")
                    onClicked: root.openPlace()

                    Column {
                        id: placeText

                        x: Theme.paddingLarge
                        y: Theme.paddingLarge
                        width: parent.width - 2 * Theme.paddingLarge

                        Label {
                            id: placeName

                            width: parent.width
                            text: root.app.selectedPlace ? root.app.selectedPlace.name : ""
                            color: placeCard.highlighted ? Theme.highlightColor : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeLarge
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            text: root.app.selectedPlace ? Logic.placeLine(root.app.selectedPlace) : ""
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
                Separator {
                    width: parent.width
                    color: Theme.primaryColor
                    horizontalAlignment: Qt.AlignHCenter
                }
                Row {
                    width: parent.width

                    Repeater {
                        model: [
                            {
                                name: "directionsAction",
                                icon: "navigate",
                                text: qsTr("Directions"),
                                primary: true
                            },
                            {
                                name: "detailsAction",
                                icon: "about",
                                text: qsTr("Details"),
                                primary: false
                            },
                            {
                                name: "clearAction",
                                icon: "clear",
                                text: qsTr("Clear"),
                                primary: false
                            }
                        ]

                        BackgroundItem {
                            id: action

                            required property var modelData

                            objectName: modelData.name
                            width: parent.width / 3
                            height: Theme.itemSizeLarge
                            enabled: !(modelData.primary && root.app.router.routing)
                            Accessible.name: modelData.text
                            onClicked: {
                                if (modelData.name === "directionsAction")
                                    root.app.requestDirections();
                                else if (modelData.name === "detailsAction")
                                    root.openPlace();
                                else
                                    root.app.clearPlace();
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.paddingSmall

                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    source: "image://theme/icon-m-" + action.modelData.icon
                                    color: action.modelData.primary || action.highlighted ? Theme.highlightColor : Theme.primaryColor
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: action.modelData.primary && root.app.router.routing ? qsTr("Finding a route") : action.modelData.text
                                    color: action.modelData.primary || action.highlighted ? Theme.highlightColor : Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                }
                            }
                        }
                    }
                }
            }

            // Route found, not started: the summary opens the directions.
            Column {
                width: parent.width
                bottomPadding: Theme.paddingLarge
                visible: root.mode === "preview"

                BackgroundItem {
                    objectName: "previewDirections"
                    width: parent.width
                    height: summary.height + 2 * Theme.paddingLarge
                    Accessible.name: qsTr("Directions")
                    onClicked: root.openRoute()

                    Column {
                        id: summary

                        x: Theme.paddingLarge
                        y: Theme.paddingLarge
                        width: parent.width - x - closeRoute.width - Theme.paddingSmall

                        Label {
                            objectName: "previewDuration"
                            text: root.app.currentRoute ? Logic.formatDuration(root.app.currentRoute.duration) : ""
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeExtraLarge
                        }
                        Label {
                            width: parent.width
                            text: {
                                if (!root.app.currentRoute)
                                    return "";
                                const via = Logic.via(root.app.maneuvers);
                                const km = Logic.formatDistance(root.app.currentRoute.distance);
                                return via ? qsTr("%1 via %2").arg(km).arg(via) : km;
                            }
                            color: Theme.secondaryColor
                            truncationMode: TruncationMode.Fade
                        }
                    }
                    IconButton {
                        id: closeRoute

                        anchors.right: parent.right
                        anchors.rightMargin: Theme.paddingSmall
                        anchors.verticalCenter: parent.verticalCenter
                        icon.source: "image://theme/icon-m-clear"
                        Accessible.name: qsTr("Clear route")
                        onClicked: root.app.endNavigation()
                    }
                }
                Button {
                    objectName: "previewStart"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Start navigation")
                    onClicked: root.app.startNavigation()
                }
            }

            // Navigating.
            Item {
                width: parent.width
                height: Theme.itemSizeLarge
                visible: root.mode === "active" && !root.app.arrived

                Column {
                    x: Theme.paddingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - endNav.width - mute.width - Theme.paddingSmall

                    Label {
                        objectName: "navRemaining"
                        width: parent.width
                        text: Logic.formatDuration(root.app.remainingRoute.time)
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeLarge
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: Logic.formatDistance(root.app.remainingRoute.distance) + (root.app.selectedPlace ? " · " + root.app.selectedPlace.name : "")
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                    }
                }
                IconButton {
                    id: mute

                    objectName: "muteButton"
                    anchors.right: endNav.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.app.voice !== null && root.app.voice.available
                    icon.source: root.app.voice && root.app.voice.muted ? "image://theme/icon-m-mute" : "image://theme/icon-m-volume"
                    Accessible.name: root.app.voice && root.app.voice.muted ? qsTr("Turn voice on") : qsTr("Mute voice")
                    onClicked: root.app.voice.muted = !root.app.voice.muted
                }
                IconButton {
                    id: endNav

                    objectName: "endButton"
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-cancel"
                    Accessible.name: qsTr("End navigation")
                    onClicked: root.app.endNavigation()
                }
            }

            // Arrived: a designed end, not a route left running.
            Column {
                width: parent.width
                topPadding: Theme.paddingLarge
                bottomPadding: Theme.paddingLarge
                spacing: Theme.paddingMedium
                visible: root.mode === "active" && root.app.arrived

                Label {
                    objectName: "arrivedLabel"
                    x: Theme.paddingLarge
                    width: parent.width - 2 * Theme.paddingLarge
                    text: root.app.selectedPlace ? qsTr("You've arrived at %1").arg(root.app.selectedPlace.name) : qsTr("You've arrived")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                    wrapMode: Text.Wrap
                }
                Button {
                    objectName: "doneButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Done")
                    onClicked: root.app.endNavigation()
                }
            }
        }
    }
}
