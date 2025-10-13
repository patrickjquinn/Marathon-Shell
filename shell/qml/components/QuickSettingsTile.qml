import QtQuick
import MarathonOS.Shell

Rectangle {
    id: tile
    
    property var toggleData: ({})
    property real tileWidth: 160
    
    signal tapped()
    signal longPressed()
    
    width: tileWidth
    height: 80
    radius: 4
    border.width: 1
    border.color: toggleData.active ? Colors.accent : Qt.rgba(255, 255, 255, 0.12)
    color: Qt.rgba(255, 255, 255, 0.04)
    
    scale: toggleMouseArea.pressed ? 0.98 : 1.0
    
    Behavior on scale {
        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
    }
    
    Behavior on border.color {
        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
    
    // Teal bar active indicator (BB10 style)
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: 4
        radius: 2
        color: Colors.accent
        visible: toggleData.active
        
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }
    }
    
    // Inner border
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.03)
    }
    
    Row {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        
        Rectangle {
            width: 44
            height: 44
            radius: 3
            color: toggleData.active ? Qt.rgba(0, 102/255, 102/255, 0.15) : Qt.rgba(255, 255, 255, 0.05)
            border.width: 1
            border.color: toggleData.active ? Qt.rgba(0, 102/255, 102/255, 0.3) : Qt.rgba(255, 255, 255, 0.08)
            anchors.verticalCenter: parent.verticalCenter
            
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            
            Behavior on border.color {
                ColorAnimation { duration: 150 }
            }
            
            Icon {
                name: toggleData.icon || "grid"
                color: Colors.text
                size: 24
                anchors.centerIn: parent
            }
        }
        
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            width: parent.width - 68
            
            Text {
                text: toggleData.label || ""
                color: Colors.text
                font.pixelSize: Typography.sizeBody
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                width: parent.width
            }
            
            Text {
                visible: toggleData.subtitle !== undefined && toggleData.subtitle !== ""
                text: toggleData.subtitle || ""
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeXSmall
                elide: Text.ElideRight
                width: parent.width
                opacity: 0.7
            }
        }
    }
    
    MouseArea {
        id: toggleMouseArea
        anchors.fill: parent
        onClicked: {
            tile.tapped()
        }
        onPressAndHold: {
            tile.longPressed()
        }
    }
}

