import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// Easy to read: text and icon size, on the real home grid.
Item {
    id: root

    signal done

    Column {
        anchors.fill: parent
        anchors.topMargin: Silica.Theme.paddingLarge
        anchors.bottomMargin: Silica.Theme.paddingMedium
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        spacing: Silica.Theme.paddingMedium

        Silica.Label {
            width: parent.width
            text: qsTr("Easy to read")
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeLarge
            wrapMode: Text.WordWrap
        }

        Silica.Label {
            width: parent.width
            //: Setup, size step: what the slider does
            text: qsTr("Drag until your home screen feels right.")
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        OobeGridPreview {
            id: preview

            objectName: "sizePreview"
            width: parent.width
            height: Math.max(0, parent.height - y - slider.height - button.height - 2 * parent.spacing)
            rows: fitRows
        }

        Silica.Slider {
            id: slider

            objectName: "sizeSlider"
            width: parent.width
            label: qsTr("Text and icon size")
            minimumValue: 75
            maximumValue: 150
            stepSize: 5
            value: Math.round(SettingsManagerCpp.userScaleFactor * 100)
            valueText: Math.round(value) + "%"
            onValueChanged: SettingsManagerCpp.userScaleFactor = Math.round(value) / 100
        }

        Silica.Button {
            id: button

            objectName: "sizeContinue"

            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Continue")
            onClicked: root.done()
        }
    }
}
