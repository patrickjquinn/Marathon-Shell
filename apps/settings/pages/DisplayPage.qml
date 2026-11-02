pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    function setBrightness(percent) {
        Display.brightness = Math.max(0, Math.min(100, percent)) / 100;
    }

    function pickNightTime(minutes, chosen) {
        const dialog = pageStack.push(timePicker, {
            hour: Math.floor(minutes / 60),
            minute: minutes % 60
        });
        dialog.accepted.connect(() => chosen(dialog.hour * 60 + dialog.minute));
    }

    Component {
        id: timePicker

        TimePickerDialog {}
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Display")
            }

            Slider {
                id: brightness

                objectName: "brightnessSlider"
                width: parent.width
                label: qsTr("Brightness")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                value: Logic.percent(Display.brightness)
                valueText: qsTr("%1%").arg(Math.round(sliderValue))
                onValueChanged: {
                    if (down)
                        page.setBrightness(value);
                }
                onReleased: page.setBrightness(value)
            }
            TextSwitch {
                objectName: "autoBrightnessSwitch"
                visible: Display.lightSensorAvailable
                text: qsTr("Automatic brightness")
                description: qsTr("Adjusts brightness to the light around you")
                automaticCheck: false
                checked: Display.autoBrightnessEnabled
                onClicked: Display.autoBrightnessEnabled = !checked
            }

            SectionHeader {
                text: qsTr("Night light")
            }
            TextSwitch {
                objectName: "nightLightSwitch"
                text: qsTr("Night light")
                description: qsTr("Warms the screen's colours, which is easier on your eyes and sleep in the evening")
                automaticCheck: false
                checked: Display.nightLightEnabled
                onClicked: Display.nightLightEnabled = !checked
            }
            Slider {
                objectName: "nightLightWarmth"
                width: parent.width
                label: qsTr("Warmth")
                minimumValue: 0
                maximumValue: 100
                stepSize: 1
                value: Logic.nightLightWarmth(Display.nightLightTemperature)
                valueText: qsTr("%1 K").arg(Logic.nightLightKelvin(sliderValue))
                onValueChanged: {
                    if (down)
                        Display.nightLightTemperature = Logic.nightLightKelvin(value);
                }
                onReleased: Display.nightLightTemperature = Logic.nightLightKelvin(value)
            }
            ComboBox {
                objectName: "nightLightSchedule"
                width: parent.width
                label: qsTr("Schedule")
                description: Logic.nightLightSchedules[currentIndex].description
                Binding on currentIndex {
                    value: Math.max(0, Logic.nightLightSchedules.findIndex(s => s.id === Display.nightLightSchedule))
                }
                menu: ContextMenu {
                    Repeater {
                        model: Logic.nightLightSchedules

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: Display.nightLightSchedule = modelData.id
                        }
                    }
                }
            }
            ValueButton {
                objectName: "nightLightFrom"
                visible: Display.nightLightSchedule === "custom"
                label: qsTr("Turns on")
                value: Format.formatDate(Logic.timeOfDay(Display.nightLightFrom), Formatter.TimeValue)
                onClicked: page.pickNightTime(Display.nightLightFrom, minutes => Display.setNightLightTimes(minutes, Display.nightLightTo))
            }
            ValueButton {
                objectName: "nightLightTo"
                visible: Display.nightLightSchedule === "custom"
                label: qsTr("Turns off")
                value: Format.formatDate(Logic.timeOfDay(Display.nightLightTo), Formatter.TimeValue)
                onClicked: page.pickNightTime(Display.nightLightTo, minutes => Display.setNightLightTimes(Display.nightLightFrom, minutes))
            }

            SectionHeader {
                text: qsTr("Screen")
            }
            ComboBox {
                id: timeout

                objectName: "timeoutCombo"
                width: parent.width
                label: qsTr("Turn screen off after")
                Binding on currentIndex {
                    value: Logic.screenTimeouts.findIndex(option => option.ms === Settings.screenTimeout)
                }
                menu: ContextMenu {
                    Repeater {
                        model: Logic.screenTimeouts

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: Settings.screenTimeout = modelData.ms
                        }
                    }
                }
            }
            TextSwitch {
                objectName: "rotationSwitch"
                visible: Display.rotationAvailable
                text: qsTr("Auto-rotate")
                description: qsTr("Turns the screen with the phone. Off keeps it as it is.")
                automaticCheck: false
                checked: !Display.rotationLocked
                onClicked: Display.rotationLocked = checked
            }

            SectionHeader {
                text: qsTr("Interface")
            }
            ComboBox {
                objectName: "scaleCombo"
                width: parent.width
                label: qsTr("Interface size")
                description: qsTr("Size of text and controls. Open apps change size when you reopen them.")
                Binding on currentIndex {
                    value: Logic.nearestIndex(Logic.scales.map(s => s.factor), Settings.userScaleFactor)
                }
                menu: ContextMenu {
                    Repeater {
                        model: Logic.scales

                        MenuItem {
                            required property var modelData

                            text: modelData.title + " · " + modelData.description
                            onClicked: Settings.userScaleFactor = modelData.factor
                        }
                    }
                }
            }
            TextSwitch {
                objectName: "reduceMotionSwitch"
                text: qsTr("Reduce motion")
                description: qsTr("Replaces slides and springs with fades")
                automaticCheck: false
                checked: Settings.reduceMotion
                onClicked: Settings.reduceMotion = !checked
            }
        }

        VerticalScrollDecorator {}
    }
}
