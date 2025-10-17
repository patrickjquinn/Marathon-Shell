import QtQuick
import MarathonUI.Theme

Item {
    id: root
    
    property bool checked: false
    property bool disabled: false
    
    signal toggled()
    
    implicitWidth: 52
    implicitHeight: 32
    
    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: checked ? MColors.accent : MColors.surface
        border.width: 1
        border.color: checked ? MColors.accent : MColors.border
        
        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }
        
        Rectangle {
            id: thumb
            x: checked ? parent.width - width - 4 : 4
            y: 4
            width: 24
            height: 24
            radius: Constants.borderRadiusMedium
            color: MColors.text
            
            Behavior on x {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
        }
    }
    
    MouseArea {
        anchors.fill: parent
        enabled: !disabled
        onClicked: {
            checked = !checked
            root.toggled()
        }
    }
}

