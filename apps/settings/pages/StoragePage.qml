import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import "../components"

SettingsPageTemplate {
    id: storagePage
    pageTitle: "Storage"

    property string pageName: "storage"

    content: Flickable {
        contentHeight: storageContent.height + 40
        clip: true

        Column {
            id: storageContent
            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Storage Overview"
                width: parent.width - 48

                Rectangle {
                    width: parent.width
                    height: Constants.bottomBarHeight
                    radius: 4
                    color: Qt.rgba(255, 255, 255, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(255, 255, 255, 0.08)

                    Column {
                        anchors.centerIn: parent
                        spacing: MSpacing.sm

                        Text {
                            text: StorageManager.usedSpaceString + " used of " + StorageManager.totalSpaceString
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: Font.Bold
                            font.family: MTypography.fontFamily
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Rectangle {
                            width: 200
                            height: 8
                            radius: 4
                            color: Qt.rgba(255, 255, 255, 0.1)
                            anchors.horizontalCenter: parent.horizontalCenter

                            Rectangle {
                                width: parent.width * StorageManager.usedPercentage
                                height: parent.height
                                radius: parent.radius
                                color: {
                                    if (StorageManager.usedPercentage > 0.9)
                                        return Qt.rgba(255, 59, 48, 0.8);      // Red when >90%
                                    if (StorageManager.usedPercentage > 0.75)
                                        return Qt.rgba(255, 149, 0, 0.8);    // Orange when >75%
                                    return Qt.rgba(20, 184, 166, 0.8);  // Teal when <75%
                                }
                            }
                        }
                    }
                }
            }

            MSection {
                title: "Storage Details"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Used"
                    value: StorageManager.usedSpaceString
                }

                MSettingsListItem {
                    title: "Available"
                    value: StorageManager.availableSpaceString
                }

                MSettingsListItem {
                    title: "Total Capacity"
                    value: StorageManager.totalSpaceString
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
