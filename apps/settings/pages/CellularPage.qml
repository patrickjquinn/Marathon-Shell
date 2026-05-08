pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: cellularPage

    property string pageName: "cellular"

    pageTitle: "Mobile Network"

    content: Flickable {
        contentHeight: cellularContent.height + 40
        clip: true

        Column {
            id: cellularContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Status"
                width: parent.width - 48
                visible: ModemManagerCpp.available

                MSettingsListItem {
                    title: "Operator"
                    value: ModemManagerCpp.operatorName || "No service"
                }

                MSettingsListItem {
                    title: "Signal Strength"
                    value: ModemManagerCpp.signalStrength + "%"
                }

                MSettingsListItem {
                    title: "Network Type"
                    value: ModemManagerCpp.networkType || "Unknown"
                }
            }

            MSection {
                title: "Mobile Data"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Mobile Data"
                    subtitle: "Use cellular network for data"
                    showToggle: true
                    toggleValue: ModemManagerCpp.dataEnabled
                    onToggleChanged: value => {
                        if (ModemManagerCpp.dataEnabled)
                            ModemManagerCpp.disableData();
                        else
                            ModemManagerCpp.enableData();
                    }
                }

                MSettingsListItem {
                    title: "Data Roaming"
                    subtitle: ModemManagerCpp.roaming ? "Currently roaming" : "Use data when traveling"
                    showToggle: true
                    toggleValue: ModemManagerCpp.roaming
                    enabled: false
                    visible: ModemManagerCpp.available
                }
            }

            MSection {
                title: "SIM Card"
                width: parent.width - 48
                visible: ModemManagerCpp.simPresent

                MSettingsListItem {
                    title: "SIM Operator"
                    value: ModemManagerCpp.operatorName || "Unknown"
                }

                MSettingsListItem {
                    title: "Phone Number"
                    value: "Not available"
                }
            }

            Text {
                width: parent.width - 48
                text: !ModemManagerCpp.available ? "Mobile network features require Linux with ModemManager" : ""
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                visible: !ModemManagerCpp.available
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
