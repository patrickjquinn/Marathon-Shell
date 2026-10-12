import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Effects
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: tile

    property var toggleData: ({})
    property real tileWidth: 160
    property bool isAvailable: toggleData.available !== undefined ? toggleData.available : true
    readonly property bool isToggleable: toggleData.id !== "settings" && toggleData.id !== "lock" && toggleData.id !== "power" && toggleData.id !== "monitor" && toggleData.id !== "alarm" && toggleData.id !== "screenshot"
    property bool isPressed: false

    signal tapped
    signal longPressed

    width: tileWidth
    height: Constants.hubHeaderHeight

    Rectangle {
        id: toggleableTile

        visible: tile.isToggleable
        anchors.fill: parent
        color: "transparent"
        scale: tile.isPressed ? 0.98 : 1
        opacity: tile.isAvailable ? 1 : 0.5

        Row {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: iconBox

                width: Constants.hubHeaderHeight
                height: Constants.hubHeaderHeight
                // Sailfish Top Menu switch: a round icon, filled with the
                // ambience highlight when on.
                radius: width / 2
                color: tile.toggleData.active ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
                antialiasing: Constants.enableAntialiasing

                Icon {
                    name: {
                        var iconName = tile.toggleData.icon || "grid";
                        if (!tile.toggleData.active && (tile.toggleData.id === "wifi" || tile.toggleData.id === "bluetooth"))
                            iconName = iconName + "-off";

                        return iconName;
                    }
                    color: tile.toggleData.active ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    size: Constants.iconSizeMedium
                    anchors.centerIn: parent

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Rectangle {
                width: parent.width - Constants.hubHeaderHeight
                height: Constants.hubHeaderHeight
                radius: Constants.borderRadiusSharp
                color: "transparent"
                antialiasing: Constants.enableAntialiasing

                // DS edge spec: "lit from above" hairline that follows
                // the squircle path (not a flat horizontal bar past the
                // corner radius).

                Item {
                    anchors.fill: parent
                    anchors.margins: MSpacing.md
                    anchors.leftMargin: MSpacing.md

                    Column {
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: MSpacing.xs

                        Silica.Label {
                            text: tile.toggleData.label || ""
                            font.pixelSize: Silica.Theme.fontSizeSmall
                            color: tile.toggleData.active ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                            truncationMode: Silica.TruncationMode.Fade
                            width: parent.width
                        }

                        Silica.Label {
                            visible: tile.toggleData.subtitle !== undefined && tile.toggleData.subtitle !== ""
                            text: tile.toggleData.subtitle || ""
                            font.pixelSize: Silica.Theme.fontSizeExtraSmall
                            truncationMode: Silica.TruncationMode.Fade
                            width: parent.width
                            color: Silica.Theme.secondaryColor
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: tile.toggleData.active ? MColors.background : MColors.accentBright
            opacity: tile.isPressed ? 0.1 : 0
            radius: Constants.borderRadiusSharp

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }

        Behavior on scale {
            enabled: Constants.enableAnimations

            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }
    }

    Rectangle {
        id: linkTile

        visible: !tile.isToggleable
        anchors.fill: parent
        color: "transparent"
        antialiasing: Constants.enableAntialiasing
        scale: tile.isPressed ? 0.98 : 1
        opacity: tile.isAvailable ? 1 : 0.5


        Item {
            anchors.fill: parent
            anchors.margins: MSpacing.md

            Row {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: MSpacing.md

                Rectangle {
                    width: Constants.iconSizeMedium + MSpacing.md
                    height: Constants.iconSizeMedium + MSpacing.md
                    radius: width / 2
                    color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
                    antialiasing: Constants.enableAntialiasing

                    Icon {
                        name: tile.toggleData.icon || "grid"
                        color: tile.isAvailable ? MColors.text : MColors.textSecondary
                        size: Constants.iconSizeMedium
                        anchors.centerIn: parent
                    }
                }

                Column {
                    spacing: MSpacing.xs
                    width: parent.width - (Constants.iconSizeMedium + MSpacing.md * 2)
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        text: tile.toggleData.label || ""
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Silica.Label {
                        visible: tile.toggleData.subtitle !== undefined && tile.toggleData.subtitle !== ""
                        text: tile.toggleData.subtitle || ""
                        font.pixelSize: MTypography.sizeXSmall
                        elide: Text.ElideRight
                        width: parent.width
                        color: MColors.text
                        opacity: 0.6
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: MColors.text
            opacity: tile.isPressed ? 0.08 : 0
            radius: Constants.borderRadiusSharp

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }

        Behavior on scale {
            enabled: Constants.enableAnimations

            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }
    }

    MouseArea {
        id: toggleMouseArea

        anchors.fill: parent
        enabled: tile.isAvailable
        onPressed: function (mouse) {
            tile.isPressed = true;
            HapticManager.light();
        }
        onReleased: {
            tile.isPressed = false;
        }
        onCanceled: {
            tile.isPressed = false;
        }
        onClicked: {
            if (!tile.isAvailable) {
                Logger.warn("QuickSettings", "Attempted to toggle unavailable feature: " + tile.toggleData.id);
                return;
            }
            tile.tapped();
        }
        onPressAndHold: {
            if (!tile.isAvailable)
                return;

            HapticManager.medium();
            tile.longPressed();
        }
    }
}
