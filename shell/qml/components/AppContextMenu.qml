import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core

Item {
    id: contextMenu
    anchors.fill: parent
    visible: false
    z: 2550

    property var appData: null
    property point position: Qt.point(0, 0)

    signal appInfo
    signal uninstall
    signal move

    function show(app, pos) {
        appData = app;
        position = pos;

        menu.x = Math.min(Math.max(pos.x - menu.width / 2, 16), parent.width - menu.width - 16);
        menu.y = Math.max(pos.y - menu.height - 10, Constants.statusBarHeight + 16);

        visible = true;
        fadeIn.start();
    }

    function hide() {
        fadeOut.start();
    }

    MouseArea {
        anchors.fill: parent
        onClicked: hide()
    }

    Rectangle {
        id: menu
        width: Math.round(180 * Constants.scaleFactor)
        height: menuColumn.height + Constants.spacingMedium
        radius: Constants.borderRadiusSmall
        color: Qt.rgba(15, 15, 15, 0.98)
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.15)
        layer.enabled: true
        opacity: 0
        scale: 0.9

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.05)
        }

        Column {
            id: menuColumn
            anchors.centerIn: parent
            width: parent.width - Constants.spacingMedium
            spacing: 0

            Rectangle {
                width: parent.width
                height: Constants.inputHeight
                radius: Constants.borderRadiusSmall
                color: infoMouseArea.pressed ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.rightMargin: Constants.spacingMedium
                    spacing: Constants.spacingMedium

                    Icon {
                        name: "info"
                        size: Constants.iconSizeSmall
                        color: MColors.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "App Info"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: infoMouseArea
                    anchors.fill: parent
                    onClicked: {
                        Logger.info("AppContextMenu", "App info for: " + appData.name);
                        HapticService.light();
                        appInfo();
                        hide();
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Constants.dividerHeight
                color: Qt.rgba(255, 255, 255, 0.05)
            }

            Rectangle {
                width: parent.width
                height: Constants.inputHeight
                radius: Constants.borderRadiusSmall
                color: uninstallMouseArea.pressed ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.rightMargin: Constants.spacingMedium
                    spacing: Constants.spacingMedium

                    Icon {
                        name: "trash-2"
                        size: Constants.iconSizeSmall
                        color: "#E63946"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Uninstall"
                        color: "#E63946"
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: uninstallMouseArea
                    anchors.fill: parent
                    onClicked: {
                        Logger.info("AppContextMenu", "Uninstall: " + appData.name);
                        HapticService.medium();
                        uninstall();
                        hide();
                        UIStore.showConfirmDialog("Uninstall " + appData.name + "?", "This app will be removed from your device.", function () {
                            Logger.info("AppContextMenu", "Confirmed uninstall");
                        });
                    }
                }
            }
        }
    }

    ParallelAnimation {
        id: fadeIn
        NumberAnimation {
            target: menu
            property: "opacity"
            to: 1
            duration: 150
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: menu
            property: "scale"
            to: 1
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: fadeOut
        NumberAnimation {
            target: menu
            property: "opacity"
            to: 0
            duration: 100
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: menu
            property: "scale"
            to: 0.9
            duration: 100
            easing.type: Easing.InCubic
        }
        onFinished: {
            contextMenu.visible = false;
        }
    }
}
