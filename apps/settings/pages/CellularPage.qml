pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    readonly property bool ready: Modem.available && Modem.simPresent

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Mobile network")
            }
            TextSwitch {
                objectName: "dataSwitch"
                visible: page.ready
                text: qsTr("Mobile data")
                description: qsTr("Use the mobile network for internet")
                automaticCheck: false
                checked: Modem.dataEnabled
                onClicked: Modem.dataEnabled ? Modem.disableData() : Modem.enableData()
            }
            TextSwitch {
                objectName: "roamingSwitch"
                visible: page.ready
                text: qsTr("Data roaming")
                description: qsTr("Use mobile data on other operators' networks, such as abroad. Charges may apply.")
                automaticCheck: false
                checked: Modem.dataRoamingAllowed
                onClicked: Modem.setDataRoamingAllowed(!Modem.dataRoamingAllowed)
            }
            ComboBox {
                objectName: "modeCombo"
                width: parent.width
                visible: page.ready && Modem.supportedModes.length > 1
                label: qsTr("Preferred network type")
                Binding on currentIndex {
                    value: Modem.supportedModes.indexOf(Modem.allowedModes)
                }
                menu: ContextMenu {
                    Repeater {
                        model: Modem.supportedModes

                        MenuItem {
                            required property int modelData

                            text: Logic.networkModeTitle(modelData)
                            onClicked: Modem.setAllowedModes(modelData)
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Status")
                visible: page.ready
            }
            DetailItem {
                objectName: "operatorItem"
                visible: page.ready
                label: qsTr("Operator")
                value: Modem.registered && Modem.operatorName !== "" ? Modem.operatorName : qsTr("No service")
            }
            DetailItem {
                objectName: "networkItem"
                visible: page.ready && Modem.registered && Modem.networkType !== "" && Modem.networkType !== "Unknown"
                label: qsTr("Network")
                value: Modem.networkType
            }
            DetailItem {
                objectName: "signalItem"
                visible: page.ready && Modem.registered
                label: qsTr("Signal")
                value: Logic.signalQuality(Modem.signalStrength)
            }
            DetailItem {
                objectName: "roamingItem"
                visible: page.ready && Modem.registered
                label: qsTr("Roaming")
                value: Modem.roaming ? qsTr("Roaming") : qsTr("Home network")
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: !page.ready
            text: !Modem.available ? qsTr("No modem found") : qsTr("No SIM card")
            hintText: !Modem.available ? qsTr("This device has no mobile modem, or it is switched off") : qsTr("Insert a SIM card to use the mobile network")
        }

        VerticalScrollDecorator {}
    }
}
