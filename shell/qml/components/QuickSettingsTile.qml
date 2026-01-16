import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

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

        visible: isToggleable
        anchors.fill: parent
        color: "transparent"
        scale: isPressed ? 0.98 : 1
        opacity: isAvailable ? 1 : 0.5

        Row {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: iconBox

                width: Constants.hubHeaderHeight
                height: Constants.hubHeaderHeight
                radius: Constants.borderRadiusSharp
                color: toggleData.active ? MColors.accentBright : MColors.bb10Elevated
                antialiasing: Constants.enableAntialiasing

                Icon {
                    name: {
                        var iconName = toggleData.icon || "grid";
                        if (!toggleData.active && (toggleData.id === "wifi" || toggleData.id === "bluetooth"))
                            iconName = iconName + "-off";

                        return iconName;
                    }
                    color: toggleData.active ? MColors.background : MColors.text
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
                color: isAvailable ? MColors.surface : Qt.rgba(MColors.surface.r, MColors.surface.g, MColors.surface.b, 0.5)
                border.width: Constants.borderWidthThin
                border.color: toggleData.active ? MColors.accentBright : MColors.border
                antialiasing: Constants.enableAntialiasing

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
                    opacity: toggleData.active ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

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

        visible: !isToggleable
        anchors.fill: parent
        radius: Constants.borderRadiusSharp
        border.width: Constants.borderWidthThin
        border.color: MColors.border
        color: isAvailable ? MColors.bb10Card : Qt.rgba(MColors.bb10Card.r, MColors.bb10Card.g, MColors.bb10Card.b, 0.5)
        antialiasing: Constants.enableAntialiasing
        scale: isPressed ? 0.98 : 1
        opacity: isAvailable ? 1 : 0.5

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
        enabled: isAvailable
        onPressed: function (mouse) {
            isPressed = true;
            HapticManager.light();
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

            HapticManager.medium();
            tile.longPressed();
        }
    }
}
