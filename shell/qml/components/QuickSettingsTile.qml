import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Item {
    id: tile

    property var toggleData: ({})
    property real tileWidth: 160
    property bool isAvailable: toggleData.available !== undefined ? toggleData.available : true

    // Determine if this is a toggleable tile (has on/off state) vs a link tile
    readonly property bool isToggleable: toggleData.id !== "settings" && toggleData.id !== "lock" && toggleData.id !== "power" &&  // Power is an action menu
    toggleData.id !== "monitor" && toggleData.id !== "alarm" &&  // Alarm is a link to Clock app
    toggleData.id !== "screenshot"  // Screenshot is an action

    signal tapped
    signal longPressed

    width: tileWidth
    height: Constants.hubHeaderHeight

    property bool isPressed: false

    // TOGGLEABLE TILE: Split design - ALWAYS visible (structure consistent across states)
    Rectangle {
        id: toggleableTile
        visible: isToggleable
        anchors.fill: parent
        color: "transparent"
        scale: isPressed ? 0.98 : 1.0
        opacity: isAvailable ? 1.0 : 0.5

        Behavior on scale {
            enabled: Constants.enableAnimations
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }

        Row {
            anchors.fill: parent
            spacing: 0

            // LEFT: Square icon box - ALWAYS VISIBLE
            Rectangle {
                id: iconBox
                width: Constants.hubHeaderHeight
                height: Constants.hubHeaderHeight
                radius: Constants.borderRadiusSharp
                // OFF state: elevated surface. ON state: bright teal
                color: toggleData.active ? MColors.accentBright : MColors.bb10Elevated
                antialiasing: Constants.enableAntialiasing

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Icon {
                    // For toggleable items with -off variants, show the -off icon when inactive
                    name: {
                        var iconName = toggleData.icon || "grid";
                        if (!toggleData.active && (toggleData.id === "vibration" || toggleData.id === "wifi" || toggleData.id === "bluetooth")) {
                            iconName = iconName + "-off";
                        }
                        return iconName;
                    }
                    // OFF: standard text color. ON: dark (readable on teal). Unavailable: dim
                    color: !isAvailable ? MColors.textSecondary : (toggleData.active ? MColors.background : MColors.text)
                    size: Constants.iconSizeMedium
                    anchors.centerIn: parent

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }
            }

            // RIGHT: Label box - ALWAYS VISIBLE
            Rectangle {
                width: parent.width - Constants.hubHeaderHeight
                height: Constants.hubHeaderHeight
                radius: Constants.borderRadiusSharp
                // OFF: standard surface. ON: slightly elevated for cohesion
                color: isAvailable ? MColors.surface : Qt.rgba(MColors.surface.r, MColors.surface.g, MColors.surface.b, 0.5)
                border.width: Constants.borderWidthThin
                // OFF: subtle border. ON: teal border for cohesion
                border.color: toggleData.active ? MColors.accentBright : MColors.border
                antialiasing: Constants.enableAntialiasing

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                // Inner border for depth
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: Constants.borderRadiusSharp
                    color: "transparent"
                    border.width: Constants.borderWidthThin
                    border.color: MColors.borderSubtle
                    antialiasing: Constants.enableAntialiasing
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: MSpacing.md
                    anchors.leftMargin: MSpacing.md

                    Column {
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: MSpacing.xs

                        MLabel {
                            text: toggleData.label || ""
                            variant: "body"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        MLabel {
                            visible: toggleData.subtitle !== undefined && toggleData.subtitle !== ""
                            text: toggleData.subtitle || ""
                            font.pixelSize: MTypography.sizeXSmall
                            elide: Text.ElideRight
                            width: parent.width
                            color: MColors.text
                            opacity: 0.6
                        }
                    }
                }

                // Teal bar active indicator (bottom of label box) - ONLY when ON
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 1
                    height: 3
                    radius: Constants.borderRadiusSharp
                    color: MColors.accentBright
                    visible: toggleData.active
                    antialiasing: Constants.enableAntialiasing
                    opacity: toggleData.active ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
            }
        }

        // Press overlay
        Rectangle {
            anchors.fill: parent
            color: toggleData.active ? MColors.background : MColors.accentBright
            opacity: isPressed ? 0.1 : 0
            radius: Constants.borderRadiusSharp

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // ACTION/LINK TILE: Solid card design (Settings, Lock, Monitor, Alarm)
    Rectangle {
        id: linkTile
        visible: !isToggleable
        anchors.fill: parent
        radius: Constants.borderRadiusSharp
        border.width: Constants.borderWidthThin
        border.color: MColors.border
        // Action tiles use elevated surface for visual distinction from toggles
        color: isAvailable ? MColors.bb10Card : Qt.rgba(MColors.bb10Card.r, MColors.bb10Card.g, MColors.bb10Card.b, 0.5)
        antialiasing: Constants.enableAntialiasing
        scale: isPressed ? 0.98 : 1.0
        opacity: isAvailable ? 1.0 : 0.5

        Behavior on scale {
            enabled: Constants.enableAnimations
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }

        // Inner border for depth
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Constants.borderRadiusSharp
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MColors.borderSubtle
            antialiasing: Constants.enableAntialiasing
        }

        Item {
            anchors.fill: parent
            anchors.margins: MSpacing.md

            Row {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: MSpacing.md

                // Icon container - slightly different sizing for action tiles
                Rectangle {
                    width: Constants.iconSizeMedium + MSpacing.md
                    height: Constants.iconSizeMedium + MSpacing.md
                    radius: Constants.borderRadiusSharp
                    color: MColors.bb10Elevated
                    antialiasing: Constants.enableAntialiasing

                    Icon {
                        name: toggleData.icon || "grid"
                        color: isAvailable ? MColors.text : MColors.textSecondary
                        size: Constants.iconSizeMedium
                        anchors.centerIn: parent
                    }
                }

                Column {
                    spacing: MSpacing.xs
                    width: parent.width - (Constants.iconSizeMedium + MSpacing.md * 2)
                    anchors.verticalCenter: parent.verticalCenter

                    MLabel {
                        text: toggleData.label || ""
                        variant: "body"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    MLabel {
                        visible: toggleData.subtitle !== undefined && toggleData.subtitle !== ""
                        text: toggleData.subtitle || ""
                        font.pixelSize: MTypography.sizeXSmall
                        elide: Text.ElideRight
                        width: parent.width
                        color: MColors.text
                        opacity: 0.6
                    }
                }
            }
        }

        // Press overlay
        Rectangle {
            anchors.fill: parent
            color: MColors.text
            opacity: isPressed ? 0.08 : 0
            radius: Constants.borderRadiusSharp

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        id: toggleMouseArea
        anchors.fill: parent
        enabled: isAvailable

        onPressed: function (mouse) {
            isPressed = true;
            HapticService.light();
        }

        onReleased: {
            isPressed = false;
        }

        onCanceled: {
            isPressed = false;
        }

        onClicked: {
            if (!isAvailable) {
                Logger.warn("QuickSettings", "Attempted to toggle unavailable feature: " + toggleData.id);
                return;
            }
            tile.tapped();
        }

        onPressAndHold: {
            if (!isAvailable)
                return;
            HapticService.medium();
            tile.longPressed();
        }
    }
}
