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
        text: qsTr("No missed calls")
        icon.source: "image://theme/icon-l-phone"
    }

    CoverHeadline {
        objectName: "coverHeadline"
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        visible: root.phone.inCall || root.phone.missedCount > 0
        value: root.phone.inCall ? (root.connected ? Phone.duration((root.now - root.phone.callStartedAt) / 1000) : qsTr("Calling…")) : root.phone.missedCount
        label: root.phone.inCall ? root.phone.callName || Phone.format(root.phone.callNumber) : root.phone.missedCount === 1 ? qsTr("missed call") : qsTr("missed calls")
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
