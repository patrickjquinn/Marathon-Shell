pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    property string kind
    // An app that asked for this access itself: only its switch is shown.
    property string focusPkg
    property var apps: []
    readonly property var shown: focusPkg !== "" && apps.some(a => a.pkg === focusPkg) ? apps.filter(a => a.pkg === focusPkg) : apps
    property bool loading: true
    readonly property var info: Logic.androidAccessKind(kind)

    function load() {
        AndroidApps.loadSpecialAccess(kind);
    }

    objectName: "androidAccessPage"
    Component.onCompleted: load()

    Connections {
        target: AndroidApps

        function onSpecialAccessLoaded(kind, apps) {
            if (kind !== page.kind)
                return;
            page.apps = apps;
            page.loading = false;
        }
        function onAppChanged(pkg) {
            if (page.apps.some(a => a.pkg === pkg))
                page.load();
        }
        function onFailed(pkg, action, error) {
            if (action === "loadSpecialAccess") {
                page.loading = false;
            } else if (action === "setSpecialAccess" && page.apps.some(a => a.pkg === pkg)) {
                Notices.show(qsTr("Couldn't change that: %1").arg(error));
                page.load();
            }
        }
    }

    SilicaListView {
        id: view

        objectName: "accessApps"
        anchors.fill: parent
        model: page.shown
        header: Column {
            width: view.width

            PageHeader {
                title: page.info.title
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.info.description
            }
        }

        delegate: TextSwitch {
            required property var modelData

            objectName: "access-" + modelData.pkg
            text: modelData.label
            automaticCheck: false
            checked: modelData.granted
            onClicked: AndroidApps.setSpecialAccess(page.kind, modelData.pkg, !checked)
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading
        }

        ViewPlaceholder {
            objectName: "noAccessApps"
            enabled: !page.loading && view.count === 0
            text: qsTr("No apps ask for this")
        }

        VerticalScrollDecorator {}
    }
}
