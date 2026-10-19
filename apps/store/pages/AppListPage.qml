pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// A full list of apps behind a title: a category, or a Discover section's
// "Show all". `source` is a Flathub collection path such as
// "collection/category/game" or "collection/mobile".
Page {
    id: root

    property var store
    property string title
    property string source

    property var apps: []
    property bool loading: true
    property string error: ""
    property real savedAt: 0

    function load() {
        root.loading = true;
        root.error = "";
        if (source === "android/recent") {
            root.apps = store.recentAndroid(300);
            root.loading = false;
            return;
        }
        // A category lists the Android apps in it after Flathub's.
        const category = source.indexOf("collection/category/") === 0 ? source.substring(20) : "";
        store.loadList(source, function (list, err, savedAt) {
            root.loading = false;
            root.error = err || "";
            root.savedAt = savedAt;
            root.apps = category !== "" ? list.concat(store.androidInCategory(category)) : list;
        });
    }

    Component.onCompleted: load()

    SilicaListView {
        id: list

        objectName: "appList"
        anchors.fill: parent
        model: root.apps
        header: PageHeader {
            title: root.title
            description: root.savedAt > 0 ? qsTr("Offline. Saved %1").arg(root.store.timeAgo(root.savedAt)) : ""
        }

        PullDownMenu {
            visible: root.error !== ""
            MenuItem {
                objectName: "retryItem"
                text: qsTr("Try again")
                onClicked: root.load()
            }
        }

        ViewPlaceholder {
            objectName: "listPlaceholder"
            enabled: !root.loading && root.apps.length === 0
            text: root.error !== "" ? qsTr("Couldn't load apps") : qsTr("Nothing here for this phone yet")
            hintText: root.error !== "" ? qsTr("Check your connection, then pull down to try again") : qsTr("None of the apps in this list are built for this phone's processor.")
        }

        delegate: AppRow {
            required property var modelData
            width: list.width
            store: root.store
            app: modelData
        }

        VerticalScrollDecorator {}
    }

    PageBusyIndicator {
        running: root.loading
    }
}
