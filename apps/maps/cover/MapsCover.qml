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
        text: qsTr("Search for a place")
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
            width: Theme.iconSizeMedium
            height: width
            source: root.maneuver ? Logic.maneuverIcon(root.maneuver.type) : ""
            color: Theme.highlightColor
        }
        CoverHeadline {
            objectName: "coverHeadline"
            width: parent.width
            value: root.arrived ? "" : Logic.formatDistance(root.distance)
            label: root.maneuver ? root.maneuver.instruction : ""
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
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Theme.fontSizeExtraSmall
        }
        Label {
            width: parent.width
            text: root.place ? root.place.address : ""
            color: Theme.secondaryColor
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeExtraSmall
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
