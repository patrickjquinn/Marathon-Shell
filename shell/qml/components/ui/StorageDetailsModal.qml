import QtQuick
import MarathonOS.Shell

Modal {
    id: storageModal
    title: "Storage"
    
    Column {
        width: parent.width
        spacing: Constants.spacingXLarge
        
        // Total Storage Bar
        Column {
            width: parent.width
            spacing: Constants.spacingSmall
            
            Row {
                width: parent.width
                
                Text {
                    text: "Used"
                    color: Colors.text
                    font.pixelSize: Typography.sizeBody
                    font.family: Typography.fontFamily
                    width: parent.width / 2
                }
                
                Text {
                    text: "45.2 GB of 64 GB"
                    color: Colors.textSecondary
                    font.pixelSize: Typography.sizeSmall
                    font.family: Typography.fontFamily
                    horizontalAlignment: Text.AlignRight
                    width: parent.width / 2
                }
            }
            
            Rectangle {
                width: parent.width
                height: 8
                radius: 4
                color: Colors.backgroundDark
                
                Rectangle {
                    width: parent.width * 0.71 // 45.2/64
                    height: parent.height
                    radius: parent.radius
                    color: Colors.accent
                }
            }
        }
        
        // Storage Breakdown
        Column {
            width: parent.width
            spacing: 0
            
            Repeater {
                model: [
                    { name: "Apps", size: "12.4 GB", color: "#3498db" },
                    { name: "Photos", size: "18.7 GB", color: "#e74c3c" },
                    { name: "Videos", size: "8.3 GB", color: "#9b59b6" },
                    { name: "Music", size: "3.2 GB", color: "#f39c12" },
                    { name: "Documents", size: "2.1 GB", color: "#2ecc71" },
                    { name: "Other", size: "0.5 GB", color: "#95a5a6" }
                ]
                
                Item {
                    width: parent.width
                    height: Constants.statusBarHeight
                    
                    Row {
                        anchors.fill: parent
                        spacing: Constants.spacingMedium
                        
                        Rectangle {
                            width: 12
                            height: 12
                            radius: 2
                            color: modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Text {
                            text: modelData.name
                            color: Colors.text
                            font.pixelSize: Typography.sizeBody
                            font.family: Typography.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 100
                        }
                        
                        Text {
                            text: modelData.size
                            color: Colors.textSecondary
                            font.pixelSize: Typography.sizeSmall
                            font.family: Typography.fontFamily
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                            width: Constants.touchTargetMedium
                        }
                    }
                }
            }
        }
    }
}

