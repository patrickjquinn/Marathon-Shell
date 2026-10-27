import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

OobeSheet {
    id: root

    //: Title of the accessibility sheet on the first setup screen
    title: qsTr("Accessibility")

    function applySize() {
        settle.stop();
        const factor = Math.round(sizeSlider.value) / 100;
        if (Math.abs(factor - SettingsManagerCpp.userScaleFactor) > 0.001)
            SettingsManagerCpp.userScaleFactor = factor;
    }

    // As on Easy to read: the shell re-sizes when the finger rests or lifts.
    Timer {
        id: settle

        interval: 250
        onTriggered: root.applySize()
    }

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
        id: sizeSlider

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
            if (down)
                settle.restart();
            else
                root.applySize();
        }
        onDownChanged: {
            if (!down)
                root.applySize();
        }
    }
}
