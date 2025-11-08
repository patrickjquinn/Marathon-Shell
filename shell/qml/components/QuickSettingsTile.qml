import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: tile
    
    property var toggleData: ({})
    property real tileWidth: 160
    property bool isAvailable: toggleData.available !== undefined ? toggleData.available : true
    
    signal tapped()
    signal longPressed()
    
    width: tileWidth
    height: Constants.hubHeaderHeight
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: toggleData.active ? MColors.accentBright : MColors.border
    color: isAvailable ? MColors.surface : Qt.rgba(MColors.surface.r, MColors.surface.g, MColors.surface.b, 0.5)
    antialiasing: Constants.enableAntialiasing
    scale: isPressed ? 0.98 : 1.0
    opacity: isAvailable ? 1.0 : 0.5
    
    Behavior on scale {
        enabled: Constants.enableAnimations
        SpringAnimation { 
            spring: MMotion.springMedium
            damping: MMotion.dampingMedium
            epsilon: MMotion.epsilon
        }
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
        border.color: MColors.borderSubtle
        antialiasing: Constants.enableAntialiasing
    }
    
    // Ripple effect removed - MarathonUI.Effects not available
    // TODO: Add back when MarathonUI is available
    
    Row {
        anchors.fill: parent
        anchors.margins: MSpacing.md
        spacing: MSpacing.md
        
        Item {
            width: Constants.iconSizeMedium + MSpacing.sm
            height: Constants.statusBarHeight
            anchors.verticalCenter: parent.verticalCenter
            
            Icon {
                name: toggleData.icon || "grid"
                color: !isAvailable ? MColors.textSecondary : (toggleData.active ? MColors.accentBright : MColors.text)
                size: Constants.iconSizeMedium
                anchors.centerIn: parent
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
        }
        
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: MSpacing.xs
            width: parent.width - (Constants.iconSizeMedium + MSpacing.md * 3)
            
            MLabel {
                text: toggleData.label || ""
                variant: "body"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                width: parent.width
            }
            
            MLabel {
                visible: toggleData.subtitle !== undefined && toggleData.subtitle !== ""
                text: toggleData.subtitle || ""
                variant: "secondary"
                font.pixelSize: MTypography.sizeXSmall
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
        enabled: isAvailable
        
        onPressed: function(mouse) {
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
            if (!isAvailable) {
                Logger.warn("QuickSettings", "Attempted to toggle unavailable feature: " + toggleData.id)
                return
            }
            tile.tapped()
        }
        
        onPressAndHold: {
            if (!isAvailable) return
            HapticService.medium()
            tile.longPressed()
        }
    }
}

