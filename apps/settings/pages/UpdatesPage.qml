pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: updatesPage

    property string pageName: "updates"

    pageTitle: "Software updates"

    content: Flickable {
        contentHeight: updatesContent.height + 40
        clip: true

        Column {
            id: updatesContent

            width: parent.width
            spacing: MSpacing.lg
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg

            MSection {
                title: "Status"
                width: parent.width - MSpacing.lg * 2

                MSettingsListItem {
                    title: "Current version"
                    value: UpdateService.currentVersion || "—"
                    Accessible.name: "Current version " + (UpdateService.currentVersion || "unknown")
                }

                MSettingsListItem {
                    title: UpdateService.updateAvailable ? "Update available" : "Up to date"
                    value: UpdateService.latestVersion || "—"
                    showChevron: UpdateService.updateAvailable
                    onSettingClicked: {
                        if (UpdateService.updateAvailable)
                            UpdateService.openInBrowser();
                    }
                    Accessible.name: UpdateService.updateAvailable ? ("Update " + UpdateService.latestVersion + " available, tap to view release") : "Up to date"
                }

                MSettingsListItem {
                    title: "Last error"
                    value: UpdateService.lastError || "—"
                    visible: UpdateService.lastError && UpdateService.lastError.length > 0
                }
            }

            MSection {
                title: "Channel"
                width: parent.width - MSpacing.lg * 2

                MSettingsListItem {
                    title: "Stable"
                    subtitle: "Tagged releases only"
                    value: UpdateService.channel === "stable" ? "selected" : ""
                    onSettingClicked: UpdateService.setChannel("stable")
                    Accessible.name: "Stable channel" + (UpdateService.channel === "stable" ? ", selected" : "")
                }

                MSettingsListItem {
                    title: "Edge"
                    subtitle: "Includes pre-releases"
                    value: UpdateService.channel === "edge" ? "selected" : ""
                    onSettingClicked: UpdateService.setChannel("edge")
                    Accessible.name: "Edge channel" + (UpdateService.channel === "edge" ? ", selected" : "")
                }
            }

            Row {
                spacing: MSpacing.md
                anchors.horizontalCenter: parent.horizontalCenter

                MButton {
                    text: UpdateService.checking ? "Checking…" : "Check now"
                    variant: "primary"
                    disabled: UpdateService.checking
                    onClicked: UpdateService.checkNow()
                    Accessible.name: "Check for updates"
                }

                MButton {
                    text: "View release"
                    variant: "default"
                    disabled: !UpdateService.releaseUrl || UpdateService.releaseUrl.length === 0
                    onClicked: UpdateService.openInBrowser()
                    Accessible.name: "View release notes in browser"
                }
            }

            MLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                variant: "secondary"
                text: "Updates are pulled from the GitHub Releases feed. The shell polls every 6 hours; tap “Check now” to refresh immediately."
            }
        }
    }
}
