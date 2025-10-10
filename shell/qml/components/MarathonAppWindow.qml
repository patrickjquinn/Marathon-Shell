import QtQuick
import "../theme"
import "../stores"
import "."

Rectangle {
    id: appWindow
    anchors.fill: parent
    color: "#1A1A1A"
    visible: false
    z: 500
    
    property string appId: ""
    property string appName: ""
    property string appIcon: ""
    
    signal closed()
    signal minimized()
    
    function show(id, name, icon) {
        appId = id
        appName = name
        appIcon = icon
        visible = true
        slideIn.start()
        console.log("📱 Showing app window for:", name)
    }
    
    function hide() {
        slideOut.start()
    }
    
    NumberAnimation {
        id: slideIn
        target: appWindow
        property: "opacity"
        from: 0.0
        to: 1.0
        duration: 300
        easing.type: Easing.OutCubic
    }
    
    NumberAnimation {
        id: slideOut
        target: appWindow
        property: "opacity"
        from: 1.0
        to: 0.0
        duration: 300
        easing.type: Easing.InCubic
        onFinished: {
            appWindow.visible = false
            closed()
        }
    }
    
    Column {
        anchors.fill: parent
        
        Rectangle {
            id: appBar
            width: parent.width
            height: 60
            color: Colors.surface
            
            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: Colors.accent
                    anchors.verticalCenter: parent.verticalCenter
                    
                    Icon {
                        name: "chevron-down"
                        size: 24
                        color: "#FFFFFF"
                        anchors.centerIn: parent
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: minimized()
                    }
                }
                
                Text {
                    text: appName
                    color: Colors.text
                    font.pixelSize: Typography.sizeLarge
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Item {
                    width: parent.width - 500
                    height: 1
                }
                
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: Colors.error
                    anchors.verticalCenter: parent.verticalCenter
                    
                    Icon {
                        name: "x"
                        size: 24
                        color: "#FFFFFF"
                        anchors.centerIn: parent
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            AppStore.closeApp(appId)
                            hide()
                        }
                    }
                }
            }
        }
        
        Rectangle {
            width: parent.width
            height: parent.height - appBar.height
            color: "#000000"
            
            Column {
                anchors.centerIn: parent
                spacing: 24
                
                Image {
                    source: appIcon
                    width: 128
                    height: 128
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Text {
                    text: appName
                    color: "#FFFFFF"
                    font.pixelSize: 32
                    font.weight: Font.Bold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Text {
                    text: "App is running..."
                    color: "#888888"
                    font.pixelSize: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}

