import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Core
import "../components"

SettingsPageTemplate {
    id: wallpaperPage
    pageTitle: "Wallpaper"

    property string pageName: "wallpaper"

    content: Flickable {
        contentHeight: wallpaperContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: wallpaperContent
            width: parent.width
            spacing: MSpacing.lg
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg

            Text {
                text: "Choose a wallpaper for your home screen"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                width: parent.width - MSpacing.lg * 2
            }

            MSection {
                title: "Wallpapers"
                width: parent.width - MSpacing.lg * 2

                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: MSpacing.lg
                    rowSpacing: MSpacing.lg

                    Repeater {
                        model: WallpaperStore.wallpapers

                        Rectangle {
                            width: (parent.width - MSpacing.lg) / 2
                            height: width * 1.4
                            radius: Constants.borderRadiusMedium
                            color: WallpaperStore.currentWallpaper === modelData.path ? MColors.marathonTeal : MColors.surface
                            border.width: WallpaperStore.currentWallpaper === modelData.path ? Math.round(4 * Constants.scaleFactor) : Constants.borderWidthThin
                            border.color: WallpaperStore.currentWallpaper === modelData.path ? MColors.marathonTeal : MColors.border
                            clip: true

                            Behavior on border.width {
                                NumberAnimation {
                                    duration: Constants.animationDurationFast
                                }
                            }

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: Constants.animationDurationFast
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: Constants.animationDurationFast
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: WallpaperStore.currentWallpaper === modelData.path ? Math.round(4 * Constants.scaleFactor) : Constants.borderWidthThin
                                radius: Constants.borderRadiusMedium
                                clip: true

                                Behavior on anchors.margins {
                                    NumberAnimation {
                                        duration: Constants.animationDurationFast
                                    }
                                }

                                Image {
                                    anchors.fill: parent
                                    source: modelData.path
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: MColors.marathonTeal
                                    opacity: wallpaperMouseArea.pressed ? 0.2 : 0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Constants.animationDurationFast
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: WallpaperStore.currentWallpaper === modelData.path
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: MSpacing.md
                                width: Math.round(Constants.iconSizeLarge * 1.2)
                                height: Math.round(Constants.iconSizeLarge * 1.2)
                                radius: width / 2
                                color: MColors.textPrimary

                                Icon {
                                    anchors.centerIn: parent
                                    name: "check"
                                    size: Constants.iconSizeMedium
                                    color: MColors.marathonTeal
                                }

                                scale: WallpaperStore.currentWallpaper === modelData.path ? 1.0 : 0.0
                                opacity: WallpaperStore.currentWallpaper === modelData.path ? 1.0 : 0.0

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Constants.animationDurationNormal
                                        easing.type: Easing.OutBack
                                    }
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Constants.animationDurationFast
                                    }
                                }
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: MSpacing.sm
                                text: modelData.name
                                color: MColors.textPrimary
                                font.pixelSize: MTypography.sizeXSmall
                                font.family: MTypography.fontFamily
                                font.weight: WallpaperStore.currentWallpaper === modelData.path ? Font.Bold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -MSpacing.xs
                                    z: -1
                                    radius: Constants.borderRadiusSmall
                                    color: MColors.background
                                    opacity: 0.8
                                }
                            }

                            MouseArea {
                                id: wallpaperMouseArea
                                anchors.fill: parent
                                onClicked: {
                                    Logger.info("WallpaperPage", "Selected wallpaper: " + modelData.path);
                                    WallpaperStore.currentWallpaper = modelData.path;
                                    SettingsManagerCpp.wallpaperPath = modelData.path;
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
