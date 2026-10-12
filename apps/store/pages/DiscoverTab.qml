pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// Search, then Editors' pick → Trending → Updates → Made for phones → New on
// Flathub. A query replaces the sections with Flathub search results,
// aarch64 builds only.
TabItem {
    id: root

    property var store
    property real topMargin

    property var results: []
    property bool searching: false
    property string searchError: ""
    // Each keystroke restarts the debounce and bumps the generation, so a
    // slow response for "fire" can't overwrite results for "firefox".
    property int generation: 0
    readonly property string query: searchField.text.trim()
    readonly property bool offline: !store.catalogLoading && store.catalogAppCount === 0

    function focusSearch() {
        flick.scrollToTop();
        searchField.forceActiveFocus();
    }

    function runSearch() {
        const gen = ++root.generation;
        if (root.query === "") {
            root.results = [];
            root.searching = false;
            root.searchError = "";
            return;
        }
        root.searching = true;
        root.store.searchApps(root.query, function (list, err) {
            if (gen !== root.generation)
                return;
            root.searching = false;
            root.searchError = err || "";
            root.results = list;
        });
    }

    flickable: flick

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.runSearch()
    }

    SilicaFlickable {
        id: flick

        objectName: "discoverView"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "updateAllItem"
                text: qsTr("Update all")
                visible: root.store.updateApps.length > 0
                onClicked: root.store.updateAll()
            }
            MenuItem {
                objectName: "refreshItem"
                text: qsTr("Refresh")
                onClicked: root.store.loadCatalog()
            }
        }

        ViewPlaceholder {
            objectName: "discoverPlaceholder"
            enabled: root.query !== "" ? !root.searching && root.results.length === 0 : root.offline
            text: root.query === "" ? qsTr("Can't reach Flathub") : root.searchError !== "" ? qsTr("Search isn't available") : qsTr("No results")
            hintText: root.query === "" ? qsTr("Check your connection, then pull down to refresh") : root.searchError !== "" ? qsTr("Couldn't reach Flathub. Check your connection and try again.") : qsTr("Nothing on Flathub for this phone matches \"%1\"").arg(root.query)
        }

        Column {
            id: column

            width: parent.width

            Item {
                width: 1
                height: root.topMargin
            }

            SearchField {
                id: searchField

                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search apps")
                onTextChanged: debounce.restart()
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: {
                    debounce.stop();
                    root.runSearch();
                    focus = false;
                }
            }

            Label {
                objectName: "savedNote"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                visible: root.query === "" && root.store.showingSavedCatalog
                text: qsTr("Offline. Showing apps saved %1. Pull down to refresh.").arg(root.store.timeAgo(root.store.catalogSavedAt))
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            // ── Search results ────────────────────────────
            Column {
                width: parent.width
                visible: root.query !== ""

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: BusyIndicatorSize.Large
                    running: root.searching && root.results.length === 0
                    visible: running
                }
                Repeater {
                    objectName: "searchResults"
                    model: root.query !== "" ? root.results : []
                    delegate: AppRow {
                        required property var modelData
                        width: column.width
                        store: root.store
                        app: modelData
                    }
                }
            }

            // ── Sections ──────────────────────────────────
            Column {
                width: parent.width
                visible: root.query === ""

                BusyIndicator {
                    objectName: "catalogBusy"
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: BusyIndicatorSize.Large
                    running: root.store.catalogLoading && root.store.catalogAppCount === 0
                    visible: running
                }

                SectionHeader {
                    text: qsTr("Editors' pick")
                    visible: hero.visible
                }
                BackgroundItem {
                    id: hero

                    readonly property var app: root.store.heroApp

                    objectName: "heroItem"
                    width: parent.width
                    height: heroContent.height + 2 * Theme.paddingMedium
                    visible: app !== null
                    Accessible.name: app ? qsTr("Editors' pick: %1").arg(app.name || app.app_id || "") : ""
                    onClicked: root.store.openDetail(app)

                    AppIcon {
                        id: heroIcon
                        x: Theme.horizontalPageMargin
                        y: Theme.paddingMedium
                        width: Theme.iconSizeExtraLarge
                        height: width
                        source: hero.app ? root.store.safeImageUrl(hero.app.icon || "") : ""
                    }
                    Column {
                        id: heroContent
                        anchors.left: heroIcon.right
                        anchors.leftMargin: Theme.paddingLarge
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        y: Theme.paddingMedium
                        spacing: Theme.paddingSmall

                        Label {
                            width: parent.width
                            text: hero.app ? (hero.app.name || hero.app.app_id || "") : ""
                            color: hero.highlighted ? Theme.highlightColor : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeLarge
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            text: hero.app ? (hero.app.developer_name || "") : ""
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                            visible: text !== ""
                        }
                        Label {
                            width: parent.width
                            text: hero.app ? (hero.app.summary || "") : ""
                            color: hero.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        GetButton {
                            store: root.store
                            appId: hero.app ? (hero.app.app_id || hero.app.id || "") : ""
                        }
                    }
                }

                SectionHeader {
                    text: qsTr("Trending now")
                    visible: trending.visible
                }
                Row {
                    id: trending

                    x: Theme.horizontalPageMargin - Theme.paddingSmall
                    width: parent.width - 2 * x
                    visible: root.store.trendingApps.length > 0

                    Repeater {
                        model: root.store.trendingApps
                        delegate: BackgroundItem {
                            id: tile

                            required property var modelData
                            readonly property string appId: modelData.app_id || modelData.id || ""
                            readonly property var rating: root.store.ratingFor(appId)

                            width: trending.width / 3
                            height: tileColumn.height + 2 * Theme.paddingMedium
                            Accessible.name: modelData.name || appId
                            Component.onCompleted: {
                                root.store.ensureCategory(modelData);
                                root.store.ensureRating(appId);
                            }
                            onClicked: root.store.openDetail(modelData)

                            Column {
                                id: tileColumn
                                x: Theme.paddingSmall
                                y: Theme.paddingMedium
                                width: parent.width - 2 * Theme.paddingSmall
                                spacing: Theme.paddingSmall

                                AppIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Theme.iconSizeLauncher
                                    height: width
                                    source: root.store.safeImageUrl(tile.modelData.icon || "")
                                }
                                Label {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: tile.modelData.name || tile.appId
                                    color: tile.highlighted ? Theme.highlightColor : Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeSmall
                                    truncationMode: TruncationMode.Fade
                                }
                                Label {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.store.categoryLabel(tile.modelData) || ""
                                    color: Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    truncationMode: TruncationMode.Fade
                                }
                                StarRating {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: tile.rating !== null
                                    value: tile.rating ? tile.rating.average : 0
                                    starSize: Theme.fontSizeExtraSmall * 0.8
                                }
                            }
                        }
                    }
                }

                SectionHeader {
                    text: qsTr("Updates available")
                    visible: root.store.updateApps.length > 0
                }
                Repeater {
                    objectName: "updateRows"
                    model: root.store.updateApps
                    delegate: AppRow {
                        required property var modelData
                        width: column.width
                        store: root.store
                        app: modelData
                    }
                }

                // Flathub's mobile collection: apps that declare a phone form factor.
                SectionHeader {
                    text: qsTr("Made for phones")
                    visible: root.store.mobileApps.length > 0
                }
                Repeater {
                    model: root.store.mobileApps
                    delegate: AppRow {
                        required property var modelData
                        width: column.width
                        store: root.store
                        app: modelData
                    }
                }
                ShowAllItem {
                    objectName: "mobileShowAll"
                    visible: root.store.mobileApps.length > 0
                    onClicked: root.store.openCollection("mobile", qsTr("Made for phones"))
                }

                SectionHeader {
                    text: qsTr("New on Flathub")
                    visible: root.store.newApps.length > 0
                }
                Repeater {
                    model: root.store.newApps
                    delegate: AppRow {
                        required property var modelData
                        width: column.width
                        store: root.store
                        app: modelData
                    }
                }
                ShowAllItem {
                    visible: root.store.newApps.length > 0
                    onClicked: root.store.openCollection("recently-added", qsTr("New on Flathub"))
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
