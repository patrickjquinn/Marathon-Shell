pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: aboutPage

    property string pageName: "about"

    pageTitle: "About Device"
    signal openSourceLicensesRequested

    StorageInfo {
        id: storageInfo
    }

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
                    value: SettingsController.deviceModel
                }

                MSettingsListItem {
                    title: "OS Version"
                    value: SettingsController.osVersion
                }

                MSettingsListItem {
                    title: "Build"
                    value: SettingsController.buildType
                }

                MSettingsListItem {
                    title: "Kernel Version"
                    value: SettingsController.kernelVersion
                }
            }

            MSection {
                title: "Hardware"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Storage"
                    value: storageInfo.totalSpaceString
                }

                MSettingsListItem {
                    title: "Display"
                    value: SettingsController.displayResolution
                }

                MSettingsListItem {
                    title: "Refresh Rate"
                    value: SettingsController.displayRefreshRate
                }

                MSettingsListItem {
                    title: "DPI"
                    value: SettingsController.displayDpi
                }

                MSettingsListItem {
                    title: "Scale"
                    value: SettingsController.displayScale
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
                    onSettingClicked: aboutPage.openSourceLicensesRequested()
                }

                MSettingsListItem {
                    title: "Terms of Service"
                    showChevron: true
                    onSettingClicked: SettingsController.requestPage("tos")
                }

                MSettingsListItem {
                    title: "Privacy Policy"
                    showChevron: true
                    onSettingClicked: SettingsController.requestPage("privacy")
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
