// Marathon Virtual Keyboard - Prediction Bar
// Word suggestions bar above keyboard (BlackBerry style)
import QtQuick
import MarathonOS.Shell

Rectangle {
    id: predictionBar

    property var predictions: []  // Array of suggested words
    property string currentWord: ""

    signal predictionSelected(string word)

    // Always expose a stable height via implicitHeight
    implicitHeight: Math.round(40 * Constants.scaleFactor)

    // HIDE when no predictions (user request)
    visible: predictions.length > 0
    height: visible ? implicitHeight : 0
    color: typeof MColors !== 'undefined' ? MColors.surface : "#0d0d0e"
    border.width: 0
    border.color: "transparent"

    // Predictions display
    Row {
        anchors.centerIn: parent
        spacing: Math.round(12 * Constants.scaleFactor)
        visible: predictionBar.predictions.length > 0

        Repeater {
            model: predictionBar.predictions

            // Prediction button
            Rectangle {
                width: Math.round(100 * Constants.scaleFactor)
                height: Math.round(32 * Constants.scaleFactor)
                radius: Constants.borderRadiusSmall
                color: predictionMouseArea.pressed ? (typeof MColors !== 'undefined' ? MColors.accent : "#00bfa5") : (typeof MColors !== 'undefined' ? MColors.elevated : "#161718")
                border.width: Constants.borderWidthMedium
                border.color: index === 0 ? (typeof MColors !== 'undefined' ? MColors.accentBright : "#1de9b6") : (typeof MColors !== 'undefined' ? MColors.border : "rgba(1, 1, 1, 0.08)")
                antialiasing: Constants.enableAntialiasing

                // PERFORMANCE: Enable layer for GPU-accelerated animations
                layer.enabled: true
                layer.smooth: true

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                // PERFORMANCE: Replace SpringAnimation with fast NumberAnimation
                // SpringAnimation is expensive (physics simulation), unnecessary for simple scale
                Behavior on scale {
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutCubic
                    }
                }

                scale: predictionMouseArea.pressed ? 0.95 : 1.0

                // Inner border
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: Constants.borderWidthThin
                    border.color: index === 0 ? (typeof MColors !== 'undefined' ? MColors.marathonTealHoverGradient : "rgba(0, 191, 165, 0.03)") : (typeof MColors !== 'undefined' ? MColors.borderSubtle : "rgba(1, 1, 1, 0.05)")
                    antialiasing: parent.antialiasing
                }

                // Prediction text
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: predictionMouseArea.pressed ? (typeof MColors !== 'undefined' ? MColors.textOnAccent : "#ffffff") : (typeof MColors !== 'undefined' ? MColors.text : "#f5f5f5")
                    font.pixelSize: Math.round(15 * Constants.scaleFactor)
                    font.weight: index === 0 ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: predictionMouseArea
                    anchors.fill: parent

                    onClicked: {
                        HapticService.light();
                        predictionBar.predictionSelected(modelData);
                    }
                }
            }
        }
    }

    // Placeholder when no predictions
    Text {
        anchors.centerIn: parent
        text: predictionBar.currentWord ? "..." : ""
        color: typeof MColors !== 'undefined' ? MColors.textSecondary : "#6a6a6a"
        font.pixelSize: Math.round(14 * Constants.scaleFactor)
        visible: predictionBar.predictions.length === 0
        opacity: 0.5
    }
}
