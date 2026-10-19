pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic

Page {
    id: page

    readonly property var runtime: AndroidApps.runtime || ({})
    readonly property string runState: runtime.state || "stopped"
    readonly property bool stopped: runState === "stopped"

    function openReset() {
        const dialog = pageStack.push(Qt.resolvedUrl("AndroidResetDialog.qml"));
        dialog.accepted.connect(() => remorse.execute(qsTr("Resetting Android"), () => AndroidApps.resetAndroid()));
    }

    component EntryItem: ListItem {
        id: entry

        property string title
        property string subtitle

        contentHeight: Math.max(Theme.itemSizeMedium, entryColumn.height + 2 * Theme.paddingMedium)
        Accessible.name: title + ", " + subtitle

        Column {
            id: entryColumn

            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            opacity: entry.enabled ? 1 : Theme.opacityLow

            Label {
                width: parent.width
                text: entry.title
                truncationMode: TruncationMode.Fade
                color: entry.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                width: parent.width
                text: entry.subtitle
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: entry.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
        }
    }

    objectName: "androidPage"
    Component.onCompleted: AndroidApps.refresh()

    // Memory and uptime move while the page is open.
    Timer {
        interval: 5000
        repeat: true
        running: page.status === PageStatus.Active && Application.state === Qt.ApplicationActive
        onTriggered: AndroidApps.refreshRuntime()
    }

    RemorsePopup {
        id: remorse
    }

    Connections {
        target: AndroidApps

        function onDone(pkg, action) {
            if (action === "reset")
                Notices.show(qsTr("Android apps removed"));
        }
        function onFailed(pkg, action, error) {
            if (pkg === "")
                Notices.show(qsTr("Couldn't do that: %1").arg(error));
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            objectName: "pulley"

            MenuItem {
                objectName: "restartItem"
                visible: page.runState === "running"
                text: qsTr("Restart Android")
                onClicked: AndroidApps.restart()
            }
            MenuItem {
                objectName: "startStopItem"
                text: page.stopped ? qsTr("Start Android") : qsTr("Stop Android")
                onClicked: {
                    if (page.stopped)
                        AndroidApps.start();
                    else
                        remorse.execute(qsTr("Stopping Android apps"), () => AndroidApps.stop());
                }
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Android apps")
            }
            DetailItem {
                objectName: "stateItem"
                label: qsTr("Status")
                value: Logic.androidState(page.runState)
            }
            DetailItem {
                objectName: "versionItem"
                visible: !page.stopped && value !== ""
                label: qsTr("Android version")
                value: page.runtime.androidVersion || ""
            }
            DetailItem {
                objectName: "memoryItem"
                visible: !page.stopped && (page.runtime.memoryBytes || 0) > 0
                label: qsTr("Memory")
                value: Logic.dataSize(page.runtime.memoryBytes)
            }
            DetailItem {
                objectName: "uptimeItem"
                visible: page.runState === "running"
                label: qsTr("Running for")
                value: Logic.duration(page.runtime.uptimeSeconds)
            }
            Label {
                objectName: "stoppedNote"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.stopped
                topPadding: Theme.paddingSmall
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Android apps start when you open one. Pull down to start them now.")
            }
            TextSwitch {
                objectName: "startAtLoginSwitch"
                text: qsTr("Start at login")
                description: qsTr("Android apps open faster and their notifications arrive from the start, at the cost of memory and battery")
                automaticCheck: false
                checked: !!page.runtime.startAtLogin
                onClicked: AndroidApps.setStartAtLogin(!checked)
            }

            SectionHeader {
                text: qsTr("Apps")
            }
            EntryItem {
                objectName: "appsEntry"
                title: qsTr("Installed apps")
                subtitle: qsTr("%n apps", "", AndroidApps.apps.length)
                onClicked: pageStack.push(Qt.resolvedUrl("AndroidAppsPage.qml"))
            }
            EntryItem {
                objectName: "accessEntry"
                title: qsTr("Special access")
                subtitle: qsTr("All files, installing apps, alarms and more")
                onClicked: pageStack.push(Qt.resolvedUrl("AndroidAccessListPage.qml"))
            }

            SectionHeader {
                text: qsTr("Reset")
            }
            EntryItem {
                objectName: "resetEntry"
                enabled: page.runState === "running"
                title: qsTr("Reset Android")
                subtitle: enabled ? qsTr("Removes every Android app and its data") : qsTr("Start Android first")
                onClicked: page.openReset()
            }
        }

        VerticalScrollDecorator {}
    }
}
