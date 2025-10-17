import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: tile
    
    property var toggleData: ({})
    property real tileWidth: 160
    
    signal tapped()
    signal longPressed()
    
    width: tileWidth
    height: Constants.hubHeaderHeight
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: toggleData.active ? MColors.accentBright : MColors.borderOuter
    color: MColors.surface
    antialiasing: Constants.enableAntialiasing
    
    // NO scale animation - BB10 style
    
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
        radius: Constants.borderRadiusSharp
        color: MColors.accentBright
        visible: toggleData.active
        antialiasing: Constants.enableAntialiasing
        
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }
    }
    
    // Inner border for depth
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Constants.borderRadiusSharp
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MColors.borderInner
        antialiasing: Constants.enableAntialiasing
    }
    
    Row {
        anchors.fill: parent
        anchors.margins: 14
        spacing: Constants.spacingMedium
        
        Item {
            width: 44
            height: Constants.statusBarHeight
            anchors.verticalCenter: parent.verticalCenter
            
            Icon {
                name: toggleData.icon || "grid"
                color: toggleData.active ? MColors.accentBright : MColors.text
                size: Constants.iconSizeMedium
                anchors.centerIn: parent
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
        }
        
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            width: parent.width - 68
            
            Text {
                text: toggleData.label || ""
                color: MColors.text
                font.pixelSize: Typography.sizeBody
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                width: parent.width
            }
            
            Text {
                visible: toggleData.subtitle !== undefined && toggleData.subtitle !== ""
                text: toggleData.subtitle || ""
                color: MColors.textSecondary
                font.pixelSize: Typography.sizeXSmall
                elide: Text.ElideRight
                width: parent.width
                opacity: 0.7
            }
        }
    }
    
    property bool isPressed: false
    
    Rectangle {
        anchors.fill: parent
        color: MColors.accentBright
        opacity: isPressed ? 0.1 : 0
        radius: Constants.borderRadiusSharp
        
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }
    
    MouseArea {
        id: toggleMouseArea
        anchors.fill: parent
        
        onPressed: {
            isPressed = true
            HapticService.light()
        }
        
        onReleased: {
            isPressed = false
        }
        
        onCanceled: {
            isPressed = false
        }
        
        onClicked: {
            tile.tapped()
        }
        
        onPressAndHold: {
            HapticService.medium()
            tile.longPressed()
        }
    }
}

