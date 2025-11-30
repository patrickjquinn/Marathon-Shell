import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import "../components"

SettingsPageTemplate {
    id: scalePage
    pageTitle: "UI Scale"

    property string pageName: "scale"

    content: Flickable {
        contentHeight: scaleContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: scaleContent
            width: parent.width
            spacing: MSpacing.xl
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg

            Text {
                text: "Adjust the size of text and UI elements. Changes take effect immediately."
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                wrapMode: Text.WordWrap
                width: parent.width - MSpacing.lg * 2
            }

            MSection {
                title: "Scale Options"
                width: parent.width - MSpacing.lg * 2

                Column {
                    width: parent.width
                    spacing: MSpacing.sm

                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: Constants.userScaleFactor === 0.75 ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                        border.width: Constants.userScaleFactor === 0.75 ? 1 : 0
                        border.color: Qt.rgba(20, 184, 166, 0.3)

                        Row {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            spacing: MSpacing.md

                            Rectangle {
                                width: Math.round(28 * Constants.userScaleFactor)
                                height: Math.round(28 * Constants.userScaleFactor)
                                radius: Math.round(14 * Constants.userScaleFactor)
                                color: Constants.userScaleFactor === 0.75 ? MColors.marathonTeal : "transparent"
                                border.width: Math.round(2 * Constants.userScaleFactor)
                                border.color: Constants.userScaleFactor === 0.75 ? MColors.marathonTeal : MColors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    visible: Constants.userScaleFactor === 0.75
                                    width: Math.round(12 * Constants.userScaleFactor)
                                    height: Math.round(12 * Constants.userScaleFactor)
                                    radius: Math.round(6 * Constants.userScaleFactor)
                                    color: MColors.background
                                    anchors.centerIn: parent
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    text: "75% - Compact"
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: MTypography.fontFamily
                                }

                                Text {
                                    text: "More content, smaller text"
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeSmall
                                    font.family: MTypography.fontFamily
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Constants.userScaleFactor = 0.75;
                                SettingsManagerCpp.userScaleFactor = 0.75;
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: Constants.userScaleFactor === 1.0 ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                        border.width: Constants.userScaleFactor === 1.0 ? 1 : 0
                        border.color: Qt.rgba(20, 184, 166, 0.3)

                        Row {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            spacing: MSpacing.md

                            Rectangle {
                                width: Math.round(28 * Constants.userScaleFactor)
                                height: Math.round(28 * Constants.userScaleFactor)
                                radius: Math.round(14 * Constants.userScaleFactor)
                                color: Constants.userScaleFactor === 1.0 ? MColors.marathonTeal : "transparent"
                                border.width: Math.round(2 * Constants.userScaleFactor)
                                border.color: Constants.userScaleFactor === 1.0 ? MColors.marathonTeal : MColors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    visible: Constants.userScaleFactor === 1.0
                                    width: Math.round(12 * Constants.userScaleFactor)
                                    height: Math.round(12 * Constants.userScaleFactor)
                                    radius: Math.round(6 * Constants.userScaleFactor)
                                    color: MColors.background
                                    anchors.centerIn: parent
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    text: "100% - Default"
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: MTypography.fontFamily
                                }

                                Text {
                                    text: "Recommended for most users"
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeSmall
                                    font.family: MTypography.fontFamily
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Constants.userScaleFactor = 1.0;
                                SettingsManagerCpp.userScaleFactor = 1.0;
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: Constants.userScaleFactor === 1.25 ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                        border.width: Constants.userScaleFactor === 1.25 ? 1 : 0
                        border.color: Qt.rgba(20, 184, 166, 0.3)

                        Row {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            spacing: MSpacing.md

                            Rectangle {
                                width: Math.round(28 * Constants.userScaleFactor)
                                height: Math.round(28 * Constants.userScaleFactor)
                                radius: Math.round(14 * Constants.userScaleFactor)
                                color: Constants.userScaleFactor === 1.25 ? MColors.marathonTeal : "transparent"
                                border.width: Math.round(2 * Constants.userScaleFactor)
                                border.color: Constants.userScaleFactor === 1.25 ? MColors.marathonTeal : MColors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    visible: Constants.userScaleFactor === 1.25
                                    width: Math.round(12 * Constants.userScaleFactor)
                                    height: Math.round(12 * Constants.userScaleFactor)
                                    radius: Math.round(6 * Constants.userScaleFactor)
                                    color: MColors.background
                                    anchors.centerIn: parent
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    text: "125% - Comfortable"
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: MTypography.fontFamily
                                }

                                Text {
                                    text: "Larger text, easier to read"
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeSmall
                                    font.family: MTypography.fontFamily
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Constants.userScaleFactor = 1.25;
                                SettingsManagerCpp.userScaleFactor = 1.25;
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Constants.touchTargetMedium
                        radius: Constants.borderRadiusSmall
                        color: Constants.userScaleFactor === 1.5 ? Qt.rgba(20, 184, 166, 0.08) : "transparent"
                        border.width: Constants.userScaleFactor === 1.5 ? 1 : 0
                        border.color: Qt.rgba(20, 184, 166, 0.3)

                        Row {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            spacing: MSpacing.md

                            Rectangle {
                                width: Math.round(28 * Constants.userScaleFactor)
                                height: Math.round(28 * Constants.userScaleFactor)
                                radius: Math.round(14 * Constants.userScaleFactor)
                                color: Constants.userScaleFactor === 1.5 ? MColors.marathonTeal : "transparent"
                                border.width: Math.round(2 * Constants.userScaleFactor)
                                border.color: Constants.userScaleFactor === 1.5 ? MColors.marathonTeal : MColors.textSecondary
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    visible: Constants.userScaleFactor === 1.5
                                    width: Math.round(12 * Constants.userScaleFactor)
                                    height: Math.round(12 * Constants.userScaleFactor)
                                    radius: Math.round(6 * Constants.userScaleFactor)
                                    color: MColors.background
                                    anchors.centerIn: parent
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    text: "150% - Large"
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: Font.DemiBold
                                    font.family: MTypography.fontFamily
                                }

                                Text {
                                    text: "Maximum readability"
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeSmall
                                    font.family: MTypography.fontFamily
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Constants.userScaleFactor = 1.5;
                                SettingsManagerCpp.userScaleFactor = 1.5;
                            }
                        }
                    }
                }
            }

            Text {
                text: "Current: " + Math.round(Constants.scaleFactor * 100) + "% (Base: " + Math.round((Constants.screenHeight / Constants.baseHeight) * 100) + "% × User: " + Math.round(Constants.userScaleFactor * 100) + "%)"
                color: MColors.textTertiary
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                width: parent.width - MSpacing.lg * 2
                wrapMode: Text.WordWrap
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
