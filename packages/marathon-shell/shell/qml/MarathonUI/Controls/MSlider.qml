import QtQuick
import MarathonOS.Shell
import QtQuick.Controls
import MarathonUI.Theme

Slider {
    id: root
    
    from: 0
    to: 100
    value: 50
    
    implicitWidth: 280
    implicitHeight: 48
    
    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth
        height: 6
        radius: Constants.borderRadiusSharp
        color: MColors.glass
        border.width: 1
        border.color: MColors.border
        
        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: parent.radius
            color: MColors.accent
        }
    }
    
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: 24
        height: 24
        radius: Constants.borderRadiusSharp
        color: MColors.accent
        border.width: 1
        border.color: MColors.text
    }
}

