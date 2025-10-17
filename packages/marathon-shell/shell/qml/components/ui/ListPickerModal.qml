import QtQuick
import MarathonOS.Shell

Modal {
    id: listPickerModal
    
    property var options: []
    property int selectedIndex: 0
    
    signal selected(int index, string value)
    
    Column {
        width: parent.width
        spacing: 0
        
        Repeater {
            model: options
            
            Rectangle {
                width: parent.width
                height: 56
                color: "transparent"
                radius: 4
                
                // Glass morphism hover effect
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(255, 255, 255, 0.02)
                    opacity: itemMouseArea.pressed ? 1 : 0
                    border.width: 1
                    border.color: Qt.rgba(255, 255, 255, 0.04)
                    radius: parent.radius
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
                
                // Press feedback
                Rectangle {
                    anchors.fill: parent
                    color: Colors.accent
                    opacity: itemMouseArea.pressed ? 0.05 : 0
                    radius: parent.radius
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }
                }
                
                transform: Translate {
                    y: itemMouseArea.pressed ? -2 : 0
                    
                    Behavior on y {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: Constants.spacingMedium
                    
                    Text {
                        text: modelData
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        font.weight: index === selectedIndex ? Font.DemiBold : Font.Normal
                        font.family: Typography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28
                    }
                    
                    Rectangle {
                        visible: index === selectedIndex
                        width: 20
                        height: Constants.navBarHeight
                        radius: 4
                        color: Colors.accent
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: Colors.text
                            anchors.centerIn: parent
                        }
                    }
                }
                
                Rectangle {
                    visible: index < options.length - 1
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Constants.spacingMedium
                    height: 1
                    color: Qt.rgba(255, 255, 255, 0.08)
                }
                
                MouseArea {
                    id: itemMouseArea
                    anchors.fill: parent
                    
                    
                    onClicked: {
                        selectedIndex = index
                        listPickerModal.selected(index, modelData)
                        listPickerModal.close()
                    }
                }
            }
        }
    }
}

