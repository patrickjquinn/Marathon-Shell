import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
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
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            Section {
                title: "Status"
                width: parent.width - 48
                visible: typeof CellularManager !== 'undefined'
                
                SettingsListItem {
                    title: "Operator"
                    value: (typeof CellularManager !== 'undefined' && CellularManager.operatorName) || "No service"
                }
                
                SettingsListItem {
                    title: "Signal Strength"
                    value: (typeof CellularManager !== 'undefined' ? CellularManager.modemSignalStrength + "%" : "N/A")
                }
                
                SettingsListItem {
                    title: "Network Type"
                    value: (typeof CellularManager !== 'undefined' && CellularManager.networkType) || "Unknown"
                }
            }
            
            Section {
                title: "Mobile Data"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Mobile Data"
                    subtitle: "Use cellular network for data"
                    showToggle: true
                    toggleValue: typeof CellularManager !== 'undefined' ? CellularManager.dataEnabled : false
                    onToggleChanged: (value) => {
                        if (typeof CellularManager !== 'undefined') {
                            CellularManager.toggleData()
                        }
                    }
                }
                
                SettingsListItem {
                    title: "Data Roaming"
                    subtitle: CellularManager.roaming ? "Currently roaming" : "Use data when traveling"
                    showToggle: true
                    toggleValue: typeof CellularManager !== 'undefined' ? CellularManager.roaming : false
                    visible: typeof CellularManager !== 'undefined'
                }
            }
            
            Section {
                title: "SIM Card"
                width: parent.width - 48
                visible: typeof CellularManager !== 'undefined' && CellularManager.simPresent
                
                SettingsListItem {
                    title: "SIM Operator"
                    value: (typeof CellularManager !== 'undefined' && CellularManager.simOperator) || "Unknown"
                }
                
                SettingsListItem {
                    title: "Phone Number"
                    value: (typeof CellularManager !== 'undefined' && CellularManager.phoneNumber) || "Not available"
                }
            }
            
            Text {
                width: parent.width - 48
                text: typeof CellularManager === 'undefined' ? "Mobile network features require Linux with ModemManager" : ""
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeSmall
                font.family: Typography.fontFamily
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                visible: typeof CellularManager === 'undefined'
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}

