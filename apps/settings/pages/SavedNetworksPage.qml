pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

// Every Wi-Fi network this phone remembers, in range or not.
Page {
    id: page

    property var networks: []

    onStatusChanged: if (status === PageStatus.Active)
        networks = Network.savedNetworks()

    SilicaListView {
        id: list

        anchors.fill: parent
        model: page.networks
        header: PageHeader {
            title: qsTr("Saved networks")
        }

        delegate: ListItem {
            id: row

            required property var modelData

            objectName: "saved-" + modelData.ssid
            contentHeight: Theme.itemSizeSmall
            menu: Component {
                ContextMenu {
                    MenuItem {
                        text: qsTr("Forget network")
                        onClicked: {
                            const ssid = row.modelData.ssid;
                            row.remorseDelete(() => {
                                Network.forgetNetwork(ssid);
                                page.networks = page.networks.filter(n => n.ssid !== ssid);
                            });
                        }
                    }
                }
            }
            onClicked: pageStack.push(Qt.resolvedUrl("NetworkPage.qml"), {
                ssid: modelData.ssid
            })

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.ssid
                color: row.modelData.ssid === Network.wifiSsid && Network.wifiConnected || row.highlighted ? Theme.highlightColor : Theme.primaryColor
                truncationMode: TruncationMode.Fade
            }
        }

        ViewPlaceholder {
            enabled: list.count === 0
            text: qsTr("No saved networks")
        }

        VerticalScrollDecorator {}
    }
}
