import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

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
        // The shade's own sliders are the feedback while it is open.
        if (UIStore.quickSettingsOpen)
            return;
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

    // A strip across the top with a highlight bar for the volume.
    Rectangle {
        id: hud

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight
        anchors.margins: Silica.Theme.paddingSmall
        height: Silica.Theme.itemSizeSmall
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        opacity: 0
        visible: hudContainer.hudVisible

        Row {
            anchors.fill: parent
            anchors.leftMargin: Silica.Theme.paddingLarge
            anchors.rightMargin: Silica.Theme.paddingLarge
            spacing: Silica.Theme.paddingLarge

            GlyphIcon {
                id: hudIcon
                name: hudContainer.hudType === "volume" ? (hudContainer.hudValue === 0 ? "speaker-x" : "speaker-high") : "sun"
                size: Silica.Theme.iconSizeSmall
                color: Silica.Theme.highlightColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: parent.width - hudIcon.width - percent.width - parent.spacing * 2
                height: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
                radius: height / 2
                color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.2)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: parent.width * hudContainer.hudValue
                    height: parent.height
                    radius: parent.radius
                    color: Silica.Theme.highlightColor

                    Behavior on width {
                        NumberAnimation { duration: MMotion.quick; easing.type: Easing.OutCubic }
                    }
                }
            }

            Silica.Label {
                id: percent
                width: Silica.Theme.itemSizeExtraSmall
                horizontalAlignment: Text.AlignRight
                text: Math.round(hudContainer.hudValue * 100) + "%"
                color: Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeSmall
                font.features: {
                    "tnum": 1
                }
                anchors.verticalCenter: parent.verticalCenter
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
        onTriggered: hudContainer.hide()
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
