import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../Phone.js" as Phone

Page {
    id: root

    property var phone
    property bool muted: false
    property bool speaker: false
    property bool keypadOpen: false
    property string tones: ""
    property real now: Date.now()

    readonly property bool connected: phone.callState === "active"
    readonly property string callStatus: {
        if (connected && phone.callStartedAt > 0)
            return Phone.duration((now - phone.callStartedAt) / 1000);
        if (phone.callState === "held")
            return qsTr("On hold");
        return qsTr("Calling…");
    }

    function sendTone(digit) {
        Telephony.sendDTMF(digit);
        tones += digit;
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.status === PageStatus.Active && root.connected && Qt.application.state === Qt.ApplicationActive
        onTriggered: root.now = Date.now()
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: Theme.horizontalPageMargin
            rightMargin: Theme.horizontalPageMargin
            top: parent.top
            topMargin: Theme.itemSizeLarge
        }
        spacing: Theme.paddingMedium

        Label {
            objectName: "statusLabel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.callStatus
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraLarge
            Accessible.name: root.connected ? qsTr("Call duration %1").arg(text) : text
        }
        Label {
            objectName: "nameLabel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.phone.callName || Phone.format(root.phone.callNumber)
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeHuge
            font.weight: Font.ExtraLight
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            Accessible.role: Accessible.Heading
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: text.length > 0
            text: root.keypadOpen && root.tones.length > 0 ? root.tones : root.phone.callName ? Phone.format(root.phone.callNumber) : ""
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeLarge
            elide: Text.ElideLeft
        }
    }

    Keypad {
        objectName: "dtmfKeypad"
        anchors {
            bottom: controls.top
            bottomMargin: Theme.paddingLarge
        }
        visible: root.keypadOpen
        vanityDialNumbersVisible: false
        onClicked: number => root.sendTone(number)
    }

    Column {
        id: controls

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: 2 * Theme.paddingLarge
        }
        spacing: Theme.paddingLarge

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.paddingLarge * 2

            IconButton {
                objectName: "muteButton"
                icon.source: root.muted ? "image://theme/icon-l-mic-mute" : "image://theme/icon-l-mic"
                highlighted: down || root.muted
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("Mute")
                Accessible.checkable: true
                Accessible.checked: root.muted
                onClicked: {
                    root.muted = !root.muted;
                    Telephony.setCallMuted(root.muted);
                }
            }
            IconButton {
                objectName: "keypadButton"
                icon.source: "image://theme/icon-l-dialpad"
                highlighted: down || root.keypadOpen
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("Keypad")
                Accessible.checkable: true
                Accessible.checked: root.keypadOpen
                onClicked: root.keypadOpen = !root.keypadOpen
            }
            IconButton {
                objectName: "speakerButton"
                icon.source: "image://theme/icon-l-speaker"
                highlighted: down || root.speaker
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("Speaker")
                Accessible.checkable: true
                Accessible.checked: root.speaker
                onClicked: {
                    root.speaker = !root.speaker;
                    Telephony.setSpeakerphone(root.speaker);
                }
            }
        }

        Button {
            objectName: "endCallButton"
            anchors.horizontalCenter: parent.horizontalCenter
            preferredWidth: Theme.buttonWidthLarge
            color: Theme.errorColor
            icon.source: "image://theme/icon-m-end-call"
            text: qsTr("End call")
            onClicked: {
                Telephony.hangup();
                root.phone.closeCallPages();
            }
        }
    }
}
