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
            font.pixelSize: Theme.fontSizeLarge
        }
        Label {
            objectName: "callerLabel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.phone.callName || Phone.format(root.phone.callNumber) || qsTr("Unknown number")
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
            visible: root.phone.callName.length > 0
            text: Phone.format(root.phone.callNumber)
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeLarge
        }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: 2 * Theme.paddingLarge
        }
        spacing: Theme.paddingLarge

        Button {
            objectName: "answerButton"
            anchors.horizontalCenter: parent.horizontalCenter
            preferredWidth: Theme.buttonWidthLarge
            icon.source: "image://theme/icon-m-answer"
            text: qsTr("Answer")
            Accessible.name: qsTr("Answer call from %1").arg(root.phone.callName || root.phone.callNumber)
            onClicked: Telephony.answer()
        }
        Button {
            objectName: "declineButton"
            anchors.horizontalCenter: parent.horizontalCenter
            preferredWidth: Theme.buttonWidthLarge
            color: Theme.errorColor
            icon.source: "image://theme/icon-m-end-call"
            text: qsTr("Decline")
            Accessible.name: qsTr("Decline call from %1").arg(root.phone.callName || root.phone.callNumber)
            onClicked: {
                Telephony.hangup();
                root.phone.closeCallPages();
            }
        }
    }
}
