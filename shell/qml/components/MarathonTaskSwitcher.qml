import QtQuick
import "../theme"
import "../stores"
import "."

Rectangle {
    id: taskSwitcher
    color: "#000000"
    opacity: 0.95
    
    signal closed()
    signal taskSelected(var task)
    
    MouseArea {
        anchors.fill: parent
        onClicked: closed()
    }
    
    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20
        
        Row {
            width: parent.width
            height: 60
            
            Text {
                text: "Active Frames"
                color: Colors.text
                font.pixelSize: 32
                font.weight: Font.Bold
                font.family: Typography.fontFamily
            }
            
            Item { width: parent.width - 250; height: parent.height }
            
            Rectangle {
                width: 120
                height: 50
                radius: 8
                color: "#333333"
                
                Text {
                    anchors.centerIn: parent
                    text: "Close All"
                    color: Colors.text
                    font.pixelSize: 18
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        AppStore.closeAllApps()
                        closed()
                    }
                }
            }
        }
        
        Item {
            width: parent.width
            height: parent.height - 80
            
            Text {
                visible: AppStore.runningApps.length === 0
                anchors.centerIn: parent
                text: "No running apps"
                color: Colors.textSecondary
                font.pixelSize: 24
                font.family: Typography.fontFamily
            }
            
            GridView {
                visible: AppStore.runningApps.length > 0
                anchors.fill: parent
                cellWidth: width / 2
                cellHeight: 300
                clip: true
                
                model: AppStore.runningApps
                
                delegate: Item {
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 12
                        color: "#1A1A1A"
                        radius: 12
                        border.width: 2
                        border.color: "#333333"
                        
                        Column {
                            anchors.centerIn: parent
                            spacing: 12
                            
                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                source: modelData.icon
                                width: 96
                                height: 96
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                color: Colors.text
                                font.pixelSize: 20
                                font.family: Typography.fontFamily
                            }
                        }
                        
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            width: 32
                            height: 32
                            radius: 16
                            color: "#FF3B30"
                            
                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: "#FFFFFF"
                                font.pixelSize: 24
                                font.weight: Font.Bold
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    console.log("Closing app from Task Switcher:", modelData.id)
                                    AppStore.closeApp(modelData.id)
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                console.log("Switching to app:", modelData.id)
                                AppStore.switchToApp(modelData.id)
                                taskSelected(modelData)
                                closed()
                            }
                        }
                    }
                }
            }
        }
    }
    
    Behavior on opacity {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
    
    scale: visible ? 1.0 : 0.95
    Behavior on scale {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
}
