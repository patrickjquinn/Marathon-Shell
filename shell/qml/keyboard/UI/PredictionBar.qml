pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick

Rectangle {
    id: predictionBar

    property var predictions: []
    property string currentWord: ""

    signal predictionSelected(string word)

    implicitHeight: Math.round(48 * Constants.scaleFactor)
    visible: predictions.length > 0
    height: visible ? implicitHeight : 0
    color: typeof MColors !== 'undefined' ? MColors.surface : "#0d0d0e"
    border.width: 0
    border.color: "transparent"

    Row {
        id: chipRow

        readonly property var shown: predictionBar.predictions.slice(0, 3)

        anchors.fill: parent
        anchors.leftMargin: spacing
        anchors.rightMargin: spacing
        spacing: Math.round(6 * Constants.scaleFactor)
        visible: predictionBar.predictions.length > 0

        Repeater {
            model: chipRow.shown

            Rectangle {
                id: predictionChip

                required property var modelData
                required property int index

                width: (chipRow.width - chipRow.spacing * (chipRow.shown.length - 1)) / chipRow.shown.length
                height: Math.round(40 * Constants.scaleFactor)
                anchors.verticalCenter: parent.verticalCenter
                radius: Constants.borderRadiusSmall
                color: predictionMouseArea.pressed ? (typeof MColors !== 'undefined' ? MColors.accent : "#00bfa5") : (typeof MColors !== 'undefined' ? MColors.elevated : "#161718")
                border.width: Constants.borderWidthMedium
                border.color: index === 0 ? (typeof MColors !== 'undefined' ? MColors.accentBright : "#1de9b6") : (typeof MColors !== 'undefined' ? MColors.border : "rgba(1, 1, 1, 0.08)")
                antialiasing: Constants.enableAntialiasing
                layer.enabled: true
                layer.smooth: true
                scale: predictionMouseArea.pressed ? 0.95 : 1

                MTopHairline {
                    radius: parent.radius
                    color: predictionChip.index === 0 ? (typeof MColors !== 'undefined' ? MColors.marathonTealHoverGradient : "rgba(0, 191, 165, 0.03)") : (typeof MColors !== 'undefined' ? MColors.borderSubtle : "rgba(1, 1, 1, 0.05)")
                    lineWidth: Constants.borderWidthThin
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - Math.round(12 * Constants.scaleFactor)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: predictionChip.modelData
                    color: predictionMouseArea.pressed ? (typeof MColors !== 'undefined' ? MColors.textOnAccent : "#ffffff") : (typeof MColors !== 'undefined' ? MColors.text : "#f5f5f5")
                    font.pixelSize: Math.round(15 * Constants.scaleFactor)
                    font.weight: predictionChip.index === 0 ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: predictionMouseArea

                    anchors.fill: parent
                    onClicked: {
                        HapticManager.light();
                        predictionBar.predictionSelected(predictionChip.modelData);
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: predictionBar.currentWord ? "..." : ""
        color: typeof MColors !== 'undefined' ? MColors.textSecondary : "#6a6a6a"
        font.pixelSize: Math.round(14 * Constants.scaleFactor)
        visible: predictionBar.predictions.length === 0
        opacity: 0.5
    }
}
