import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: hudContainer

    property string hudType: "volume"
    property real hudValue: 0
    property bool hudVisible: false

    function showVolume(value) {
        hudType = "volume";
        hudValue = value;
        show();
    }

    function showBrightness(value) {
        hudType = "brightness";
        hudValue = value;
        show();
    }

    function show() {
        hudVisible = true;
        hud.opacity = 1;
        autoHideTimer.restart();
    }

    function hide() {
        hudVisible = false;
        fadeOut.start();
    }

    anchors.fill: parent
    z: 2900

    Rectangle {
        id: hud

        anchors.centerIn: parent
        // Box scales with the same factor as its contents (Icon/MText scale off
        // Constants.scaleFactor). A fixed 200 px square let the scaled contents
        // break out on high-DPI panels; clip is a belt-and-braces guard.
        width: Math.round(200 * (Constants.scaleFactor || 1))
        height: Math.round(200 * (Constants.scaleFactor || 1))
        clip: true
        // DS says 4 px corners on every chrome surface. Previously
        // Constants.borderRadiusSharp (= 0) made this a flat box,
        // breaking continuity with the rest of the shell language.
        radius: MRadius.md
        color: MElevation.getSurface(4)
        border.width: 1
        border.color: MElevation.getBorderOuter(4)
        antialiasing: true
        opacity: 0
        visible: hudContainer.hudVisible

        // Inner hairline highlight — same role as MTopHairline elsewhere,
        // but a HUD only ever sits as a free-floating overlay so the
        // simpler all-around inset hairline is fine.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: MColors.whiteOverlay04
        }

        Column {
            anchors.centerIn: parent
            spacing: MSpacing.lg
            width: parent.width - Math.round(40 * (Constants.scaleFactor || 1))

            Icon {
                name: hudContainer.hudType === "volume" ? "volume-2" : "sun"
                size: Constants.iconSizeXLarge
                color: MColors.textPrimary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Column {
                width: parent.width
                spacing: MSpacing.sm

                Rectangle {
                    width: parent.width
                    height: Math.round(8 * (Constants.scaleFactor || 1))
                    radius: MRadius.md
                    color: MColors.whiteOverlay04
                    border.width: 1
                    border.color: MColors.whiteOverlay04

                    Rectangle {
                        width: parent.width * hudContainer.hudValue
                        height: parent.height
                        radius: parent.radius
                        // DS teal accent — was an inline RGB literal duplicating
                        // MColors.marathonTeal at ~0.9 opacity.
                        color: Qt.rgba(0, 191 / 255, 165 / 255, 0.9)

                        Behavior on width {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                MText {
                    text: Math.round(hudContainer.hudValue * 100) + "%"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeHeadline
                    font.weight: MTypography.weightDemiBold
                    font.letterSpacing: MTypography.trackingHeadline
                    // Tabular figures so the percentage digits don't jitter.
                    tnum: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        Behavior on opacity {
            enabled: Constants.enableAnimations

            NumberAnimation {
                duration: Constants.animationNormal
                easing.type: Easing.OutCubic
            }
        }
    }

    Timer {
        id: autoHideTimer

        interval: 2000
        onTriggered: hide()
    }

    NumberAnimation {
        id: fadeOut

        target: hud
        property: "opacity"
        to: 0
        duration: 200
        easing.type: Easing.InCubic
    }
}
