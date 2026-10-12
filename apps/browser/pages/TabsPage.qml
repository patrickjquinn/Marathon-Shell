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

    SilicaListView {
        id: view

        objectName: "tabsView"
        anchors.fill: parent
        spacing: Theme.paddingLarge
        model: root.browser.tabs

        header: PageHeader {
            title: root.browser.isPrivateMode ? qsTr("Private tabs") : qsTr("Tabs")
        }

        PullDownMenu {
            MenuItem {
                objectName: "closeAllItem"
                text: qsTr("Close all tabs")
                onClicked: remorse.execute(qsTr("Closed all tabs"), function () {
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

        // A card per tab: title bar with close, then the page thumbnail.
        delegate: ListItem {
            id: card

            required property int index
            required property int tabId
            required property string title
            required property string url
            required property string thumbnail

            readonly property bool current: index === root.browser.currentTabIndex

            width: view.width
            contentHeight: Math.round((width - 2 * Theme.horizontalPageMargin) * 2 / 3)
            Accessible.name: (title || qsTr("New tab")) + (current ? ", " + qsTr("current tab") : "")
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Close tab")
                    onClicked: root.browser.closeTab(card.tabId)
                }
            }
            onClicked: root.openTab(tabId)

            Item {
                anchors {
                    fill: parent
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                }
                clip: true

                Rectangle {
                    anchors.fill: parent
                    visible: card.thumbnail === ""
                    color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityLow)

                    Icon {
                        anchors.centerIn: parent
                        source: "image://theme/icon-l-browser"
                        color: Theme.secondaryColor
                    }
                }
                Image {
                    objectName: "thumbnail"
                    anchors {
                        fill: parent
                        topMargin: titleBar.height
                    }
                    source: card.thumbnail
                    fillMode: Image.PreserveAspectCrop
                    verticalAlignment: Image.AlignTop
                    asynchronous: true
                }
                Rectangle {
                    id: titleBar

                    width: parent.width
                    height: Theme.itemSizeExtraSmall
                    color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay)

                    Label {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.paddingLarge
                            right: closeButton.left
                            verticalCenter: parent.verticalCenter
                        }
                        text: card.title || Logic.displayHost(card.url) || qsTr("New tab")
                        truncationMode: TruncationMode.Fade
                        color: card.current || card.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    IconButton {
                        id: closeButton

                        objectName: "closeTabButton"
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        icon.source: "image://theme/icon-m-close"
                        Accessible.name: qsTr("Close tab")
                        onClicked: root.browser.closeTab(card.tabId)
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
