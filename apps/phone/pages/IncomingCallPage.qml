import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../Phone.js" as Phone

Page {
    id: root

    property var phone

    backNavigation: false

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
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Incoming call")
            color: Theme.highlightColor
        }
        Label {
            objectName: "callerLabel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.phone.callName || Phone.format(root.phone.callNumber) || qsTr("Unknown number")
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
            visible: root.phone.callName.length > 0
            text: Phone.format(root.phone.callNumber)
            color: Theme.secondaryColor
        }
    }

    Row {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: answerButton.top
            bottomMargin: Theme.itemSizeMedium
        }
        spacing: Theme.paddingLarge

        LabelledButton {
            name: "message"
            visible: root.phone.callNumber.length > 0
            icon: "image://theme/icon-m-message"
            text: qsTr("Message")
            accessibleName: qsTr("Decline and send a message to %1").arg(root.phone.callName || root.phone.callNumber)
            onClicked: {
                const number = root.phone.callNumber;
                Telephony.hangup();
                root.phone.closeCallPages();
                root.phone.sendMessage(number);
            }
        }
        LabelledButton {
            name: "decline"
            icon: "image://theme/icon-m-end-call"
            text: qsTr("Decline")
            accessibleName: qsTr("Decline call from %1").arg(root.phone.callName || root.phone.callNumber)
            onClicked: {
                Telephony.hangup();
                root.phone.closeCallPages();
            }
        }
    }

    Button {
        id: answerButton

        objectName: "answerButton"
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 2 * Theme.paddingLarge
        }
        preferredWidth: Theme.buttonWidthLarge
        icon.source: "image://theme/icon-m-answer"
        text: qsTr("Answer")
        Accessible.name: qsTr("Answer call from %1").arg(root.phone.callName || root.phone.callNumber)
        onClicked: Telephony.answer()
    }

    component LabelledButton: Column {
        id: labelled

        property string name
        property string icon
        property string text
        property string accessibleName

        signal clicked

        width: Theme.itemSizeExtraLarge

        IconButton {
            id: button

            objectName: labelled.name + "Button"
            anchors.horizontalCenter: parent.horizontalCenter
            icon.source: labelled.icon
            Accessible.name: labelled.accessibleName
            onClicked: labelled.clicked()
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: labelled.text
            color: button.highlighted ? Theme.highlightColor : Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.Wrap
            Accessible.ignored: true
        }
    }
}
