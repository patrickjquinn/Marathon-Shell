pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Page {
    id: page

    readonly property string updateState: Updates.state
    readonly property bool busy: updateState === "checking" || updateState === "downloading"

    function statusText() {
        switch (updateState) {
        case "unsupported":
            return qsTr("This device can't install updates yet");
        case "checking":
            return qsTr("Checking for updates…");
        case "upToDate":
            return qsTr("Up to date");
        case "available":
            return qsTr("Marathon OS %1 is available").arg(Updates.availableVersion);
        case "downloading":
            return qsTr("Downloading Marathon OS %1…").arg(Updates.availableVersion);
        case "readyToReboot":
            return qsTr("Marathon OS %1 is ready to install").arg(Updates.availableVersion);
        case "rolledBack":
            return qsTr("Marathon OS %1 didn't start").arg(Updates.rolledBackVersion);
        case "error":
            return Updates.availableVersion !== "" ? qsTr("Couldn't install Marathon OS %1").arg(Updates.availableVersion) : qsTr("Couldn't check for updates");
        default:
            return qsTr("Not checked yet");
        }
    }

    function hintText() {
        switch (updateState) {
        case "unsupported":
            return qsTr("Its storage isn't laid out for over-the-air updates. Flash a newer image to update it.");
        case "available":
            if (Updates.blockedReason === "metered")
                return qsTr("Connect to Wi-Fi to download this update.");
            if (Updates.blockedReason === "battery")
                return qsTr("Charge to at least 30%, or plug in, to download this update.");
            return "";
        case "readyToReboot":
            if (Security.dataEncryption === "pin")
                return qsTr("Restart to finish. Your phone asks for its PIN when it starts, so it won't restart by itself overnight. If it doesn't start properly, it goes back to the version it has now.");
            return Updates.restartScheduled ? qsTr("It restarts tonight between 2 and 5 AM, on charge and not in use. If it doesn't start properly, your phone goes back to the version it has now.") : qsTr("Restart to finish. If it doesn't start properly, your phone goes back to the version it has now.");
        case "rolledBack":
            return qsTr("Your phone went back to %1. A fixed update will be offered when it's published.").arg(Updates.osVersion);
        case "error":
            return Updates.availableVersion !== "" ? qsTr("The download didn't finish. Pull down to try again.") : qsTr("Couldn't reach the update server. Check your connection, then pull down to try again.");
        default:
            return "";
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.busy
            visible: page.updateState !== "unsupported"

            MenuItem {
                objectName: "checkItem"
                text: page.updateState === "checking" ? qsTr("Checking…") : qsTr("Check now")
                enabled: !page.busy && page.updateState !== "readyToReboot"
                onClicked: Updates.checkNow()
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Software updates")
            }
            Label {
                objectName: "statusLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                text: page.statusText()
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
            }
            Label {
                objectName: "sizeLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                visible: page.updateState === "available" && Updates.downloadSize >= 0
                text: visible ? qsTr("Download size: %1").arg(Qt.locale().formattedDataSize(Updates.downloadSize)) : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }
            Label {
                objectName: "notesLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                visible: (page.updateState === "available" || page.updateState === "downloading" || page.updateState === "readyToReboot") && Updates.releaseNotes !== ""
                text: Updates.releaseNotes
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }
            Label {
                objectName: "hintLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                visible: text !== ""
                text: page.hintText()
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }
            ProgressBar {
                objectName: "downloadProgress"
                width: parent.width
                visible: page.updateState === "downloading"
                minimumValue: 0
                maximumValue: 100
                value: Updates.progress
                label: qsTr("%1%").arg(Updates.progress)
            }
            Button {
                objectName: "installButton"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.updateState === "available"
                text: qsTr("Download and install")
                onClicked: Updates.install()
            }
            Button {
                objectName: "cancelButton"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.updateState === "downloading"
                text: qsTr("Cancel")
                onClicked: Updates.cancel()
            }
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: page.updateState === "readyToReboot"

                Button {
                    objectName: "rebootButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Restart now")
                    onClicked: Updates.reboot()
                }
                Button {
                    objectName: "tonightButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !Updates.restartScheduled && Security.dataEncryption !== "pin"
                    text: qsTr("Restart tonight")
                    onClicked: Updates.scheduleRestart()
                }
            }
            TextSwitch {
                objectName: "autoUpdateSwitch"
                visible: page.updateState !== "unsupported"
                text: qsTr("Automatic updates")
                description: qsTr("Downloads updates on Wi-Fi and installs them overnight while charging")
                automaticCheck: false
                checked: Updates.autoUpdate
                onClicked: Updates.autoUpdate = !checked
            }
            DetailItem {
                objectName: "osVersion"
                label: qsTr("Marathon OS")
                value: Updates.osVersion || "—"
            }
            DetailItem {
                objectName: "currentVersion"
                label: qsTr("Shell")
                value: Updates.currentVersion || "—"
            }
            DetailItem {
                objectName: "lastChecked"
                visible: Updates.lastCheckedMs > 0
                label: qsTr("Last checked")
                value: visible ? new Date(Updates.lastCheckedMs).toLocaleString(Qt.locale(), Locale.ShortFormat) : ""
            }
            SectionHeader {
                objectName: "currentNotesHeader"
                visible: Updates.currentReleaseNotes !== ""
                text: qsTr("What's new")
            }
            Label {
                objectName: "currentNotesLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: Updates.currentReleaseNotes !== ""
                text: Updates.currentReleaseNotes
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                visible: page.updateState !== "unsupported"
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Updates are signed and checked every 6 hours. They download only on Wi-Fi, with the battery at 30% or more or on charge.")
            }
        }

        VerticalScrollDecorator {}
    }
}
