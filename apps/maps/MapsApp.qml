import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers

MApp {
    id: mapsApp
    appId: "maps"
    appName: "Maps"
    appIcon: "assets/icon.svg"
    
    content: Rectangle {
        anchors.fill: parent
        color: Colors.background
        
        Column {
            anchors.centerIn: parent
            spacing: Constants.spacingLarge
            
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "map"
                size: Constants.iconSizeXLarge * 2
                color: Colors.accent
            }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Maps"
                color: Colors.text
                font.pixelSize: Constants.fontSizeXLarge
                font.weight: Font.Bold
            }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Location viewer and navigation\nComing soon"
                color: Colors.textSecondary
                font.pixelSize: Constants.fontSizeMedium
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}

