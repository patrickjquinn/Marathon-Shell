pragma ComponentBehavior: Bound

import MarathonApp.Store
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick

// A full list of apps behind a title: a category, or a Discover section's
// "See all". `source` is a Flathub collection path such as
// "collection/category/game" or "collection/mobile".
Rectangle {
    id: page

    required property var store
    required property string title
    required property string source

    property var apps: []
    property bool loading: true
    property string error: ""

    function load() {
        page.loading = true;
        page.error = "";
        store.loadList(source, function (list, err) {
            page.loading = false;
            page.error = err || "";
            page.apps = list;
        });
    }

    color: MColors.background
    Component.onCompleted: load()

    MTopBar {
        id: bar
        width: parent.width
        title: page.title
        showBack: true
        onBackClicked: page.store.goBack()
    }

    ListView {
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        model: page.apps
        bottomMargin: MSpacing.lg
        delegate: AppRow {
            required property var modelData
            required property int index
            width: ListView.view.width
            store: page.store
            app: modelData
            showDivider: index < page.apps.length - 1
        }
    }

    MActivityIndicator {
        anchors.centerIn: parent
        visible: page.loading
    }

    MEmptyState {
        anchors.centerIn: parent
        width: parent.width - MSpacing.xxl
        visible: !page.loading && page.apps.length === 0
        iconName: page.error !== "" ? "wifi-slash" : "package"
        iconSize: page.store.dp(64)
        title: page.error !== "" ? "Couldn't load apps" : "Nothing here for this phone yet"
        actionText: page.error !== "" ? "Try again" : ""
        onActionClicked: page.load()
        message: page.error !== "" ? "Couldn't reach Flathub. Check your connection and try again." : "None of the apps in this list are built for this phone's processor."
    }
}
