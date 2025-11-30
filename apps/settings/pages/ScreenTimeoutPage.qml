import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import "../components"

SettingsPageTemplate {
    id: screenTimeoutPage
    pageTitle: "Screen Timeout"

    property string pageName: "screentimeout"

    content: Flickable {
        contentHeight: timeoutContent.height + MSpacing.xl * 3
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: timeoutContent
            width: parent.width
            spacing: MSpacing.lg
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg

            Text {
                text: "Choose how long before your screen turns off"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                width: parent.width - MSpacing.lg * 2
                wrapMode: Text.WordWrap
            }

            MSection {
                title: "Timeout Duration"
                width: parent.width - MSpacing.lg * 2

                Column {
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: SettingsManagerCpp.screenTimeoutOptions()

                        Rectangle {
                            width: parent.width
                            height: Constants.hubHeaderHeight
                            color: "transparent"

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Constants.borderRadiusSmall
                                color: timeoutMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.15) : (DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? Qt.rgba(20, 184, 166, 0.08) : "transparent")
                                border.width: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? Constants.borderWidthMedium : 0
                                border.color: MColors.marathonTeal

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Constants.animationDurationFast
                                    }
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: MSpacing.md
                                anchors.rightMargin: MSpacing.md
                                spacing: MSpacing.md

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Constants.iconSizeMedium
                                    height: Constants.iconSizeMedium
                                    radius: Constants.iconSizeMedium / 2
                                    color: "transparent"
                                    border.width: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? Math.round(6 * Constants.scaleFactor) : Constants.borderWidthMedium
                                    border.color: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? MColors.marathonTeal : MColors.border

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Constants.iconSizeSmall
                                        height: Constants.iconSizeSmall
                                        radius: Constants.iconSizeSmall / 2
                                        color: MColors.marathonTeal
                                        visible: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.family: MTypography.fontFamily
                                    font.weight: DisplayManager.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData) ? Font.DemiBold : Font.Normal
                                }
                            }

                            MouseArea {
                                id: timeoutMouseArea
                                anchors.fill: parent
                                onClicked: {
                                    var value = SettingsManagerCpp.screenTimeoutValue(modelData);
                                    DisplayManager.setScreenTimeout(value);
                                    Logger.info("ScreenTimeoutPage", "Screen timeout changed to: " + modelData);
                                }
                            }
                        }
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
