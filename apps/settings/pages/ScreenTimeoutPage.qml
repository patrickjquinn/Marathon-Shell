pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: screenTimeoutPage

    property string pageName: "screentimeout"

    pageTitle: "Screen Timeout"

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
                            id: timeoutOption

                            required property var modelData

                            width: parent.width
                            height: Constants.hubHeaderHeight
                            color: "transparent"
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData
                            Accessible.checked: DisplayManagerCpp.screenTimeout === SettingsManagerCpp.screenTimeoutValue(modelData)
                            Accessible.onPressAction: DisplayManagerCpp.screenTimeout = SettingsManagerCpp.screenTimeoutValue(modelData)

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Constants.borderRadiusSmall
                                color: timeoutMouseArea.pressed ? MColors.ripple : ((DisplayManagerCpp.screenTimeout === SettingsManagerCpp.screenTimeoutValue(timeoutOption.modelData)) ? MColors.marathonTealGlowMid : "transparent")
                                border.width: (DisplayManagerCpp.screenTimeout === SettingsManagerCpp.screenTimeoutValue(timeoutOption.modelData)) ? Constants.borderWidthMedium : 0
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
                                    border.width: (DisplayManagerCpp.screenTimeout === SettingsManagerCpp.screenTimeoutValue(timeoutOption.modelData)) ? Math.round(6 * Constants.scaleFactor) : Constants.borderWidthMedium
                                    border.color: (DisplayManagerCpp.screenTimeout === SettingsManagerCpp.screenTimeoutValue(timeoutOption.modelData)) ? MColors.marathonTeal : MColors.border

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Constants.iconSizeSmall
                                        height: Constants.iconSizeSmall
                                        radius: Constants.iconSizeSmall / 2
                                        color: MColors.marathonTeal
                                        visible: DisplayManagerCpp.screenTimeout === SettingsManagerCpp.screenTimeoutValue(timeoutOption.modelData)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: timeoutOption.modelData
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.family: MTypography.fontFamily
                                    font.weight: (DisplayManagerCpp.screenTimeout === SettingsManagerCpp.screenTimeoutValue(timeoutOption.modelData)) ? Font.DemiBold : Font.Normal
                                }
                            }

                            MouseArea {
                                id: timeoutMouseArea

                                anchors.fill: parent
                                onClicked: {
                                    var value = SettingsManagerCpp.screenTimeoutValue(timeoutOption.modelData);
                                    DisplayManagerCpp.screenTimeout = value;

                                    Logger.info("ScreenTimeoutPage", "Screen timeout changed to: " + timeoutOption.modelData);
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
