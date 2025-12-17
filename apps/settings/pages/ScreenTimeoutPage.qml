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
                            width: parent.width
                            height: Constants.hubHeaderHeight
                            color: "transparent"

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Constants.borderRadiusSmall
                                color: timeoutMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.15) : ((typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp && DisplayPolicyControllerCpp.screenTimeoutMs === SettingsManagerCpp.screenTimeoutValue(modelData)) ? Qt.rgba(20, 184, 166, 0.08) : "transparent")
                                border.width: (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp && DisplayPolicyControllerCpp.screenTimeoutMs === SettingsManagerCpp.screenTimeoutValue(modelData)) ? Constants.borderWidthMedium : 0
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
                                    border.width: (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp && DisplayPolicyControllerCpp.screenTimeoutMs === SettingsManagerCpp.screenTimeoutValue(modelData)) ? Math.round(6 * Constants.scaleFactor) : Constants.borderWidthMedium
                                    border.color: (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp && DisplayPolicyControllerCpp.screenTimeoutMs === SettingsManagerCpp.screenTimeoutValue(modelData)) ? MColors.marathonTeal : MColors.border

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Constants.iconSizeSmall
                                        height: Constants.iconSizeSmall
                                        radius: Constants.iconSizeSmall / 2
                                        color: MColors.marathonTeal
                                        visible: typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp && DisplayPolicyControllerCpp.screenTimeoutMs === SettingsManagerCpp.screenTimeoutValue(modelData)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData
                                    color: MColors.textPrimary
                                    font.pixelSize: MTypography.sizeBody
                                    font.family: MTypography.fontFamily
                                    font.weight: (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp && DisplayPolicyControllerCpp.screenTimeoutMs === SettingsManagerCpp.screenTimeoutValue(modelData)) ? Font.DemiBold : Font.Normal
                                }
                            }

                            MouseArea {
                                id: timeoutMouseArea

                                anchors.fill: parent
                                onClicked: {
                                    var value = SettingsManagerCpp.screenTimeoutValue(modelData);
                                    if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                                        DisplayPolicyControllerCpp.screenTimeoutMs = value;

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
