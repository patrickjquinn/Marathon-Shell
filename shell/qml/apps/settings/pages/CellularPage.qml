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
                title: "Mobile Data"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Mobile Data"
                    subtitle: "Use cellular network for data"
                    showToggle: true
                    toggleValue: true
                }
                
                SettingsListItem {
                    title: "Data Roaming"
                    subtitle: "Use data when traveling"
                    showToggle: true
                    toggleValue: false
                }
            }
            
            Section {
                title: "Carrier"
                width: parent.width - 48
                
                SettingsListItem {
                    title: "Carrier"
                    value: "Auto"
                }
                
                SettingsListItem {
                    title: "Network Type"
                    value: "4G LTE"
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
}

