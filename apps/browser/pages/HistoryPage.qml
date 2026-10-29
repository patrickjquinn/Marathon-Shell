pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../BrowserLogic.js" as Logic

Page {
    id: root

    property var browser
    property string searchText: ""

    readonly property var shown: Logic.matches(browser.history, searchText)

    function open(url) {
        browser.navigateTo(url);
        pageStack.pop();
    }

    // A ListModel, since ListView sections need model roles.
    function rebuild() {
        const now = Date.now();
        entries.clear();
        for (const h of shown)
            entries.append({
                url: h.url,
                title: h.title || h.url,
                visits: h.visitCount || 1,
                group: Logic.dateGroup(h.timestamp, now)
            });
    }

    objectName: "historyPage"
    onShownChanged: rebuild()
    Component.onCompleted: rebuild()

    ListModel {
        id: entries
    }

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: view

        objectName: "historyView"
        anchors.fill: parent
        model: entries
        section.property: "group"
        section.delegate: SectionHeader {
            required property string section

            text: ({
                    "Today": qsTr("Today"),
                    "Yesterday": qsTr("Yesterday"),
                    "This week": qsTr("This week")
                })[section] || qsTr("Older")
        }

        header: Column {
            width: view.width

            PageHeader {
                title: qsTr("History")
            }
            SearchField {
                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search history")
                visible: root.browser.history.length > 0
                onTextChanged: root.searchText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        PullDownMenu {
            visible: root.browser.history.length > 0

            MenuItem {
                objectName: "clearHistoryItem"
                text: qsTr("Clear history")
                onClicked: remorse.execute(qsTr("Clearing history"), function () {
                    root.browser.clearHistory();
                })
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: entries.count === 0
            text: root.browser.history.length === 0 ? qsTr("No history yet") : qsTr("No matching pages")
            hintText: root.browser.history.length === 0 ? (root.browser.isPrivateMode ? qsTr("Private browsing doesn't keep history") : qsTr("Pages you visit show up here")) : qsTr("Try a different word")
        }

        delegate: ListItem {
            id: item

            required property string url
            required property string title
            required property int visits

            contentHeight: Theme.itemSizeMedium
            Accessible.name: title
            menu: ContextMenu {
                MenuItem {
                    objectName: "deleteItem"
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function () {
                        root.browser.removeHistory(item.url);
                    })
                }
            }
            onClicked: root.open(url)

            Column {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: visitsLabel.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.title
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: Logic.displayHost(item.url)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
            Label {
                id: visitsLabel

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                visible: item.visits > 1
                width: visible ? implicitWidth : 0
                text: qsTr("%1 visits").arg(item.visits)
                font.pixelSize: Theme.fontSizeExtraSmall
                color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
