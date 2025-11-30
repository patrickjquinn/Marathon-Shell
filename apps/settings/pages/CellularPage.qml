import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import "../components"

SettingsPageTemplate {
    id: cellularPage
    pageTitle: "Mobile Network"

    property string pageName: "cellular"

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
                visible: typeof CellularManager !== 'undefined'

                MSettingsListItem {
                    title: "Operator"
                    value: (typeof CellularManager !== 'undefined' && CellularManager.operatorName) || "No service"
                }

                MSettingsListItem {
                    title: "Signal Strength"
                    value: (typeof CellularManager !== 'undefined' ? CellularManager.modemSignalStrength + "%" : "N/A")
                }

                MSettingsListItem {
                    title: "Network Type"
                    value: (typeof CellularManager !== 'undefined' && CellularManager.networkType) || "Unknown"
                }
            }

            MSection {
                title: "Mobile Data"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Mobile Data"
                    subtitle: "Use cellular network for data"
                    showToggle: true
                    toggleValue: typeof CellularManager !== 'undefined' ? CellularManager.dataEnabled : false
                    onToggleChanged: value => {
                        if (typeof CellularManager !== 'undefined') {
                            CellularManager.toggleData();
                        }
                    }
                }

                MSettingsListItem {
                    title: "Data Roaming"
                    subtitle: (typeof CellularManager !== 'undefined' && CellularManager.roaming) ? "Currently roaming" : "Use data when traveling"
                    showToggle: true
                    toggleValue: typeof CellularManager !== 'undefined' ? CellularManager.roaming : false
                    visible: typeof CellularManager !== 'undefined'
                }
            }

            MSection {
                title: "SIM Card"
                width: parent.width - 48
                visible: typeof CellularManager !== 'undefined' && CellularManager.simPresent

                MSettingsListItem {
                    title: "SIM Operator"
                    value: (typeof CellularManager !== 'undefined' && CellularManager.simOperator) || "Unknown"
                }

                MSettingsListItem {
                    title: "Phone Number"
                    value: (typeof CellularManager !== 'undefined' && CellularManager.phoneNumber) || "Not available"
                }
            }

            Text {
                width: parent.width - 48
                text: typeof CellularManager === 'undefined' ? "Mobile network features require Linux with ModemManager" : ""
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                visible: typeof CellularManager === 'undefined'
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
