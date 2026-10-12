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
        id: info

        anchors {
            left: parent.left
            right: parent.right
            leftMargin: Theme.horizontalPageMargin
            rightMargin: Theme.horizontalPageMargin
            top: parent.top
            topMargin: root.keypadOpen ? Theme.paddingLarge : Theme.itemSizeLarge
        }
        spacing: Theme.paddingSmall

        Label {
            objectName: "nameLabel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.phone.callName || Phone.format(root.phone.callNumber)
            font.pixelSize: Theme.fontSizeExtraLarge
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
            color: Theme.secondaryColor
            elide: Text.ElideLeft
        }
        Label {
            objectName: "statusLabel"
            width: parent.width
            topPadding: root.keypadOpen ? 0 : Theme.paddingLarge
            horizontalAlignment: Text.AlignHCenter
            text: root.callStatus
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeHuge
            font.weight: Font.ExtraLight
            Accessible.name: root.connected ? qsTr("Call duration %1").arg(text) : text
        }
    }

    Row {
        anchors {
            top: info.bottom
            topMargin: Theme.paddingLarge
            horizontalCenter: parent.horizontalCenter
        }
        spacing: Theme.paddingLarge

        CallToggle {
            name: "speaker"
            checked: root.speaker
            icon: "image://theme/icon-l-speaker"
            text: qsTr("Speaker")
            onToggled: {
                root.speaker = !root.speaker;
                Telephony.setSpeakerphone(root.speaker);
            }
        }
        CallToggle {
            name: "keypad"
            checked: root.keypadOpen
            icon: "image://theme/icon-l-dialpad"
            text: qsTr("Keypad")
            onToggled: root.keypadOpen = !root.keypadOpen
        }
        CallToggle {
            name: "mute"
            checked: root.muted
            icon: root.muted ? "image://theme/icon-l-mic-mute" : "image://theme/icon-l-mic"
            text: qsTr("Mute")
            onToggled: {
                root.muted = !root.muted;
                Telephony.setCallMuted(root.muted);
            }
        }
    }

    Keypad {
        objectName: "dtmfKeypad"
        anchors {
            bottom: endCallButton.top
            bottomMargin: Theme.paddingLarge
        }
        visible: root.keypadOpen
        vanityDialNumbersVisible: false
        onClicked: number => root.sendTone(number)
    }

    Button {
        id: endCallButton

        objectName: "endCallButton"
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 2 * Theme.paddingLarge
        }
        preferredWidth: Theme.buttonWidthLarge
        icon.source: "image://theme/icon-m-end-call"
        text: qsTr("End call")
        onClicked: {
            Telephony.hangup();
            root.phone.closeCallPages();
        }
    }

    component CallToggle: Column {
        id: toggle

        property string name
        property bool checked
        property string icon
        property string text

        signal toggled

        width: Theme.itemSizeExtraLarge

        Switch {
            objectName: toggle.name + "Button"
            anchors.horizontalCenter: parent.horizontalCenter
            automaticCheck: false
            checked: toggle.checked
            icon.source: toggle.icon
            Accessible.name: toggle.text
            onClicked: toggle.toggled()
        }
        Label {
            objectName: toggle.name + "Label"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: toggle.text
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            wrapMode: Text.Wrap
            Accessible.ignored: true
        }
    }
}
