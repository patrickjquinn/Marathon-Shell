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
        pageStack.push(Qt.resolvedUrl("RoutePage.qml"), { app: root.app });
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
        anchors.bottom: bottomPanel.top
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
        width: parent.width
        height: banner.height
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

                x: Theme.horizontalPageMargin
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
                    rightMargin: Theme.horizontalPageMargin
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
        width: parent.width
        height: hintLabel.height + 2 * Theme.paddingLarge
        visible: root.app.awaitingStartPoint
        color: root.panelColor

        Label {
            id: hintLabel

            x: Theme.horizontalPageMargin
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

    Rectangle {
        id: bottomPanel

        objectName: "bottomPanel"
        anchors.bottom: parent.bottom
        width: parent.width
        height: panel.height + 2 * Theme.paddingMedium
        color: root.panelColor

        Column {
            id: panel

            y: Theme.paddingMedium
            width: parent.width

            // Search, or the chosen place.
            Item {
                width: parent.width
                height: Theme.itemSizeMedium
                visible: root.mode === "idle"

                BackgroundItem {
                    objectName: "searchButton"
                    width: parent.width - locate.width - (clearPlace.visible ? clearPlace.width : 0) - Theme.paddingSmall
                    height: parent.height
                    Accessible.name: root.app.selectedPlace ? root.app.selectedPlace.name : qsTr("Search places")
                    onClicked: root.app.selectedPlace ? pageStack.push(Qt.resolvedUrl("PlacePage.qml"), { app: root.app }) : root.app.openSearch()

                    Icon {
                        id: searchIcon

                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: root.app.selectedPlace ? "image://theme/icon-m-location" : "image://theme/icon-m-search"
                        color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Column {
                        anchors {
                            left: searchIcon.right
                            leftMargin: Theme.paddingMedium
                            right: parent.right
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
                IconButton {
                    id: clearPlace

                    anchors.right: locate.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.app.selectedPlace !== null
                    icon.source: "image://theme/icon-m-clear"
                    Accessible.name: qsTr("Clear place")
                    onClicked: root.app.clearPlace()
                }
                IconButton {
                    id: locate

                    objectName: "locateButton"
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-gps"
                    Accessible.name: qsTr("Show my location")
                    onClicked: root.app.locateMe()
                }
            }

            // Route found, not started.
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: root.mode === "preview"

                Item {
                    width: parent.width
                    height: summary.height

                    Column {
                        id: summary

                        x: Theme.horizontalPageMargin
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
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.paddingLarge

                    SecondaryButton {
                        objectName: "previewDirections"
                        text: qsTr("Directions")
                        onClicked: root.openRoute()
                    }
                    Button {
                        objectName: "previewStart"
                        text: qsTr("Start navigation")
                        onClicked: root.app.startNavigation()
                    }
                }
            }

            // Navigating.
            Item {
                width: parent.width
                height: Theme.itemSizeMedium
                visible: root.mode === "active"

                Column {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - endNav.width - mute.width - Theme.paddingSmall

                    Label {
                        objectName: "navRemaining"
                        width: parent.width
                        text: root.app.arrived ? qsTr("Arrived") : Logic.formatDuration(root.app.remainingRoute.time) + " · " + Logic.formatDistance(root.app.remainingRoute.distance)
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeLarge
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: root.app.selectedPlace ? root.app.selectedPlace.name : ""
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
        }
    }
}
