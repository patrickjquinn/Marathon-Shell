pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import QtQml.Models

Page {
    id: root

    property var phone
    readonly property alias tabs: tabs

    function openDialer(number) {
        phone.dialedNumber = number;
        tabs.moveTo(0);
    }

    BackgroundItem {
        id: returnToCall

        objectName: "returnToCall"
        width: parent.width
        height: visible ? Theme.itemSizeSmall : 0
        visible: root.phone.inCall && !root.phone.callPage
        highlighted: true
        Accessible.role: Accessible.Button
        Accessible.name: label.text
        onClicked: root.phone.showCallPage()

        Label {
            id: label

            anchors.centerIn: parent
            width: parent.width - 2 * Theme.horizontalPageMargin
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Call in progress. Tap to return")
            color: Theme.highlightColor
            truncationMode: TruncationMode.Fade
        }
    }

    TabView {
        id: tabs

        anchors {
            top: returnToCall.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        model: ObjectModel {
            TabItem {
                DialerPanel {
                    anchors.fill: parent
                    phone: root.phone
                }
            }
            CallLogTab {
                phone: root.phone
                headerOffset: tabs.tabBarHeight
                onOpenInDialer: number => root.openDialer(number)
            }
            PeopleTab {
                phone: root.phone
                headerOffset: tabs.tabBarHeight
            }
        }
        header: TabBar {
            objectName: "tabBar"
            model: [
                { title: qsTr("Dialer") },
                { title: qsTr("Call log"), count: root.phone.missedCount },
                { title: qsTr("People") }
            ]
        }
        onCurrentIndexChanged: {
            if (currentIndex === 1)
                root.phone.markCallLogSeen();
            else if (currentIndex === 2)
                root.phone.requestContacts();
        }
    }
}
