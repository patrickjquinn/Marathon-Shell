import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

/**
 * World-Class Power Menu - Tile Grid Design
 * Modern, visual, with large touchable tiles
 */
Item {
    id: root
    anchors.fill: parent
    visible: false
    z: Constants.zIndexModal + 100

    signal sleepRequested
    signal rebootRequested
    signal shutdownRequested
    signal canceled

    property bool showing: false

    function show() {
        showing = true;
        visible = true;
        HapticService.medium();
        fadeIn.start();
    }

    function hide() {
        showing = false;
        fadeOut.start();
    }

    // Dark backdrop
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "#000000"
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.canceled();
                root.hide();
            }
        }
    }

    // Power menu dialog
    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, Math.round(360 * Constants.scaleFactor))
        height: contentColumn.height + MSpacing.xxl * 2
        radius: MRadius.lg
        color: Qt.rgba(15 / 255, 15 / 255, 15 / 255, 0.98)
        border.width: Math.max(1, Math.round(Constants.scaleFactor))
        border.color: MColors.border
        layer.enabled: true
        opacity: 0
        scale: 0.9

        // Inner glow
        Rectangle {
            anchors.fill: parent
            anchors.margins: Math.max(1, Math.round(Constants.scaleFactor))
            radius: parent.radius - Math.max(1, Math.round(Constants.scaleFactor))
            color: "transparent"
            border.width: Math.max(1, Math.round(Constants.scaleFactor))
            border.color: Qt.rgba(255 / 255, 255 / 255, 255 / 255, 0.05)
        }

        // Prevent click propagation
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            id: contentColumn
            anchors.centerIn: parent
            width: parent.width - MSpacing.xxl * 2
            spacing: MSpacing.lg

            // Title
            Text {
                text: "Power Options"
                font.pixelSize: MTypography.sizeLarge
                font.weight: MTypography.weightBold
                font.family: MTypography.fontFamily
                color: MColors.textPrimary
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            // 2x2 Grid of power tiles
            Grid {
                width: parent.width
                columns: 2
                rowSpacing: MSpacing.md
                columnSpacing: MSpacing.md

                // Sleep Tile
                Rectangle {
                    id: sleepTile
                    width: (parent.width - MSpacing.md) / 2
                    height: Math.round(90 * Constants.scaleFactor)
                    radius: MRadius.md
                    color: sleepMouseArea.pressed ? MColors.bb10Elevated : MColors.bb10Card
                    border.width: Math.max(1, Math.round(Constants.scaleFactor))
                    border.color: MColors.border

                    scale: sleepMouseArea.pressed ? 0.95 : 1.0
                    Behavior on scale {
                        SpringAnimation {
                            spring: MMotion.springMedium
                            damping: MMotion.dampingMedium
                            epsilon: MMotion.epsilon
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: MMotion.xs
                        }
                    }

                    // Inner border
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        color: "transparent"
                        border.width: 1
                        border.color: MColors.borderSubtle
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: MSpacing.sm

                        Icon {
                            name: "moon"
                            size: Math.round(32 * Constants.scaleFactor)
                            color: MColors.textPrimary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Sleep"
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightMedium
                            font.family: MTypography.fontFamily
                            color: MColors.textPrimary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: sleepMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.medium();
                            root.sleepRequested();
                            root.hide();
                        }
                    }
                }

                // Reboot Tile
                Rectangle {
                    id: rebootTile
                    width: (parent.width - MSpacing.md) / 2
                    height: Math.round(90 * Constants.scaleFactor)
                    radius: MRadius.md
                    color: rebootMouseArea.pressed ? MColors.bb10Elevated : MColors.bb10Card
                    border.width: Math.max(1, Math.round(Constants.scaleFactor))
                    border.color: MColors.border

                    scale: rebootMouseArea.pressed ? 0.95 : 1.0
                    Behavior on scale {
                        SpringAnimation {
                            spring: MMotion.springMedium
                            damping: MMotion.dampingMedium
                            epsilon: MMotion.epsilon
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: MMotion.xs
                        }
                    }

                    // Inner border
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        color: "transparent"
                        border.width: 1
                        border.color: MColors.borderSubtle
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: MSpacing.sm

                        Icon {
                            name: "rotate-ccw"
                            size: Math.round(32 * Constants.scaleFactor)
                            color: MColors.textPrimary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Reboot"
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightMedium
                            font.family: MTypography.fontFamily
                            color: MColors.textPrimary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: rebootMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.medium();
                            root.rebootRequested();
                            root.hide();
                        }
                    }
                }

                // Power Off Tile (primary/teal)
                Rectangle {
                    id: powerOffTile
                    width: (parent.width - MSpacing.md) / 2
                    height: Math.round(90 * Constants.scaleFactor)
                    radius: MRadius.md

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: powerOffMouseArea.pressed ? MColors.marathonTealDark : MColors.marathonTealBright
                        }
                        GradientStop {
                            position: 0.5
                            color: MColors.marathonTeal
                        }
                        GradientStop {
                            position: 1.0
                            color: MColors.marathonTealDark
                        }
                    }

                    border.width: 0

                    scale: powerOffMouseArea.pressed ? 0.95 : 1.0
                    Behavior on scale {
                        SpringAnimation {
                            spring: MMotion.springMedium
                            damping: MMotion.dampingMedium
                            epsilon: MMotion.epsilon
                        }
                    }

                    // Outer glow
                    Rectangle {
                        visible: true
                        anchors.centerIn: parent
                        width: parent.width + Math.round(6 * Constants.scaleFactor)
                        height: parent.height + Math.round(6 * Constants.scaleFactor)
                        radius: parent.radius + Math.round(3 * Constants.scaleFactor)
                        color: "transparent"
                        border.width: Math.round(3 * Constants.scaleFactor)
                        border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.3)
                        z: -1
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: MSpacing.sm

                        Icon {
                            name: "power"
                            size: Math.round(32 * Constants.scaleFactor)
                            color: "#000000"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Power Off"
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightBold
                            font.family: MTypography.fontFamily
                            color: "#000000"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: powerOffMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.medium();
                            root.shutdownRequested();
                            root.hide();
                        }
                    }
                }

                // Cancel Tile
                Rectangle {
                    id: cancelTile
                    width: (parent.width - MSpacing.md) / 2
                    height: Math.round(90 * Constants.scaleFactor)
                    radius: MRadius.md
                    color: "transparent"
                    border.width: Math.max(1, Math.round(Constants.scaleFactor))
                    border.color: cancelMouseArea.pressed ? MColors.borderGlass : MColors.border

                    scale: cancelMouseArea.pressed ? 0.95 : 1.0
                    Behavior on scale {
                        SpringAnimation {
                            spring: MMotion.springMedium
                            damping: MMotion.dampingMedium
                            epsilon: MMotion.epsilon
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: MMotion.xs
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: MSpacing.sm

                        Icon {
                            name: "x"
                            size: Math.round(32 * Constants.scaleFactor)
                            color: MColors.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Cancel"
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightMedium
                            font.family: MTypography.fontFamily
                            color: MColors.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: cancelMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            root.canceled();
                            root.hide();
                        }
                    }
                }
            }
        }
    }

    // Fade in animation
    ParallelAnimation {
        id: fadeIn
        NumberAnimation {
            target: backdrop
            property: "opacity"
            to: 0.7
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: dialog
            property: "opacity"
            to: 1
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: dialog
            property: "scale"
            to: 1
            duration: MMotion.quick
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    // Fade out animation
    SequentialAnimation {
        id: fadeOut
        ParallelAnimation {
            NumberAnimation {
                target: backdrop
                property: "opacity"
                to: 0
                duration: MMotion.fast
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: dialog
                property: "opacity"
                to: 0
                duration: MMotion.fast
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: dialog
                property: "scale"
                to: 0.9
                duration: MMotion.fast
                easing.type: Easing.InCubic
            }
        }
        PropertyAction {
            target: root
            property: "visible"
            value: false
        }
    }
}
