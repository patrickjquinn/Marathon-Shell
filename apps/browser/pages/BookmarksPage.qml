pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../BrowserLogic.js" as Logic

Page {
    id: root

    property var browser
    property string searchText: ""

    readonly property var tab: browser.currentTab
    readonly property bool canBookmark: tab !== null && Logic.schemeBadge(tab.url) !== "none"
    readonly property bool bookmarked: tab !== null && Logic.isBookmarked(browser.bookmarks, tab.url)
    readonly property var shown: Logic.matches(browser.bookmarks, searchText)

    function open(url) {
        browser.navigateTo(url);
        pageStack.pop();
    }

    objectName: "bookmarksPage"

    SilicaListView {
        id: view

        objectName: "bookmarksView"
        anchors.fill: parent
        model: root.shown

        header: Column {
            width: view.width

            PageHeader {
                title: qsTr("Bookmarks")
            }
            SearchField {
                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search bookmarks")
                visible: root.browser.bookmarks.length > 0
                onTextChanged: root.searchText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        PullDownMenu {
            objectName: "pulley"
            visible: root.canBookmark && !root.browser.isPrivateMode

            MenuItem {
                objectName: "toggleBookmarkItem"
                text: root.bookmarked ? qsTr("Remove bookmark for this page") : qsTr("Bookmark this page")
                onClicked: root.browser.toggleBookmark()
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: root.shown.length === 0
            text: root.browser.bookmarks.length === 0 ? qsTr("No bookmarks yet") : qsTr("No matching bookmarks")
            hintText: root.browser.bookmarks.length > 0 ? qsTr("Try a different word") : root.browser.isPrivateMode ? qsTr("Bookmarks are off in private browsing") : qsTr("Pull down to bookmark the page you're on")
        }

        delegate: ListItem {
            id: item

            required property var modelData

            contentHeight: Theme.itemSizeMedium
            Accessible.name: modelData.title || modelData.url
            menu: ContextMenu {
                MenuItem {
                    objectName: "deleteItem"
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function () {
                        root.browser.removeBookmark(item.modelData.url);
                    })
                }
            }
            onClicked: root.open(modelData.url)

            Column {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.modelData.title || item.modelData.url
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: Logic.displayHost(item.modelData.url)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
