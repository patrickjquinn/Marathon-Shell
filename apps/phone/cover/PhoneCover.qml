import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Phone.js" as Phone

CoverBackground {
    id: root

    property var phone
    property real now: Date.now()
    readonly property bool connected: phone.callState === "active" && phone.callStartedAt > 0

    signal hangupRequested

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.status === Cover.Active && root.connected
        onTriggered: root.now = Date.now()
    }

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: !root.phone.inCall && root.phone.missedCount === 0
        text: qsTr("Phone")
        icon.source: "image://theme/icon-l-phone"
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall
        visible: root.phone.inCall || root.phone.missedCount > 0

        Label {
            objectName: "coverPrimary"
            width: parent.width
            text: root.phone.inCall ? (root.connected ? Phone.duration((root.now - root.phone.callStartedAt) / 1000) : qsTr("Calling…")) : root.phone.missedCount
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeHuge
            font.weight: Font.ExtraLight
            truncationMode: TruncationMode.Fade
        }
        Label {
            objectName: "coverSecondary"
            width: parent.width
            text: root.phone.inCall ? root.phone.callName || Phone.format(root.phone.callNumber) : root.phone.missedCount === 1 ? qsTr("missed call") : qsTr("missed calls")
            font.pixelSize: Theme.fontSizeMedium
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Fade
        }
    }

    CoverActionList {
        enabled: root.phone.inCall

        CoverAction {
            objectName: "hangupAction"
            iconSource: "image://theme/icon-cover-end-call"
            onTriggered: root.hangupRequested()
        }
    }
}
