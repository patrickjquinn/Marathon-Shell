import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers

MApp {
    id: galleryApp
    appId: "gallery"
    appName: "Gallery"
    appIcon: "assets/icon.svg"
    
    content: Rectangle {
        anchors.fill: parent
        color: Colors.background
        
        Column {
            anchors.centerIn: parent
            spacing: Constants.spacingLarge
            
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "image"
                size: Constants.iconSizeXLarge * 2
                color: Colors.accent
            }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Gallery"
                color: Colors.text
                font.pixelSize: Constants.fontSizeXLarge
                font.weight: Font.Bold
            }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Photo and video browser\nComing soon"
                color: Colors.textSecondary
                font.pixelSize: Constants.fontSizeMedium
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}

