import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Nemo.Ngf 1.0
import "../Phone.js" as Phone

Item {
    id: root

    property var phone
    property bool _plusHeld: false
    readonly property string number: phone ? phone.dialedNumber : ""
    readonly property string match: number.length >= 3 && !phone.emergencyOnly ? phone.contactName(number) : ""
    readonly property bool emergency: phone ? phone.emergencyOnly || Phone.isEmergency(number) : false
    readonly property bool canCall: number.length > 0 && (Telephony.hasModem || emergency)

    function append(text) {
        phone.dialedNumber = number + text;
    }

    function backspace() {
        phone.dialedNumber = number.slice(0, -1);
    }

    function call() {
        if (canCall)
            phone.call(number);
    }

    activeFocusOnTab: true
    focus: true
    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Dialer")
    Keys.onPressed: function (event) {
        if (event.text.length === 1 && "0123456789*#+".indexOf(event.text) !== -1)
            root.append(event.text);
        else if (event.key === Qt.Key_Backspace)
            root.backspace();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.call();
        else
            return;
        event.accepted = true;
    }

    NonGraphicalFeedback {
        id: keyFeedback

        event: "keypad_press"
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            bottom: keypad.top
            bottomMargin: Theme.paddingLarge
        }
        spacing: Theme.paddingSmall

        Item {
            width: parent.width
            height: numberLabel.height

            Label {
                id: numberLabel

                objectName: "numberLabel"
                x: Theme.horizontalPageMargin + backspaceButton.width
                width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                text: root.number.length > 0 ? Phone.format(root.number) : !Telephony.hasModem ? qsTr("No SIM or modem") : root.phone && root.phone.emergencyOnly ? qsTr("Emergency number") : qsTr("Enter number")
                color: root.number.length > 0 ? Theme.primaryColor : Theme.secondaryColor
                font.pixelSize: root.number.length > 0 ? Theme.fontSizeHuge : Theme.fontSizeLarge
                font.weight: Font.ExtraLight
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: root.number.length > 0 ? Theme.fontSizeLarge : Theme.fontSizeMedium
                elide: Text.ElideLeft
                Accessible.name: root.number.length > 0 ? root.number.split("").join(" ") : text
            }

            IconButton {
                id: backspaceButton

                objectName: "backspaceButton"
                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: numberLabel.verticalCenter
                }
                enabled: root.number.length > 0
                opacity: enabled ? 1 : 0
                icon.source: "image://theme/icon-m-backspace"
                Accessible.name: qsTr("Delete digit")
                onClicked: root.backspace()
                onPressAndHold: root.phone.dialedNumber = ""
            }
        }

        Label {
            objectName: "matchLabel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.number.length > 0 && !root.canCall ? qsTr("Calls aren't available") : root.match
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
            opacity: text.length > 0 ? 1 : 0
        }
    }

    Keypad {
        id: keypad

        objectName: "keypad"
        anchors {
            bottom: callButton.top
            bottomMargin: Theme.paddingLarge
        }
        vanityDialNumbers: ["", "abc", "def", "ghi", "jkl", "mno", "pqrs", "tuv", "wxyz", "", "+", ""]
        onPressed: keyFeedback.play()
        onPressAndHold: function (number) {
            if (number === "0") {
                root._plusHeld = true;
                root.append("+");
            }
        }
        onClicked: function (number) {
            if (root._plusHeld)
                root._plusHeld = false;
            else
                root.append(number);
        }
    }

    Button {
        id: callButton

        objectName: "callButton"
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 2 * Theme.paddingLarge
        }
        preferredWidth: Theme.buttonWidthLarge
        enabled: root.canCall
        icon.source: "image://theme/icon-m-call"
        text: root.emergency ? qsTr("Emergency call") : qsTr("Call")
        onClicked: root.call()
    }
}
