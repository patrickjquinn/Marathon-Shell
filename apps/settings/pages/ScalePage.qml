pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: scalePage

    property string pageName: "scale"
    property var scaleOptions: [
        {
            "factor": 0.75,
            "title": "75% - Compact",
            "description": "More content, smaller text"
        },
        {
            "factor": 0.9,
            "title": "90% - Small",
            "description": "Slightly smaller UI"
        },
        {
            "factor": 1,
            "title": "100% - Default",
            "description": "Recommended for most users"
        },
        {
            "factor": 1.1,
            "title": "110% - Comfortable",
            "description": "A bit larger for readability"
        },
        {
            "factor": 1.25,
            "title": "125% - Large",
            "description": "Larger text, easier to read"
        },
        {
            "factor": 1.4,
            "title": "140% - Extra Large",
            "description": "Maximum readability"
        },
        {
            "factor": 1.5,
            "title": "150% - Huge",
            "description": "Oversized UI elements"
        }
    ]

    pageTitle: "UI Scale"

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

                    Repeater {
                        model: scalePage.scaleOptions

                        Rectangle {
                            id: scaleOption

                            required property var modelData

                            width: parent.width
                            height: Constants.touchTargetMedium
                            radius: Constants.borderRadiusSmall
                            color: Constants.userScaleFactor === modelData.factor ? MColors.marathonTealGlowMid : "transparent"
                            border.width: Constants.userScaleFactor === modelData.factor ? 1 : 0
                            border.color: MColors.tealBorder
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.title
                            Accessible.description: modelData.description
                            Accessible.checked: Constants.userScaleFactor === modelData.factor
                            Accessible.onPressAction: SettingsManagerCpp.userScaleFactor = modelData.factor

                            Row {
                                anchors.fill: parent
                                anchors.margins: MSpacing.md
                                spacing: MSpacing.md

                                Rectangle {
                                    width: Math.round(28 * Constants.userScaleFactor)
                                    height: Math.round(28 * Constants.userScaleFactor)
                                    radius: Math.round(14 * Constants.userScaleFactor)
                                    color: Constants.userScaleFactor === scaleOption.modelData.factor ? MColors.marathonTeal : "transparent"
                                    border.width: Math.round(2 * Constants.userScaleFactor)
                                    border.color: Constants.userScaleFactor === scaleOption.modelData.factor ? MColors.marathonTeal : MColors.textSecondary
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        visible: Constants.userScaleFactor === scaleOption.modelData.factor
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
                                        text: scaleOption.modelData.title
                                        color: MColors.textPrimary
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: Font.DemiBold
                                        font.family: MTypography.fontFamily
                                    }

                                    Text {
                                        text: scaleOption.modelData.description
                                        color: MColors.textSecondary
                                        font.pixelSize: MTypography.sizeSmall
                                        font.family: MTypography.fontFamily
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                // Write only to SettingsManagerCpp — the
                                // Constants.userScaleFactor Binding listens
                                // for changes and propagates back.
                                onClicked: SettingsManagerCpp.userScaleFactor = scaleOption.modelData.factor
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
