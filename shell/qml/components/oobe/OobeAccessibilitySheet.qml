import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

OobeSheet {
    id: root

    //: Title of the accessibility sheet on the first setup screen
    title: qsTr("Accessibility")

    Silica.TextSwitch {
        objectName: "reduceMotionSwitch"
        width: parent.width
        //: Switch: fades in place of moving animations
        text: qsTr("Reduce motion")
        checked: SettingsManagerCpp.reduceMotion
        automaticCheck: false
        onClicked: SettingsManagerCpp.reduceMotion = !SettingsManagerCpp.reduceMotion
    }

    Silica.Slider {
        objectName: "textSizeSlider"
        width: parent.width
        //: Slider that scales text and icons everywhere
        label: qsTr("Text and icon size")
        minimumValue: 75
        maximumValue: 150
        stepSize: 5
        value: Math.round(SettingsManagerCpp.userScaleFactor * 100)
        valueText: Math.round(value) + "%"
        onValueChanged: {
            if (Math.round(value) !== Math.round(SettingsManagerCpp.userScaleFactor * 100))
                SettingsManagerCpp.userScaleFactor = Math.round(value) / 100;
        }
    }
}
