pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../Phone.js" as Phone

TabItem {
    id: root

    property var phone

    signal openInDialer(string number)

    flickable: list

    SilicaListView {
        id: list

        objectName: "callLog"
        anchors.fill: parent
        model: root.phone.callHistory

        ViewPlaceholder {
            enabled: list.count === 0
            text: qsTr("No calls")
            hintText: qsTr("Calls you make or receive appear here")
        }

        delegate: ListItem {
            id: item

            required property var modelData
            readonly property string number: modelData.number || ""
            readonly property string name: modelData.contactName || root.phone.contactName(number)
            readonly property bool missed: modelData.type === "missed"
            readonly property real when: Phone.timestampMs(modelData.timestamp)

            function remove() {
                item.remorseDelete(function () {
                    CallHistory.deleteCall(item.modelData.id);
                });
            }

            objectName: "callLogItem"
            contentHeight: Theme.itemSizeMedium
            Accessible.name: (missed ? qsTr("Missed call from %1") : modelData.type === "outgoing" ? qsTr("Call to %1") : qsTr("Call from %1")).arg(name || number)
            menu: ContextMenu {
                MenuItem {
                    objectName: "callMenuItem"
                    text: qsTr("Call")
                    onClicked: root.phone.call(item.number)
                }
                MenuItem {
                    objectName: "messageMenuItem"
                    text: qsTr("Send message")
                    onClicked: root.phone.sendMessage(item.number)
                }
                MenuItem {
                    objectName: "deleteMenuItem"
                    text: qsTr("Delete")
                    onClicked: item.remove()
                }
            }
            onClicked: root.openInDialer(number)

            Icon {
                id: typeIcon

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: "image://theme/icon-s-" + (item.missed ? "missed-call" : item.modelData.type === "outgoing" ? "outgoing-call" : "incoming-call")
                color: item.missed ? Theme.errorColor : item.highlighted ? Theme.highlightColor : Theme.secondaryColor
            }

            Column {
                anchors {
                    left: typeIcon.right
                    leftMargin: Theme.paddingMedium
                    right: timeLabel.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.name || Phone.format(item.number) || qsTr("Unknown number")
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : item.missed ? Theme.errorColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: [item.name ? Phone.format(item.number) : "", item.modelData.duration > 0 ? Phone.duration(item.modelData.duration) : ""].filter(s => s.length > 0).join(" · ")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }

            Label {
                id: timeLabel

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: item.when > 0 ? Format.formatDate(new Date(item.when), Formatter.CallTimeRelative) : ""
                font.pixelSize: Theme.fontSizeExtraSmall
                color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
