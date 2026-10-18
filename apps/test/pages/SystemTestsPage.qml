pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../components"

Page {
    id: page

    property var app
    readonly property var power: typeof Power !== "undefined" ? Power : null
    readonly property var network: typeof Network !== "undefined" ? Network : null
    readonly property var display: typeof Display !== "undefined" ? Display : null
    // Shell-only; absent in the app runner.
    readonly property var modem: typeof ModemManagerCpp !== "undefined" ? ModemManagerCpp : null
    // The shell keeps Power and Display to system apps.
    readonly property bool powerRefused: power !== null && power.permitted === false
    readonly property bool displayRefused: display !== null && display.permitted === false

    function onOff(on) {
        return on ? qsTr("On") : qsTr("Off");
    }

    function refused(isRefused, value) {
        return isRefused ? qsTr("Not permitted") : value;
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("System services")
                description: page.app.summary
            }

            SectionHeader {
                text: qsTr("Power & battery")
            }
            Column {
                width: parent.width

                DetailItem {
                    objectName: "battery"
                    label: qsTr("Battery")
                    value: page.refused(page.powerRefused, (page.power ? page.power.batteryLevel : 0) + "%")
                }
                DetailItem {
                    objectName: "charging"
                    label: qsTr("Charging")
                    value: page.refused(page.powerRefused, page.power && page.power.isCharging ? qsTr("Yes") : qsTr("No"))
                }
                DetailItem {
                    objectName: "powerSave"
                    label: qsTr("Power save")
                    value: page.refused(page.powerRefused, page.onOff(page.power && page.power.isPowerSaveMode))
                }
            }
            Actions {
                TestItem {
                    objectName: "togglePowerSave"
                    text: qsTr("Toggle power save")
                    onClicked: page.app.run("Toggle power save", () => page.power.setPowerSaveMode(!page.power.isPowerSaveMode))
                }
            }

            SectionHeader {
                text: qsTr("Network")
            }
            Column {
                width: parent.width

                DetailItem {
                    label: qsTr("WiFi")
                    value: page.network && page.network.wifiConnected ? qsTr("Connected (%1)").arg(page.network.wifiSsid) : qsTr("Disconnected")
                }
                DetailItem {
                    label: qsTr("Signal")
                    value: (page.network ? page.network.wifiSignalStrength : 0) + "%"
                    visible: page.network !== null && page.network.wifiConnected
                }
                DetailItem {
                    label: qsTr("Cellular")
                    value: page.modem && page.modem.registered ? page.modem.operatorName : qsTr("Disconnected")
                }
                DetailItem {
                    objectName: "airplane"
                    label: qsTr("Airplane mode")
                    value: page.onOff(page.network && page.network.airplaneModeEnabled)
                }
            }
            Actions {
                TestItem {
                    objectName: "scanWifi"
                    text: qsTr("Scan WiFi")
                    onClicked: page.app.run("WiFi scan", () => page.network.scanWifi())
                }
                TestItem {
                    objectName: "toggleAirplane"
                    text: qsTr("Toggle airplane")
                    onClicked: page.app.run("Toggle airplane mode", () => page.network.setAirplaneMode(!page.network.airplaneModeEnabled))
                }
            }

            SectionHeader {
                text: qsTr("Display")
            }
            Column {
                width: parent.width

                DetailItem {
                    objectName: "brightness"
                    label: qsTr("Brightness")
                    value: page.refused(page.displayRefused, (page.display ? Math.round(page.display.brightness * 100) : 0) + "%")
                }
                DetailItem {
                    objectName: "autoBrightness"
                    label: qsTr("Auto-brightness")
                    value: page.refused(page.displayRefused, page.display && !page.display.lightSensorAvailable ? qsTr("No light sensor") : page.onOff(page.display && page.display.autoBrightnessEnabled))
                }
            }
            Actions {
                TestItem {
                    objectName: "brightnessUp"
                    text: qsTr("Increase")
                    onClicked: page.app.run("Increase brightness", () => {
                        page.display.brightness = Math.min(1, page.display.brightness + 0.1);
                    })
                }
                TestItem {
                    objectName: "brightnessDown"
                    text: qsTr("Decrease")
                    onClicked: page.app.run("Decrease brightness", () => {
                        page.display.brightness = Math.max(0, page.display.brightness - 0.1);
                    })
                }
                TestItem {
                    objectName: "toggleAuto"
                    visible: page.display !== null && page.display.lightSensorAvailable
                    text: qsTr("Toggle auto")
                    onClicked: page.app.run("Toggle auto-brightness", () => {
                        page.display.autoBrightnessEnabled = !page.display.autoBrightnessEnabled;
                    })
                }
            }

            // Drives the same setScreenState path as the power key.
            SectionHeader {
                text: qsTr("Display power")
            }
            Actions {
                TestItem {
                    objectName: "blank"
                    text: qsTr("Blank")
                    onClicked: page.app.run("Display power: blank", () => page.display.setScreenState(false))
                }
                TestItem {
                    objectName: "wake"
                    text: qsTr("Wake")
                    onClicked: page.app.run("Display power: wake", () => page.display.setScreenState(true))
                }
                TestItem {
                    objectName: "brightness50"
                    text: qsTr("Brightness 50%")
                    onClicked: page.app.run("Brightness 50%", () => {
                        page.display.brightness = 0.5;
                    })
                }
                TestItem {
                    objectName: "brightness100"
                    text: qsTr("Brightness 100%")
                    onClicked: page.app.run("Brightness 100%", () => {
                        page.display.brightness = 1.0;
                    })
                }
            }

            SectionHeader {
                text: qsTr("Screenshot")
            }
            Actions {
                TestItem {
                    objectName: "screenshot"
                    text: qsTr("Take screenshot")
                    // Shell-only, so in an app this reports failed (tst_testpages).
                    onClicked: page.app.run("Screenshot", () => ScreenshotService.takeScreenshot()) // qmllint disable unqualified
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
