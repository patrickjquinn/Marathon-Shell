pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: aboutPage

    property string pageName: "about"

    pageTitle: "About Device"
    overlayOpen: renameModal.showing
    onCloseOverlayRequested: renameModal.showing = false
    signal openSourceLicensesRequested

    MModal {
        id: renameModal

        title: "Device name"
        onClosed: renameModal.showing = false

        content: Column {
            width: parent.width
            spacing: MSpacing.md

            MTextField {
                id: deviceNameField

                width: parent.width
                label: "Name for this device"
                errorText: text.trim().length === 0 ? "Enter a name" : ""
            }

            Row {
                anchors.right: parent.right
                spacing: MSpacing.sm

                MButton {
                    text: "Cancel"
                    onClicked: renameModal.showing = false
                }

                MButton {
                    text: "Save"
                    variant: "primary"
                    disabled: deviceNameField.text.trim().length === 0
                    onClicked: {
                        SettingsManagerCpp.deviceName = deviceNameField.text.trim();
                        renameModal.showing = false;
                    }
                }
            }
        }
    }

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
                    onSettingClicked: {
                        deviceNameField.text = SettingsManagerCpp.deviceName;
                        renameModal.showing = true;
                    }
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
