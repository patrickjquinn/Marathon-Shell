pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Rectangle {
    id: predictionBar

    property var predictions: []
    property string currentWord: ""
    readonly property bool canPaste: Silica.Clipboard.hasText

    signal predictionSelected(string word)
    signal pasteRequested(string text)

    implicitHeight: Math.round(48 * Constants.scaleFactor)
    visible: predictions.length > 0 || canPaste
    height: visible ? implicitHeight : 0
    // Plain words, the best guess in the highlight.
    color: "transparent"

    // As Sailfish's keyboard: the clipboard, ready to paste, at the start of the bar.
    Rectangle {
        id: pasteChip

        objectName: "pasteChip"
        x: chipRow.spacing
        width: predictionBar.canPaste ? pasteRow.width + 2 * Silica.Theme.paddingMedium : 0
        height: Math.round(40 * Constants.scaleFactor)
        visible: predictionBar.canPaste
        radius: Silica.Theme.paddingSmall
        color: pasteMouseArea.pressed ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"
        anchors.verticalCenter: parent.verticalCenter
        //: Accessible name of the keyboard's key that pastes the clipboard
        Accessible.name: qsTr("Paste")
        Accessible.role: Accessible.Button

        Row {
            id: pasteRow

            anchors.centerIn: parent
            spacing: Silica.Theme.paddingSmall

            GlyphIcon {
                name: "clipboard-text"
                size: Silica.Theme.iconSizeSmall
                color: pasteMouseArea.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: qsTr("Paste")
                color: pasteMouseArea.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: pasteMouseArea

            anchors.fill: parent
            onClicked: {
                if (SettingsManagerCpp.keyboardHapticStrength !== "off")
                    HapticManager.light();
                predictionBar.pasteRequested(Silica.Clipboard.text);
            }
        }
    }

    Row {
        id: chipRow

        readonly property var shown: predictionBar.predictions.slice(0, 3)

        anchors.fill: parent
        anchors.leftMargin: pasteChip.width + spacing
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
                        if (SettingsManagerCpp.keyboardHapticStrength !== "off")
                            HapticManager.light();
                        predictionBar.predictionSelected(predictionChip.modelData);
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: MMotion.ms(100)
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
