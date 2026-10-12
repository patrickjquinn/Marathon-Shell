pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Rectangle {
    id: predictionBar

    property var predictions: []
    property string currentWord: ""

    signal predictionSelected(string word)

    implicitHeight: Math.round(48 * Constants.scaleFactor)
    visible: predictions.length > 0
    height: visible ? implicitHeight : 0
    // Plain words, the best guess in the highlight, as Sailfish shows them.
    color: "transparent"

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
                radius: Silica.Theme.paddingSmall
                color: predictionMouseArea.pressed ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"

                Text {
                    anchors.centerIn: parent
                    width: parent.width - Math.round(12 * Constants.scaleFactor)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: predictionChip.modelData
                    color: predictionChip.index === 0 || predictionMouseArea.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    font.family: Silica.Theme.fontFamily
                    font.pixelSize: Silica.Theme.fontSizeMedium
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

            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: predictionBar.currentWord ? "..." : ""
        color: Silica.Theme.secondaryColor
        font.pixelSize: Silica.Theme.fontSizeSmall
        visible: predictionBar.predictions.length === 0
        opacity: 0.5
    }
}
