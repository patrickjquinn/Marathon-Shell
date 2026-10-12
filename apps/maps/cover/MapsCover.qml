pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MapsLogic.js" as Logic

CoverBackground {
    id: root

    property bool navigating
    property var maneuver: null
    property real distance
    property bool arrived
    property var place: null
    property bool voiceAvailable
    property bool muted

    signal searchRequested
    signal muteToggled

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: !root.navigating && !root.place
        text: qsTr("Maps")
        icon.source: "image://theme/icon-l-location"
    }

    Column {
        objectName: "coverNavigation"
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall
        visible: root.navigating

        Icon {
            width: Theme.iconSizeLarge
            height: width
            source: root.maneuver ? Logic.maneuverIcon(root.maneuver.type) : ""
            color: Theme.highlightColor
        }
        Label {
            objectName: "coverDistance"
            visible: !root.arrived
            text: Logic.formatDistance(root.distance)
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraLarge
        }
        Label {
            objectName: "coverInstruction"
            width: parent.width
            text: root.maneuver ? root.maneuver.instruction : ""
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeMedium
        }
    }

    Column {
        objectName: "coverPlace"
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall
        visible: !root.navigating && root.place !== null

        Icon {
            source: "image://theme/icon-m-location"
            color: Theme.highlightColor
        }
        Label {
            objectName: "coverPlaceName"
            width: parent.width
            text: root.place ? root.place.name : ""
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeLarge
        }
        Label {
            width: parent.width
            text: root.place ? root.place.address : ""
            color: Theme.secondaryColor
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeMedium
        }
    }

    // Ending a route stays in the app: a stray tap on Home shouldn't drop it.
    CoverActionList {
        objectName: "searchActions"
        enabled: !root.navigating

        CoverAction {
            objectName: "coverAction"
            iconSource: "image://theme/icon-cover-search"
            onTriggered: root.searchRequested()
        }
    }
    CoverActionList {
        objectName: "voiceActions"
        enabled: root.navigating && root.voiceAvailable

        CoverAction {
            objectName: "muteAction"
            iconSource: root.muted ? "image://theme/icon-cover-speaker" : "image://theme/icon-cover-speaker-mute"
            onTriggered: root.muteToggled()
        }
    }
}
