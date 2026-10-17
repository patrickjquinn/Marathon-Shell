pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../Phone.js" as Phone

TabItem {
    id: root

    property var phone
    property real headerOffset

    signal openInDialer(string number)

    flickable: list

    SilicaListView {
        id: list

        objectName: "callLog"
        anchors.fill: parent
        model: Phone.groupCalls(root.phone.callHistory)
        // With a pulley menu the tab spans the tab bar too.
        header: Item {
            width: list.width
            height: root.headerOffset
        }

        PullDownMenu {
            visible: list.count > 0

            MenuItem {
                objectName: "clearMenuItem"
                text: qsTr("Clear call log")
                onClicked: clearRemorse.execute(qsTr("Cleared call log"), () => CallHistory.clearHistory())
            }
        }

        RemorsePopup {
            id: clearRemorse
        }

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
            readonly property bool declined: modelData.type === "rejected"
            readonly property int count: modelData.ids.length
            readonly property real when: Phone.timestampMs(modelData.timestamp)

            function remove() {
                const ids = item.modelData.ids;
                item.remorseDelete(function () {
                    ids.forEach(id => CallHistory.deleteCall(id));
                });
            }

            objectName: "callLogItem"
            contentHeight: Theme.itemSizeMedium
            Accessible.name: (missed ? qsTr("Missed call from %1") : declined ? qsTr("Declined call from %1") : modelData.type === "outgoing" ? qsTr("Call to %1") : qsTr("Call from %1")).arg(name || number) + (count > 1 ? ", " + qsTr("%n calls", "", count) : "")
            menu: ContextMenu {
                MenuItem {
                    objectName: "editMenuItem"
                    text: qsTr("Edit before calling")
                    onClicked: root.openInDialer(item.number)
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
            onClicked: root.phone.call(number)

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

                Row {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        objectName: "callerLabel"
                        width: Math.min(implicitWidth, parent.width - (countLabel.visible ? countLabel.width + parent.spacing : 0))
                        text: item.name || Phone.format(item.number) || qsTr("Unknown number")
                        truncationMode: TruncationMode.Fade
                        color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        id: countLabel

                        objectName: "countLabel"
                        visible: item.count > 1
                        text: "(" + item.count + ")"
                        color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    }
                }
                Label {
                    objectName: "detailLabel"
                    width: parent.width
                    visible: text.length > 0
                    text: [item.name ? Phone.format(item.number) : "", item.declined ? qsTr("Declined") : "", item.modelData.duration > 0 ? Phone.duration(item.modelData.duration) : ""].filter(s => s.length > 0).join(" · ")
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
