import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Item {
    id: searchOverlay

    property bool active: false
    property real pullProgress: 0.0  // 0.0 to 1.0, for pull-to-reveal animation
    property string searchQuery: ""
    property var searchResults: []

    signal closed
    signal resultSelected(var result)

    visible: opacity > 0.01
    enabled: opacity > 0.01  // Block interactions whenever visible

    // Opacity: active = full opacity, OR follows pullProgress during gesture
    opacity: active ? 1.0 : Math.max(0.0, pullProgress)

    // Smooth fade-out when search closes or progress resets
    Behavior on opacity {
        enabled: !active
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    // Full-screen mouse blocker when visible at any opacity
    // Excludes nav bar area to allow swipe-up-to-close gesture
    MouseArea {
        anchors.fill: parent
        anchors.bottomMargin: Constants.bottomBarHeight
        enabled: searchOverlay.opacity > 0.01 && !searchOverlay.active
        onClicked: {
            // Clicking on overlay when partially visible dismisses it
            searchOverlay.pullProgress = 0.0;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: MColors.background
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Constants.safeAreaTop + MSpacing.md
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        anchors.bottomMargin: Constants.safeAreaBottom + MSpacing.lg
        spacing: MSpacing.md
        z: 10

        Item {
            width: parent.width
            height: 56

            Rectangle {
                id: searchBarContainer
                anchors.fill: parent
                color: MColors.surface
                radius: MRadius.lg
                border.width: searchInput.activeFocus ? 2 : 1
                border.color: searchInput.activeFocus ? MColors.accentBright : MColors.border
                antialiasing: true

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: MSpacing.sm
                    spacing: MSpacing.sm

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        size: 24
                        color: searchInput.activeFocus ? MColors.accentBright : MColors.textSecondary

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                    }

                    TextInput {
                        id: searchInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 64
                        color: MColors.text
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        selectionColor: MColors.accentBright
                        selectedTextColor: MColors.text
                        clip: true

                        Keys.onEscapePressed: searchOverlay.close()
                        Keys.onDownPressed: resultsList.forceActiveFocus()

                        onTextChanged: {
                            searchOverlay.searchQuery = text;
                            performSearch();
                        }

                        Text {
                            anchors.fill: parent
                            text: "Search apps, settings..."
                            color: MColors.textSecondary
                            font: parent.font
                            visible: !searchInput.text && !searchInput.activeFocus
                        }
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        visible: searchInput.text.length > 0

                        Icon {
                            anchors.centerIn: parent
                            name: "x"
                            size: 16
                            color: MColors.textSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            onClicked: {
                                searchInput.text = "";
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        ListView {
            id: resultsList
            width: parent.width
            height: parent.height - 76
            clip: true
            spacing: MSpacing.xs
            model: searchOverlay.searchResults
            interactive: true
            boundsBehavior: Flickable.StopAtBounds

            Keys.onUpPressed: {
                if (currentIndex === 0) {
                    searchInput.forceActiveFocus();
                } else {
                    decrementCurrentIndex();
                }
            }
            Keys.onReturnPressed: {
                if (currentItem) {
                    var result = searchOverlay.searchResults[currentIndex];
                    selectResult(result);
                }
            }
            Keys.onEscapePressed: searchOverlay.close()

            delegate: Rectangle {
                width: resultsList.width
                height: Constants.appIconSize
                color: resultMouseArea.pressed ? MColors.pressed : (resultsList.currentIndex === index ? MColors.highlightSubtle : "transparent")
                radius: MRadius.md
                antialiasing: true

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: MSpacing.md
                    spacing: MSpacing.md

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 48
                        height: 48
                        radius: modelData.type === "app" ? MRadius.sm : 24
                        color: MColors.elevated
                        antialiasing: true

                        Image {
                            anchors.centerIn: parent
                            width: modelData.type === "app" ? 40 : 24
                            height: modelData.type === "app" ? 40 : 24
                            source: modelData.icon
                            smooth: true
                            antialiasing: true
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 76
                        spacing: MSpacing.xs

                        Text {
                            width: parent.width
                            text: modelData.title
                            color: MColors.text
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightDemiBold
                            font.family: MTypography.fontFamily
                            elide: Text.ElideRight
                        }

                        Row {
                            spacing: MSpacing.sm

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: typeText.width + MSpacing.md
                                height: 20
                                radius: MRadius.sm
                                color: {
                                    if (modelData.type === "app")
                                        return MColors.elevated;
                                    if (modelData.type === "deeplink")
                                        return Qt.rgba(139 / 255, 92 / 255, 246 / 255, 0.15);
                                    return Qt.rgba(59 / 255, 130 / 255, 246 / 255, 0.15);
                                }
                                antialiasing: Constants.enableAntialiasing

                                Text {
                                    id: typeText
                                    anchors.centerIn: parent
                                    text: {
                                        if (modelData.type === "app")
                                            return "App";
                                        if (modelData.type === "deeplink")
                                            return "Page";
                                        return "Setting";
                                    }
                                    color: {
                                        if (modelData.type === "app")
                                            return MColors.accentBright;
                                        if (modelData.type === "deeplink")
                                            return Qt.rgba(167 / 255, 139 / 255, 250 / 255, 1.0);
                                        return Qt.rgba(96 / 255, 165 / 255, 250 / 255, 1.0);
                                    }
                                    font.pixelSize: MTypography.sizeSmall
                                    font.weight: MTypography.weightMedium
                                    font.family: MTypography.fontFamily
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.subtitle
                                color: MColors.textSecondary
                                font.pixelSize: MTypography.sizeSmall
                                font.family: MTypography.fontFamily
                            }
                        }
                    }
                }

                MouseArea {
                    id: resultMouseArea
                    anchors.fill: parent
                    onClicked: {
                        resultsList.currentIndex = index;
                        selectResult(modelData);
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: searchInput.text.length === 0 ? "Start typing to search" : "No results found"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                visible: resultsList.count === 0
            }
        }
    }

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
        // Prevent double execution
        if (searchOverlay.opacity < 1.0 || !active) {
            return;
        }

        Logger.info("Search", "Result selected: " + result.title + " (type: " + result.type + ")");
        UnifiedSearchService.addToRecentSearches(searchQuery);

        // Close first to prevent double-tap through
        close();

        // Execute after a brief delay to ensure search is closed
        Qt.callLater(function () {
            // Emit signal to parent (MarathonShell) to handle launch
            resultSelected(result);
        });
    }

    onActiveChanged: {
        if (active) {
            Logger.info("Search", "Search became active - focusing input");
            Qt.callLater(function () {
                searchInput.forceActiveFocus();
            });
        } else {
            searchInput.text = "";
            searchResults = [];
            Logger.info("Search", "Search became inactive - emitting closed signal");
            closed();
        }
    }
}
