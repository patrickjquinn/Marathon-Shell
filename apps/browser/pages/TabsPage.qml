pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../BrowserLogic.js" as Logic

Page {
    id: root

    property var browser

    function openTab(tabId) {
        browser.switchToTab(tabId);
        pageStack.pop();
    }

    function newTab() {
        pageStack.pop();
        browser.createNewTab();
    }

    objectName: "tabsPage"

    RemorsePopup {
        id: remorse
    }

    SilicaGridView {
        id: grid

        objectName: "tabsGrid"
        anchors.fill: parent
        cellWidth: width / 2
        cellHeight: Math.round(cellWidth * 4 / 3)
        model: root.browser.tabs

        header: PageHeader {
            title: root.browser.isPrivateMode ? qsTr("Private tabs") : qsTr("Tabs")
        }

        PullDownMenu {
            MenuItem {
                objectName: "closeAllItem"
                text: qsTr("Close all tabs")
                onClicked: remorse.execute(qsTr("Closing all tabs"), function () {
                    root.browser.closeAllTabs();
                })
            }
            MenuItem {
                objectName: "newTabItem"
                text: root.browser.tabs.count >= root.browser.maxTabs ? qsTr("Tab limit reached") : qsTr("New tab")
                enabled: root.browser.tabs.count < root.browser.maxTabs
                onClicked: root.newTab()
            }
        }

        delegate: GridItem {
            id: cell

            required property var model
            required property int index
            required property int tabId
            required property string title
            required property string url
            required property string thumbnail

            readonly property bool current: index === root.browser.currentTabIndex

            width: grid.cellWidth
            contentHeight: grid.cellHeight
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: (title || qsTr("New tab")) + (current ? ", " + qsTr("current tab") : "")
            Accessible.onPressAction: root.openTab(tabId)
            Keys.onReturnPressed: root.openTab(tabId)
            Keys.onSpacePressed: root.openTab(tabId)
            onClicked: root.openTab(tabId)

            Rectangle {
                id: frame

                anchors {
                    fill: parent
                    margins: Theme.paddingSmall
                }
                radius: Theme.paddingSmall
                color: Qt.rgba(0, 0, 0, 0.55)
                border.width: cell.current ? Math.max(2, Math.round(Theme.pixelRatio * 2)) : 0
                border.color: Theme.highlightColor
                clip: true

                Icon {
                    anchors.centerIn: parent
                    visible: cell.thumbnail === ""
                    source: "image://theme/icon-l-browser"
                    color: Theme.secondaryColor
                }
                Image {
                    objectName: "thumbnail"
                    anchors {
                        fill: parent
                        margins: frame.border.width
                    }
                    source: cell.thumbnail
                    fillMode: Image.PreserveAspectCrop
                    verticalAlignment: Image.AlignTop
                    asynchronous: true
                }
                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        margins: frame.border.width
                    }
                    height: Theme.itemSizeSmall
                    color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay)

                    Label {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.paddingMedium
                            right: parent.right
                            rightMargin: Theme.paddingMedium
                            verticalCenter: parent.verticalCenter
                        }
                        text: cell.title || Logic.displayHost(cell.url) || qsTr("New tab")
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                        color: cell.current || cell.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                }
            }

            IconButton {
                objectName: "closeTabButton"
                anchors {
                    top: frame.top
                    right: frame.right
                }
                icon.source: "image://theme/icon-m-close"
                Accessible.name: qsTr("Close tab")
                onClicked: root.browser.closeTab(cell.tabId)

                Rectangle {
                    anchors.centerIn: parent
                    z: -1
                    width: Theme.iconSizeMedium
                    height: width
                    radius: width / 2
                    color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay)
                }
            }
            FocusFrame {
                parent: cell
            }
        }

        VerticalScrollDecorator {}
    }
}
