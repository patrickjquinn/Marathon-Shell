pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    readonly property var timeouts: Settings.screenTimeoutOptions()
    readonly property var wallpapers: typeof Wallpapers !== "undefined" ? Wallpapers : null
    readonly property var wallpaper: wallpapers ? wallpapers.wallpapers.find(w => w.path === wallpapers.currentWallpaper) : undefined
    readonly property var clockPositions: [
        { value: "left", title: qsTr("Left"), description: qsTr("Best for right-side notches") },
        { value: "center", title: qsTr("Center"), description: qsTr("Default position") },
        { value: "right", title: qsTr("Right"), description: qsTr("Best for left-side notches") }
    ]

    function setBrightness(percent) {
        Display.brightness = Math.max(0, Math.min(100, percent)) / 100;
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
                text: qsTr("Automatic brightness")
                description: qsTr("Adjusts brightness to the light around you")
                automaticCheck: false
                checked: Display.autoBrightnessEnabled
                onClicked: Display.autoBrightnessEnabled = !checked
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
                    value: page.timeouts.findIndex(option => Settings.screenTimeoutValue(option) === Display.screenTimeout)
                }
                menu: ContextMenu {
                    Repeater {
                        model: page.timeouts

                        MenuItem {
                            required property string modelData

                            text: modelData
                            onClicked: Display.screenTimeout = Settings.screenTimeoutValue(modelData)
                        }
                    }
                }
            }
            TextSwitch {
                objectName: "rotationSwitch"
                text: qsTr("Rotation lock")
                description: qsTr("Keeps the screen in its current orientation")
                automaticCheck: false
                checked: Display.rotationLocked
                onClicked: Display.rotationLocked = !checked
            }
            ValueButton {
                objectName: "wallpaperButton"
                label: qsTr("Wallpaper")
                value: page.wallpaper ? page.wallpaper.name : ""
                onClicked: pageStack.push(Qt.resolvedUrl("WallpaperPage.qml"))
            }

            SectionHeader {
                text: qsTr("Interface")
            }
            ComboBox {
                objectName: "scaleCombo"
                width: parent.width
                label: qsTr("Interface size")
                description: qsTr("Size of text and controls")
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
            ComboBox {
                objectName: "clockCombo"
                width: parent.width
                label: qsTr("Status bar clock")
                description: page.clockPositions[Math.max(0, currentIndex)].description
                Binding on currentIndex {
                    value: Math.max(0, page.clockPositions.findIndex(p => p.value === (Settings.statusBarClockPosition || "center")))
                }
                menu: ContextMenu {
                    Repeater {
                        model: page.clockPositions

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: Settings.statusBarClockPosition = modelData.value
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
