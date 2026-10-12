pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Page {
    id: page

    readonly property var channels: [
        { value: "stable", title: qsTr("Stable"), description: qsTr("Tagged releases only") },
        { value: "edge", title: qsTr("Edge"), description: qsTr("Includes pre-releases") }
    ]

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: Updates.checking

            MenuItem {
                objectName: "releaseItem"
                text: qsTr("View release")
                visible: Updates.releaseUrl !== ""
                onClicked: Updates.openInBrowser()
            }
            MenuItem {
                objectName: "checkItem"
                text: Updates.checking ? qsTr("Checking…") : qsTr("Check now")
                enabled: !Updates.checking
                onClicked: Updates.checkNow()
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Software updates")
            }
            Label {
                objectName: "statusLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                text: Updates.checking ? qsTr("Checking for updates…") : Updates.updateAvailable ? qsTr("Update %1 is available").arg(Updates.latestVersion) : qsTr("Up to date")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
            }
            DetailItem {
                objectName: "currentVersion"
                label: qsTr("Installed")
                value: Updates.currentVersion || "—"
            }
            DetailItem {
                objectName: "latestVersion"
                label: qsTr("Latest")
                value: Updates.latestVersion || "—"
            }
            DetailItem {
                objectName: "lastError"
                visible: Updates.lastError !== ""
                label: qsTr("Last error")
                value: Updates.lastError
            }
            ComboBox {
                objectName: "channelCombo"
                width: parent.width
                label: qsTr("Channel")
                description: currentIndex >= 0 ? page.channels[currentIndex].description : ""
                Binding on currentIndex {
                    value: page.channels.findIndex(c => c.value === Updates.channel)
                }
                menu: ContextMenu {
                    Repeater {
                        model: page.channels

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: Updates.setChannel(modelData.value)
                        }
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Updates come from the GitHub Releases feed, checked every 6 hours. Pull down to check now.")
            }
        }

        VerticalScrollDecorator {}
    }
}
