import QtQuick
import QtQuick.Controls
import "../theme"
import "../stores"
import "."

Rectangle {
    id: quickSettings
    color: "#000000"
    opacity: 0.98
    
    signal closed()
    
    property real dragStartY: 0
    property bool isDragging: false
    
    MouseArea {
        anchors.fill: parent
        z: -1
        propagateComposedEvents: true
        
        onPressed: (mouse) => {
            dragStartY = mouse.y
            isDragging = false
        }
        
        onPositionChanged: (mouse) => {
            if (Math.abs(mouse.y - dragStartY) > 10) {
                isDragging = true
            }
            if (isDragging && (mouse.y - dragStartY) < -50) {
                closed()
            }
        }
        
        onReleased: {
            if (isDragging && (dragStartY > 0)) {
                closed()
            }
            isDragging = false
            dragStartY = 0
        }
    }
    
    Flickable {
        id: scrollView
        anchors.fill: parent
        anchors.margins: 20
        anchors.bottomMargin: 80
        contentHeight: contentColumn.height
        clip: true
        
        Column {
            id: contentColumn
            width: parent.width
            spacing: 20
        
        Text {
            text: "Quick Settings"
            color: Colors.text
            font.pixelSize: Typography.sizeLarge
            font.weight: Font.Bold
        }
        
        Grid {
            width: parent.width
            columns: 2
            spacing: 12
            
            // WiFi Toggle
            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 110
                radius: Colors.cornerRadiusMedium
                color: SystemControlStore.isWifiOn ? Colors.accent : Colors.surface
                border.width: 1
                border.color: SystemControlStore.isWifiOn ? Colors.accentLight : Colors.border
                
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }
                
                scale: wifiMouseArea.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
                
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.1) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.1) }
                    }
                }
                
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    Icon {
                        name: "wifi"
                        color: Colors.text
                        size: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    Text {
                        text: "Wi-Fi"
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                
                MouseArea {
                    id: wifiMouseArea
                    anchors.fill: parent
                    onClicked: SystemControlStore.toggleWifi()
                }
            }
            
            // Bluetooth Toggle
            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 110
                radius: Colors.cornerRadiusMedium
                color: SystemControlStore.isBluetoothOn ? Colors.accent : Colors.surface
                
                Behavior on color { ColorAnimation { duration: 200 } }
                
                scale: bluetoothMouseArea.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
                
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    Icon {
                        name: "bluetooth"
                        color: Colors.text
                        size: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    Text {
                        text: "Bluetooth"
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                
                MouseArea {
                    id: bluetoothMouseArea
                    anchors.fill: parent
                    onClicked: SystemControlStore.toggleBluetooth()
                }
            }
            
            // Airplane Mode Toggle
            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 110
                radius: Colors.cornerRadiusMedium
                color: SystemControlStore.isAirplaneModeOn ? Colors.accent : Colors.surface
                
                Behavior on color { ColorAnimation { duration: 200 } }
                
                scale: airplaneMouseArea.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
                
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    Icon {
                        name: "plane"
                        color: Colors.text
                        size: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    Text {
                        text: "Airplane"
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                
                MouseArea {
                    id: airplaneMouseArea
                    anchors.fill: parent
                    onClicked: SystemControlStore.toggleAirplaneMode()
                }
            }
            
            // Rotation Lock Toggle
            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 110
                radius: Colors.cornerRadiusMedium
                color: SystemControlStore.isRotationLocked ? Colors.accent : Colors.surface
                
                Behavior on color { ColorAnimation { duration: 200 } }
                
                scale: rotationMouseArea.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
                
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    Icon {
                        name: "rotate-ccw"
                        color: Colors.text
                        size: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    Text {
                        text: "Rotation"
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                
                MouseArea {
                    id: rotationMouseArea
                    anchors.fill: parent
                    onClicked: SystemControlStore.toggleRotationLock()
                }
            }
            
            // Flashlight Toggle
            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 110
                radius: Colors.cornerRadiusMedium
                color: SystemControlStore.isFlashlightOn ? Colors.accent : Colors.surface
                
                Behavior on color { ColorAnimation { duration: 200 } }
                
                scale: flashlightMouseArea.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
                
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    Icon {
                        name: "zap"
                        color: Colors.text
                        size: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    Text {
                        text: "Flashlight"
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                
                MouseArea {
                    id: flashlightMouseArea
                    anchors.fill: parent
                    onClicked: SystemControlStore.toggleFlashlight()
                }
            }
            
            // Alarm Toggle
            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 110
                radius: Colors.cornerRadiusMedium
                color: SystemControlStore.isAlarmOn ? Colors.accent : Colors.surface
                
                Behavior on color { ColorAnimation { duration: 200 } }
                
                scale: alarmMouseArea.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
                
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    Icon {
                        name: "bell"
                        color: Colors.text
                        size: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    Text {
                        text: "Alarm"
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                
                MouseArea {
                    id: alarmMouseArea
                    anchors.fill: parent
                    onClicked: SystemControlStore.toggleAlarm()
                }
            }
        }
        
        // Brightness Slider
        Rectangle {
            width: parent.width
            height: 60
            radius: 12
            color: Colors.surface
            
            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                
                Icon {
                    name: "sun"
                    color: Colors.text
                    size: 24
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Slider {
                    id: brightnessSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56
                    from: 0
                    to: 100
                    value: SystemControlStore.brightness
                    onValueChanged: {
                        if (pressed) {
                            SystemControlStore.setBrightness(value)
                        }
                    }
                    
                    background: Rectangle {
                        x: brightnessSlider.leftPadding
                        y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                        implicitWidth: 200
                        implicitHeight: 4
                        width: brightnessSlider.availableWidth
                        height: implicitHeight
                        radius: 2
                        color: Colors.textTertiary
                        
                        Rectangle {
                            width: brightnessSlider.visualPosition * parent.width
                            height: parent.height
                            color: Colors.accent
                            radius: 2
                        }
                    }
                    
                    handle: Rectangle {
                        x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                        y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                        implicitWidth: 20
                        implicitHeight: 20
                        radius: 10
                        color: brightnessSlider.pressed ? Qt.lighter(Colors.accent, 1.2) : Colors.accent
                        border.color: Colors.text
                        border.width: 1
                    }
                }
            }
        }
        
        // Volume Slider
        Rectangle {
            width: parent.width
            height: 60
            radius: 12
            color: Colors.surface
            
            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                
                Icon {
                    name: "volume-2"
                    color: Colors.text
                    size: 24
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Slider {
                    id: volumeSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56
                    from: 0
                    to: 100
                    value: SystemControlStore.volume
                    onValueChanged: {
                        if (pressed) {
                            SystemControlStore.setVolume(value)
                        }
                    }
                    
                    background: Rectangle {
                        x: volumeSlider.leftPadding
                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                        implicitWidth: 200
                        implicitHeight: 4
                        width: volumeSlider.availableWidth
                        height: implicitHeight
                        radius: 2
                        color: Colors.textTertiary
                        
                        Rectangle {
                            width: volumeSlider.visualPosition * parent.width
                            height: parent.height
                            color: Colors.accent
                            radius: 2
                        }
                    }
                    
                    handle: Rectangle {
                        x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                        implicitWidth: 20
                        implicitHeight: 20
                        radius: 10
                        color: volumeSlider.pressed ? Qt.lighter(Colors.accent, 1.2) : Colors.accent
                        border.color: Colors.text
                        border.width: 1
                    }
                }
            }
        }
        }
    }
    
    // Drag handle at bottom
    Rectangle {
        id: dragHandle
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 16
        width: 120
        height: 60
        radius: Colors.cornerRadiusMedium
        color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, 0.8)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
        z: 100
        
        Rectangle {
            anchors.centerIn: parent
            width: 60
            height: 4
            radius: 2
            color: Colors.textTertiary
        }
        
        Icon {
            name: "chevron-up"
            color: Colors.text
            size: 32
            anchors.centerIn: parent
        }
        
        MouseArea {
            id: handleArea
            anchors.fill: parent
            property real startY: 0
            property bool wasDragged: false
            
            onPressed: (mouse) => {
                startY = mouse.y
                wasDragged = false
            }
            
            onPositionChanged: (mouse) => {
                if (Math.abs(mouse.y - startY) > 10) {
                    wasDragged = true
                }
                if (mouse.y - startY < -50) {
                    closed()
                }
            }
            
            onReleased: (mouse) => {
                if (!wasDragged) {
                    closed()
                }
            }
        }
    }
}

