import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Item {
    id: toggle
    width: Constants.touchTargetSmall
    height: 32
    
    property bool checked: false
    signal toggled(bool value)
    
    Rectangle {
        id: track
        anchors.fill: parent
        radius: Constants.borderRadiusSharp
        border.width: Constants.borderWidthThin
        border.color: checked ? MColors.accentBright : MColors.borderOuter
        color: checked ? MColors.surface2 : MColors.surface
        antialiasing: Constants.enableAntialiasing
        
        Behavior on border.color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Constants.borderRadiusSharp
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MColors.borderInner
            antialiasing: Constants.enableAntialiasing
        }
    }
    
    Rectangle {
        id: switchHandle
        anchors.verticalCenter: parent.verticalCenter
        x: checked ? parent.width - width - 2 : 2
        width: 28
        height: 28
        radius: Constants.borderRadiusSharp
        color: MColors.text
        border.width: Constants.borderWidthThin
        border.color: MColors.borderShadow
        antialiasing: Constants.enableAntialiasing
        
        // NO scale animation - BB10 style
        
        Behavior on x {
            NumberAnimation { 
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -8
        onClicked: {
            checked = !checked
            toggled(checked)
        }
    }
}

