import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: storagePage

    property string pageName: "storage"

    pageTitle: "Storage"

    StorageInfo {
        id: storageInfo
    }

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
                            text: storageInfo.usedSpaceString + " used of " + storageInfo.totalSpaceString
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
                                width: parent.width * storageInfo.usedPercentage
                                height: parent.height
                                radius: parent.radius
                                color: {
                                    if (storageInfo.usedPercentage > 0.9)
                                        return Qt.rgba(255, 59, 48, 0.8);

                                    if (storageInfo.usedPercentage > 0.75)
                                        return Qt.rgba(255, 149, 0, 0.8);

                                    return Qt.rgba(20, 184, 166, 0.8);
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
                    value: storageInfo.usedSpaceString
                }

                MSettingsListItem {
                    title: "Available"
                    value: storageInfo.availableSpaceString
                }

                MSettingsListItem {
                    title: "Total Capacity"
                    value: storageInfo.totalSpaceString
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
