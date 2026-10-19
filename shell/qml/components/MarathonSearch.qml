pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Item {
    id: searchOverlay

    property bool active: false
    property real pullProgress: 0
    property string searchQuery: ""
    property var searchResults: []

    signal closed
    signal resultSelected(var result)

    function open() {
        searchInput.forceActiveFocus();
        Logger.info("Search", "Search overlay opened - input focused");
    }

    function close() {
        searchInput.text = "";
        searchResults = [];
        closed();
        Logger.info("Search", "Search overlay closed");
    }

    function setKeyboardVisible(show) {
        if (!Platform.hasHardwareKeyboard) {
            InputMethodEngine.showKeyboard(show);
        }
    }

    function ensureInputFocus() {
        if (searchInput.activeFocus)
            return;

        Qt.callLater(function () {
            searchInput.forceActiveFocus();
            setKeyboardVisible(true);
        });
    }

    function appendToSearch(text) {
        searchInput.text += text;
        searchInput.forceActiveFocus();
    }

    function performSearch() {
        if (searchQuery.trim().length === 0) {
            searchResults = [];
            return;
        }
        var results = UnifiedSearchService.search(searchQuery);
        searchResults = results.slice(0, 20);
        Logger.info("Search", "Search performed: '" + searchQuery + "' - " + searchResults.length + " results");
    }

    function selectResult(result) {
        if (searchOverlay.opacity < 1 || !active)
            return;

        Logger.info("Search", "Result selected: " + result.title + " (type: " + result.type + ")");
        UnifiedSearchService.addToRecentSearches(searchQuery);
        close();
        Qt.callLater(function () {
            resultSelected(result);
        });
    }

    visible: opacity > 0.01
    enabled: opacity > 0.01
    opacity: active ? 1 : Math.max(0, pullProgress)
    onActiveChanged: {
        if (active) {
            Logger.info("Search", "Search became active - focusing input");
            ensureInputFocus();
        } else {
            searchInput.text = "";
            searchResults = [];
            setKeyboardVisible(false);
            Logger.info("Search", "Search became inactive - emitting closed signal");
            closed();
        }
    }

    onPullProgressChanged: {
        if (pullProgress > 0 && !active)
            ensureInputFocus();
    }

    MouseArea {
        anchors.fill: parent
        anchors.bottomMargin: Constants.bottomBarHeight
        enabled: searchOverlay.opacity > 0.01 && !searchOverlay.active
        onClicked: {
            searchOverlay.pullProgress = 0;
        }
    }

    KeelAmbienceBackground {
        anchors.fill: parent
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Constants.safeAreaTop + Silica.Theme.paddingLarge
        anchors.bottomMargin: Constants.safeAreaBottom + Silica.Theme.paddingLarge
        spacing: Silica.Theme.paddingMedium
        z: 10

        // Silica's search field: a magnifier, the text, and an underline lit
        // while focused.
        Item {
            id: searchBarContainer

            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * Silica.Theme.horizontalPageMargin
            height: Silica.Theme.itemSizeSmall

            GlyphIcon {
                id: searchGlyph

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: Silica.Theme.iconSizeSmall
                color: searchInput.activeFocus ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            }

            TextInput {
                id: searchInput

                anchors.left: searchGlyph.right
                anchors.leftMargin: Silica.Theme.paddingLarge
                anchors.right: clearButton.left
                anchors.rightMargin: Silica.Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeMedium
                font.family: Silica.Theme.fontFamily
                selectionColor: Silica.Theme.highlightColor
                selectedTextColor: Silica.Theme.highlightDimmerColor
                clip: true
                Keys.onEscapePressed: searchOverlay.close()
                Keys.onDownPressed: resultsList.forceActiveFocus()
                onTextChanged: {
                    searchOverlay.searchQuery = text;
                    searchOverlay.performSearch();
                }

                Text {
                    anchors.fill: parent
                    text: qsTr("Search apps and settings")
                    color: Silica.Theme.secondaryColor
                    font: parent.font
                    elide: Text.ElideRight
                    visible: !searchInput.text && !searchInput.preeditText
                }
            }

            Item {
                id: clearButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Silica.Theme.iconSizeSmall
                height: width
                visible: searchInput.text.length > 0

                GlyphIcon {
                    anchors.centerIn: parent
                    name: "x"
                    size: Silica.Theme.iconSizeSmall
                    color: Silica.Theme.primaryColor
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Clear search"

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Silica.Theme.paddingMedium
                    onClicked: {
                        searchInput.text = "";
                        searchInput.forceActiveFocus();
                    }
                }
            }

            Rectangle {
                anchors.left: searchInput.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                color: searchInput.activeFocus ? Silica.Theme.highlightColor : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)
            }
        }

        ListView {
            id: resultsList

            width: parent.width
            height: parent.height - searchBarContainer.height - parent.spacing
            clip: true
            model: searchOverlay.searchResults
            interactive: true
            flickDeceleration: MMotion.flickDeceleration
            maximumFlickVelocity: MMotion.flickVelocity
            boundsBehavior: Flickable.StopAtBounds
            Keys.onUpPressed: {
                if (currentIndex === 0)
                    searchInput.forceActiveFocus();
                else
                    decrementCurrentIndex();
            }
            Keys.onReturnPressed: {
                if (currentItem) {
                    var result = searchOverlay.searchResults[currentIndex];
                    searchOverlay.selectResult(result);
                }
            }
            Keys.onEscapePressed: searchOverlay.close()

            Text {
                anchors.centerIn: parent
                text: searchInput.text.length === 0 ? qsTr("Search apps, settings and more") : qsTr("No results for \u201c%1\u201d").arg(searchInput.text)
                color: Silica.Theme.secondaryHighlightColor
                font.pixelSize: Silica.Theme.fontSizeLarge
                font.family: Silica.Theme.fontFamily
                width: parent.width - 2 * Silica.Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: resultsList.count === 0 && !recentColumn.visible
            }

            Column {
                id: recentColumn

                width: parent.width
                visible: searchInput.text.length === 0 && UnifiedSearchService.recentSearches.length > 0

                Item {
                    width: parent.width
                    height: Silica.Theme.itemSizeExtraSmall

                    Text {
                        id: clearRecent

                        anchors.left: parent.left
                        anchors.leftMargin: Silica.Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Clear")
                        color: Silica.Theme.primaryColor
                        font.pixelSize: Silica.Theme.fontSizeSmall
                        font.family: Silica.Theme.fontFamily

                        Accessible.role: Accessible.Button
                        Accessible.name: "Clear recent searches"
                        Accessible.onPressAction: UnifiedSearchService.clearRecentSearches()

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Silica.Theme.paddingMedium
                            onClicked: UnifiedSearchService.clearRecentSearches()
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Silica.Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Recent")
                        color: Silica.Theme.highlightColor
                        font.pixelSize: Silica.Theme.fontSizeSmall
                        font.family: Silica.Theme.fontFamily
                    }
                }

                Repeater {
                    model: UnifiedSearchService.recentSearches

                    Item {
                        id: recentItem

                        required property string modelData

                        width: recentColumn.width
                        height: Silica.Theme.itemSizeSmall

                        Accessible.role: Accessible.Button
                        Accessible.name: "Search for " + modelData
                        Accessible.onPressAction: searchInput.text = modelData

                        Row {
                            x: Silica.Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Silica.Theme.paddingLarge

                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "clock-counter-clockwise"
                                size: Silica.Theme.iconSizeSmall
                                color: Silica.Theme.secondaryColor
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: recentItem.modelData
                                color: Silica.Theme.primaryColor
                                font.pixelSize: Silica.Theme.fontSizeMedium
                                font.family: Silica.Theme.fontFamily
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                searchInput.text = recentItem.modelData;
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            delegate: Rectangle {
                id: resultDelegate

                required property var modelData
                required property int index

                readonly property bool down: resultMouseArea.pressed || resultsList.currentIndex === index && resultsList.activeFocus

                width: resultsList.width
                height: Silica.Theme.itemSizeMedium
                color: down ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"

                MAppIcon {
                    id: resultIcon

                    x: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: resultDelegate.modelData.icon
                    size: resultDelegate.modelData.type === "app" ? Silica.Theme.iconSizeMedium : Silica.Theme.iconSizeSmall
                    width: Silica.Theme.iconSizeMedium
                    height: width
                }

                Column {
                    anchors.left: resultIcon.right
                    anchors.leftMargin: Silica.Theme.paddingLarge
                    anchors.right: parent.right
                    anchors.rightMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: resultDelegate.modelData.title
                        color: resultDelegate.down ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                        font.pixelSize: Silica.Theme.fontSizeMedium
                        font.family: Silica.Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: {
                            const type = resultDelegate.modelData.type === "app" ? qsTr("App") : resultDelegate.modelData.type === "deeplink" ? qsTr("Page") : qsTr("Setting");
                            return resultDelegate.modelData.subtitle ? type + " · " + resultDelegate.modelData.subtitle : type;
                        }
                        color: resultDelegate.down ? Silica.Theme.secondaryHighlightColor : Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                        font.family: Silica.Theme.fontFamily
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: resultMouseArea

                    anchors.fill: parent
                    onClicked: {
                        resultsList.currentIndex = resultDelegate.index;
                        searchOverlay.selectResult(resultDelegate.modelData);
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }
        }
    }

    Behavior on opacity {
        enabled: !searchOverlay.active

        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
}
