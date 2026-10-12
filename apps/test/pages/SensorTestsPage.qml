pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../components"

Page {
    id: page

    property var app
    readonly property var sensors: typeof Sensors !== "undefined" ? Sensors : null
    readonly property var location: typeof Location !== "undefined" ? Location : null
    // Shell-only; absent in the app runner.
    readonly property var flashlight: typeof FlashlightManagerCpp !== "undefined" ? FlashlightManagerCpp : null

    function yesNo(yes) {
        return yes ? qsTr("Yes") : qsTr("No");
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Sensors & location")
                description: page.app.summary
            }

            SectionHeader {
                text: qsTr("Ambient light sensor")
            }
            Column {
                width: parent.width

                DetailItem {
                    label: qsTr("Available")
                    value: page.yesNo(page.sensors && page.sensors.available)
                }
                DetailItem {
                    objectName: "light"
                    label: qsTr("Light level")
                    value: qsTr("%1 lux").arg(page.sensors ? page.sensors.ambientLight : 0)
                }
            }

            SectionHeader {
                text: qsTr("Proximity sensor")
            }
            Column {
                width: parent.width

                DetailItem {
                    label: qsTr("Available")
                    value: page.yesNo(page.sensors && page.sensors.available)
                }
                DetailItem {
                    objectName: "near"
                    label: qsTr("Near")
                    value: page.yesNo(page.sensors && page.sensors.proximityNear)
                }
            }

            SectionHeader {
                text: qsTr("Location service")
            }
            Column {
                width: parent.width

                DetailItem {
                    objectName: "locationActive"
                    label: qsTr("Active")
                    value: page.yesNo(page.location && page.location.active)
                }
                DetailItem {
                    label: qsTr("Latitude")
                    value: page.location ? page.location.latitude.toFixed(6) : "-"
                }
                DetailItem {
                    label: qsTr("Longitude")
                    value: page.location ? page.location.longitude.toFixed(6) : "-"
                }
                DetailItem {
                    label: qsTr("Accuracy")
                    value: page.location ? qsTr("%1 m").arg(page.location.accuracy) : "-"
                }
            }
            Actions {
                TestItem {
                    objectName: "locationStart"
                    text: qsTr("Start")
                    onClicked: page.app.run("Start location", () => page.location.start())
                }
                TestItem {
                    objectName: "locationStop"
                    text: qsTr("Stop")
                    onClicked: page.app.run("Stop location", () => page.location.stop())
                }
            }

            SectionHeader {
                text: qsTr("Flashlight")
            }
            DetailItem {
                label: qsTr("Status")
                value: page.flashlight && page.flashlight.enabled ? qsTr("On") : qsTr("Off")
            }
            Actions {
                TestItem {
                    objectName: "flashlight"
                    text: qsTr("Toggle")
                    onClicked: page.app.run("Toggle flashlight", () => page.flashlight.toggle())
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
