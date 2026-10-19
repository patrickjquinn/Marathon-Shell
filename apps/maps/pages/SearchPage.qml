pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: root

    property var app
    property string query: ""

    function choose(place) {
        app.selectPlace(place);
        pageStack.replace(Qt.resolvedUrl("PlacePage.qml"), { app: root.app });
    }

    objectName: "searchPage"
    // A search asked for from outside runs at once.
    Component.onCompleted: {
        if (query.trim() !== "")
            app.search(query.trim());
    }
    onQueryChanged: {
        if (query.trim().length > 2) {
            searchTimer.restart();
            return;
        }
        searchTimer.stop();
        app.search("");
    }

    Timer {
        id: searchTimer

        interval: 500
        onTriggered: root.app.search(root.query.trim())
    }

    SilicaListView {
        id: view

        objectName: "resultsView"
        anchors.fill: parent
        readonly property bool showingRecent: root.query.trim() === ""

        model: showingRecent ? root.app.recentPlaces : root.app.searchResults

        header: Column {
            width: view.width

            Connections {
                target: root
                function onStatusChanged() {
                    if (root.status === PageStatus.Active)
                        searchField.forceActiveFocus();
                }
            }

            PageHeader {
                title: qsTr("Search")
            }
            SearchField {
                id: searchField

                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search places")
                text: root.query
                onTextChanged: root.query = text
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    searchTimer.stop();
                    root.app.search(root.query.trim());
                    focus = false;
                }
            }
            SectionHeader {
                objectName: "recentHeader"
                text: qsTr("Recent")
                visible: view.showingRecent && view.count > 0
            }
        }

        PullDownMenu {
            MenuItem {
                objectName: "retryItem"
                visible: root.app.searchError !== ""
                text: qsTr("Try again")
                onClicked: root.app.search(root.app.lastQuery)
            }
            MenuItem {
                text: qsTr("Show my location")
                onClicked: {
                    root.app.locateMe();
                    pageStack.pop();
                }
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: !root.app.searching && view.count === 0
            text: root.app.searchError !== "" ? qsTr("Search didn't work") : root.app.lastQuery !== "" && !view.showingRecent ? qsTr("No places found") : qsTr("Find a place")
            hintText: root.app.searchError !== "" ? root.app.searchError : root.app.lastQuery !== "" && !view.showingRecent ? qsTr("Check the spelling, or try a street, city or postcode") : qsTr("Type an address, a place or a postcode")
        }

        BusyIndicator {
            objectName: "searchBusy"
            anchors.horizontalCenter: parent.horizontalCenter
            y: view.headerItem ? view.headerItem.height + Theme.paddingLarge * 4 : 0
            size: BusyIndicatorSize.Large
            running: root.app.searching
        }

        delegate: ListItem {
            id: item

            required property var modelData

            contentHeight: Theme.itemSizeMedium
            Accessible.name: modelData.name + ", " + modelData.address
            onClicked: root.choose(item.modelData)

            Icon {
                id: pin

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: view.showingRecent ? "image://theme/icon-m-history" : "image://theme/icon-m-location"
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Column {
                anchors {
                    left: pin.right
                    leftMargin: Theme.paddingMedium
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: Theme.highlightText(item.modelData.name, root.query.trim(), Theme.highlightColor)
                    textFormat: Text.StyledText
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: item.modelData.address
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
