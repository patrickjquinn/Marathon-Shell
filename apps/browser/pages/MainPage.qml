pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../BrowserLogic.js" as Logic
import "../components"

Page {
    id: root

    property var browser

    readonly property var tab: browser.currentTab
    readonly property bool loading: tab !== null && tab.isLoading === true
    readonly property bool bookmarked: tab !== null && Logic.isBookmarked(browser.bookmarks, tab.url)
    property bool toolbarShown: true
    property real _lastScrollY: 0
    readonly property bool toolbarOpen: toolbarShown || loading || browser.editingAddress || menuPanel.open
    readonly property alias addressField: addressField
    readonly property alias menuPanel: menuPanel

    function startEditing() {
        browser.editingAddress = true;
        addressField.text = tab ? tab.url : "";
        addressField.forceActiveFocus();
        addressField.selectAll();
    }

    function stopEditing() {
        browser.editingAddress = false;
        addressField.focus = false;
    }

    // A rejected address stays in the field with its scheme selected.
    function open(text) {
        const target = Logic.resolveInput(text, browser.searchEngineUrl);
        if (target.error) {
            Notices.show(target.error);
            addressField.forceActiveFocus();
            addressField.select(addressField.text.search(/\S/), addressField.text.indexOf(":") + 1);
            return;
        }
        stopEditing();
        browser.navigateTo(text);
    }

    function closeOverlays() {
        if (menuPanel.open) {
            menuPanel.hide();
            return true;
        }
        if (browser.editingAddress) {
            stopEditing();
            return true;
        }
        return false;
    }

    function showPage(name) {
        menuPanel.hide();
        pageStack.push(Qt.resolvedUrl(name), { browser: browser });
    }

    function showTabs() {
        if (browser.webLayer)
            browser.webLayer.capture();
        pageStack.push(Qt.resolvedUrl("TabsPage.qml"), { browser: browser });
    }

    function followScroll(y) {
        if (y <= 0) {
            toolbarShown = true;
        } else if (Math.abs(y - _lastScrollY) < Theme.paddingLarge) {
            return;
        } else {
            toolbarShown = y < _lastScrollY;
        }
        _lastScrollY = y;
    }

    objectName: "mainPage"
    backNavigation: false
    showNavigationIndicator: false

    Connections {
        target: root.browser
        function onAddressRequested() {
            root.startEditing();
        }
        function onCurrentTabIndexChanged() {
            root.toolbarShown = true;
            root._lastScrollY = 0;
        }
    }

    Loader {
        id: webLoader

        anchors {
            fill: parent
            bottomMargin: root.toolbarOpen ? toolbar.height : 0
        }
        Component.onCompleted: setSource(root.browser.webLayerSource, { browser: root.browser })
        onLoaded: root.browser.webLayer = item
    }

    Connections {
        target: webLoader.item
        function onScrolled(y) {
            root.followScroll(y);
        }
    }

    MouseArea {
        objectName: "addressDimmer"
        anchors.fill: parent
        visible: root.browser.editingAddress
        onClicked: root.stopEditing()

        Rectangle {
            anchors.fill: parent
            color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay)
        }
    }

    SilicaListView {
        id: suggestionView

        objectName: "suggestionView"
        anchors {
            left: parent.left
            right: parent.right
            bottom: toolbar.top
        }
        height: Math.min(contentHeight, toolbar.y)
        visible: root.browser.editingAddress && count > 0
        verticalLayoutDirection: ListView.BottomToTop
        clip: true
        model: root.browser.editingAddress ? Logic.suggestions(addressField.text === (root.tab ? root.tab.url : "") ? "" : addressField.text, root.browser.bookmarks, root.browser.history, root.browser.searchEngineName) : []

        delegate: ListItem {
            id: suggestion

            required property var modelData

            contentHeight: Theme.itemSizeMedium
            Accessible.name: modelData.title
            onClicked: root.open(modelData.value)

            Icon {
                id: kindIcon

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: {
                    switch (suggestion.modelData.kind) {
                    case "bookmark":
                        return "image://theme/icon-m-favorite";
                    case "history":
                        return "image://theme/icon-m-history";
                    case "go":
                        return "image://theme/icon-m-right";
                    default:
                        return "image://theme/icon-m-search";
                    }
                }
                highlighted: suggestion.highlighted
            }
            Column {
                anchors {
                    left: kindIcon.right
                    leftMargin: Theme.paddingMedium
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: suggestion.modelData.title
                    truncationMode: TruncationMode.Fade
                    color: suggestion.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    text: suggestion.modelData.subtitle
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: suggestion.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }

    Rectangle {
        id: toolbar

        objectName: "toolbar"
        width: parent.width
        height: Theme.itemSizeMedium
        // Animating y itself would also animate page resizes.
        property real offset: root.toolbarOpen ? 0 : height

        y: parent.height - height + offset
        color: root.browser.isPrivateMode ? Theme.highlightDimmerColor : Theme.overlayBackgroundColor

        Behavior on offset {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        Rectangle {
            objectName: "progressBar"
            width: root.loading ? parent.width * Math.max(root.tab.loadProgress, 5) / 100 : 0
            height: Math.max(2, Math.round(Theme.pixelRatio * 3))
            visible: root.loading
            color: Theme.highlightColor
        }

        Row {
            id: buttons

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            visible: !root.browser.editingAddress

            TabCountButton {
                objectName: "tabsButton"
                width: Theme.itemSizeSmall
                height: Theme.itemSizeSmall
                count: root.browser.tabs.count
                onClicked: root.showTabs()
            }
            IconButton {
                id: backButton

                objectName: "backButton"
                width: Theme.itemSizeSmall
                icon.source: "image://theme/icon-m-back"
                enabled: root.tab !== null && root.tab.canGoBack === true
                Accessible.name: qsTr("Back")
                onClicked: root.browser.goBack()
            }
            BackgroundItem {
                id: addressButton

                readonly property string badge: root.tab ? Logic.schemeBadge(root.tab.url) : "none"
                readonly property string host: root.tab && !root.tab.isNewTab ? Logic.displayHost(root.tab.url) : ""

                objectName: "addressButton"
                width: parent.width - 3 * Theme.itemSizeSmall
                height: Theme.itemSizeSmall
                Accessible.name: qsTr("Address: %1").arg(host || placeholder.text)
                onClicked: root.startEditing()

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.paddingSmall

                    Icon {
                        objectName: "schemeIcon"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.browser.isPrivateMode || addressButton.badge !== "none"
                        source: root.browser.isPrivateMode ? "image://theme/icon-s-privacy"
                              : addressButton.badge === "secure" ? "image://theme/icon-s-lock" : "image://theme/icon-s-warning"
                        color: addressButton.badge === "insecure" ? Theme.errorColor : Theme.secondaryColor
                    }
                    Label {
                        id: placeholder

                        objectName: "hostLabel"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, addressButton.width - 2 * Theme.paddingMedium - Theme.iconSizeSmall)
                        text: addressButton.host || (root.browser.isPrivateMode ? qsTr("Private browsing") : qsTr("Search or enter address"))
                        color: addressButton.host ? (addressButton.highlighted ? Theme.highlightColor : Theme.primaryColor) : Theme.secondaryColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }
            IconButton {
                objectName: "menuButton"
                width: Theme.itemSizeSmall
                icon.source: "image://theme/icon-m-menu"
                Accessible.name: qsTr("Menu")
                onClicked: menuPanel.open ? menuPanel.hide() : menuPanel.show()
            }
        }

        SearchField {
            id: addressField

            objectName: "addressField"
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            visible: root.browser.editingAddress
            placeholderText: qsTr("Search or enter address")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: root.open(text)
        }
    }

    // Above the toolbar, so the panel docks onto it rather than under it.
    Item {
        anchors {
            top: parent.top
            bottom: toolbar.top
            left: parent.left
            right: parent.right
        }

        MouseArea {
            objectName: "menuDimmer"
            anchors.fill: parent
            visible: menuPanel.expanded
            onClicked: menuPanel.hide()

            Rectangle {
                anchors.fill: parent
                color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay)
            }
        }

        DockedPanel {
            id: menuPanel

            objectName: "menuPanel"
            width: parent.width
            height: menuColumn.height
            dock: Dock.Bottom

            Column {
                id: menuColumn

                width: parent.width
                topPadding: Theme.paddingMedium

                MenuRow {
                    objectName: "newTabRow"
                    iconSource: "image://theme/icon-m-add"
                    text: qsTr("New tab")
                    onClicked: {
                        menuPanel.hide();
                        root.browser.createNewTab();
                    }
                }
                MenuRow {
                    objectName: "privateRow"
                    iconSource: "image://theme/icon-m-privacy"
                    text: root.browser.isPrivateMode ? qsTr("Leave private browsing") : qsTr("Private browsing")
                    onClicked: {
                        menuPanel.hide();
                        root.browser.setPrivateMode(!root.browser.isPrivateMode);
                    }
                }
                MenuRow {
                    objectName: "bookmarksRow"
                    iconSource: "image://theme/icon-m-favorite-selected"
                    text: qsTr("Bookmarks")
                    onClicked: root.showPage("BookmarksPage.qml")
                }
                MenuRow {
                    objectName: "historyRow"
                    iconSource: "image://theme/icon-m-history"
                    text: qsTr("History")
                    onClicked: root.showPage("HistoryPage.qml")
                }
                MenuRow {
                    objectName: "settingsRow"
                    iconSource: "image://theme/icon-m-settings"
                    text: qsTr("Settings")
                    onClicked: root.showPage("SettingsPage.qml")
                }

                // Page tools sit nearest the toolbar, as in Sailfish Browser.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: Theme.itemSizeMedium

                    IconButton {
                        objectName: "forwardButton"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.itemSizeLarge
                        icon.source: "image://theme/icon-m-forward"
                        enabled: root.tab !== null && root.tab.canGoForward === true
                        Accessible.name: qsTr("Forward")
                        onClicked: {
                            menuPanel.hide();
                            root.browser.goForward();
                        }
                    }
                    IconButton {
                        objectName: "bookmarkButton"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.itemSizeLarge
                        enabled: !root.browser.isPrivateMode && root.tab !== null && Logic.schemeBadge(root.tab.url) !== "none"
                        icon.source: root.bookmarked ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                        Accessible.name: root.bookmarked ? qsTr("Remove bookmark") : qsTr("Bookmark this page")
                        onClicked: root.browser.toggleBookmark()
                    }
                    IconButton {
                        objectName: "reloadButton"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.itemSizeLarge
                        icon.source: root.loading ? "image://theme/icon-m-close" : "image://theme/icon-m-refresh"
                        Accessible.name: root.loading ? qsTr("Stop loading") : qsTr("Reload")
                        onClicked: {
                            menuPanel.hide();
                            root.browser.reloadOrStop();
                        }
                    }
                }
            }
        }
    }
}
