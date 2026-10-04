pragma ComponentBehavior: Bound

import MarathonApp.Store
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Theme
import QtQuick

// Search as you type against Flathub, aarch64 builds only. Before a query it
// offers categories, so the empty tab is still a way in.
Rectangle {
    id: page

    required property var store

    property var results: []
    property bool searching: false
    property string error: ""
    // Each keystroke restarts the debounce and bumps the generation, so a
    // slow response for "fire" can't overwrite results for "firefox".
    property int generation: 0

    function focusField() {
        field.forceActiveFocus();
    }

    function runSearch() {
        const query = field.text.trim();
        const gen = ++page.generation;
        if (query === "") {
            page.results = [];
            page.searching = false;
            page.error = "";
            return;
        }
        page.searching = true;
        page.store.searchApps(query, function (list, err) {
            if (gen !== page.generation)
                return;
            page.searching = false;
            page.error = err || "";
            page.results = list;
        });
    }

    color: MColors.background

    MTextField {
        id: field
        x: MSpacing.md
        y: page.store.dp(10)
        width: parent.width - MSpacing.md * 2
        placeholder: "Apps, games, developers"
        inputMethodHints: Qt.ImhNoPredictiveText
        onTextChanged: debounce.restart()
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: page.runSearch()
    }

    ListView {
        anchors.top: field.bottom
        anchors.topMargin: page.store.dp(8)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        visible: page.results.length > 0
        model: page.results
        bottomMargin: MSpacing.lg
        delegate: AppRow {
            required property var modelData
            required property int index
            width: ListView.view.width
            store: page.store
            app: modelData
            showDivider: index < page.results.length - 1
        }
    }

    Flickable {
        anchors.top: field.bottom
        anchors.topMargin: MSpacing.lg
        anchors.bottom: parent.bottom
        width: parent.width
        visible: field.text.trim() === ""
        contentHeight: browse.height
        clip: true

        Column {
            id: browse
            width: parent.width
            spacing: page.store.dp(10)

            SectionHeader {
                width: parent.width
                title: "Browse"
            }
            Flow {
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                spacing: MSpacing.sm
                Repeater {
                    model: page.store.categories
                    delegate: MFilterChip {
                        id: chip
                        required property var modelData
                        label: chip.modelData.label
                        onActivated: page.store.openCategory(chip.modelData.id, chip.modelData.label)
                    }
                }
            }
        }
    }

    MActivityIndicator {
        anchors.centerIn: parent
        visible: page.searching && page.results.length === 0
    }

    MEmptyState {
        anchors.centerIn: parent
        width: parent.width - MSpacing.xxl
        visible: !page.searching && field.text.trim() !== "" && page.results.length === 0
        iconName: page.error !== "" ? "wifi-slash" : "magnifying-glass"
        iconSize: page.store.dp(64)
        title: page.error !== "" ? "Search isn't available" : "No results"
        message: page.error !== "" ? page.error : "Nothing on Flathub for this phone matches \"" + field.text.trim() + "\"."
    }
}
