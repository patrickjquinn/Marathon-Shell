import QtQuick
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import "../components"

SettingsPageTemplate {
    id: aboutPage
    pageTitle: "About Device"

    property string pageName: "about"

    content: Flickable {
        contentHeight: aboutContent.height + 40
        clip: true

        Column {
            id: aboutContent
            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Device Information"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Device Name"
                    value: SettingsManagerCpp.deviceName
                    showChevron: true
                }

                MSettingsListItem {
                    title: "Model"
                    value: "Marathon Passport"
                }

                MSettingsListItem {
                    title: "OS Version"
                    value: "Marathon OS 1.0.0"
                }

                MSettingsListItem {
                    title: "Build"
                    value: "Alpha"
                }

                MSettingsListItem {
                    title: "Kernel Version"
                    value: Platform.os === "linux" ? "Linux 6.x" : "Darwin"
                }
            }

            MSection {
                title: "Hardware"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Storage"
                    value: "64 GB"
                }

                MSettingsListItem {
                    title: "Display"
                    value: DisplayManager.width + "x" + DisplayManager.height
                }

                MSettingsListItem {
                    title: "Battery"
                    value: SystemStatusStore.batteryLevel + "%"
                }
            }

            MSection {
                title: "Legal"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Open Source Licenses"
                    showChevron: true
                }

                MSettingsListItem {
                    title: "Terms of Service"
                    showChevron: true
                }

                MSettingsListItem {
                    title: "Privacy Policy"
                    showChevron: true
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
