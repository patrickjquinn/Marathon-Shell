import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    // No platform service exposes the modem yet; the page shows it if one appears.
    readonly property var modem: typeof ModemManagerCpp !== "undefined" ? ModemManagerCpp : null
    readonly property bool available: modem !== null && modem.available === true

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
                text: qsTr("Mobile data")
                description: qsTr("Use the mobile network for data")
                enabled: page.available
                automaticCheck: false
                checked: page.available && page.modem.dataEnabled === true
                onClicked: {
                    if (page.modem.dataEnabled)
                        page.modem.disableData();
                    else
                        page.modem.enableData();
                }
            }

            SectionHeader {
                text: qsTr("Status")
                visible: page.available
            }
            DetailItem {
                visible: page.available
                label: qsTr("Operator")
                value: (page.available && page.modem.operatorName) || qsTr("No service")
            }
            DetailItem {
                visible: page.available
                label: qsTr("Signal strength")
                value: page.available ? page.modem.signalStrength + "%" : ""
            }
            DetailItem {
                visible: page.available
                label: qsTr("Network type")
                value: (page.available && page.modem.networkType) || qsTr("Unknown")
            }
            DetailItem {
                visible: page.available
                label: qsTr("Roaming")
                value: page.available && page.modem.roaming ? qsTr("Roaming") : qsTr("Home network")
            }
            DetailItem {
                visible: page.available && page.modem.simPresent === true
                label: qsTr("SIM operator")
                value: (page.available && page.modem.operatorName) || qsTr("Unknown")
            }

            InfoLabel {
                objectName: "noModem"
                topPadding: Theme.paddingLarge * 2
                visible: !page.available
                text: qsTr("No modem found")
                font.pixelSize: Theme.fontSizeLarge
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !page.available
                text: qsTr("Check that a SIM card is inserted and the modem is switched on.")
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }
        }

        VerticalScrollDecorator {}
    }
}
