// Marathon Virtual Keyboard - Prediction Bar
// Word suggestions bar above keyboard (BlackBerry style)
import QtQuick

Rectangle {
    id: predictionBar

    property var predictions: []  // Array of suggested words
    property string currentWord: ""

    signal predictionSelected(string word)

    // Always expose a stable height via implicitHeight
    implicitHeight: Math.round(40 * scaleFactor)

    // HIDE when no predictions (user request)
    visible: predictions.length > 0
    height: visible ? implicitHeight : 0
    color: MColors.surface
    border.width: 0
    border.color: "transparent"

    // Predictions display
    Row {
        anchors.centerIn: parent
        spacing: Math.round(12 * scaleFactor)
        visible: predictionBar.predictions.length > 0

        Repeater {
            model: predictionBar.predictions

            // Prediction button
            Rectangle {
                width: Math.round(100 * scaleFactor)
                height: Math.round(32 * scaleFactor)
                radius: Constants.borderRadiusSmall
                color: predictionMouseArea.pressed ? MColors.accent : MColors.elevated
                border.width: Constants.borderWidthMedium
                border.color: index === 0 ? MColors.accentBright : MColors.border
                antialiasing: Constants.enableAntialiasing

                Behavior on color {
                    ColorAnimation {
                        duration: MMotion.quick
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    SpringAnimation {
                        spring: MMotion.springMedium
                        damping: MMotion.dampingMedium
                        epsilon: MMotion.epsilon
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
                    border.color: index === 0 ? MColors.marathonTealHoverGradient : MColors.borderSubtle
                    antialiasing: parent.antialiasing
                }

                // Prediction text
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: predictionMouseArea.pressed ? MColors.textOnAccent : MColors.text
                    font.pixelSize: Math.round(15 * scaleFactor)
                    font.weight: index === 0 ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: predictionMouseArea
                    anchors.fill: parent

                    onClicked: {
                        keyboard.hapticRequested("light");
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
        color: MColors.textSecondary
        font.pixelSize: Math.round(14 * scaleFactor)
        visible: predictionBar.predictions.length === 0
        opacity: 0.5
    }
}
