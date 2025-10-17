import QtQuick
import MarathonOS.Shell

Rectangle {
    id: root
    
    property real value: 0.0
    property real from: 0.0
    property real to: 1.0
    property bool indeterminate: false
    
    readonly property real progress: (value - from) / (to - from)
    
    implicitWidth: 200
    implicitHeight: 6
    
    color: MElevation.getSurface(0)
    radius: height / 2
    border.width: Constants.borderWidthThin
    border.color: MElevation.getBorderOuter(0)
    antialiasing: Constants.enableAntialiasing
    
    Rectangle {
        id: progressFill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Constants.borderWidthThin
        width: root.indeterminate ? parent.width * 0.3 : (parent.width - Constants.borderWidthThin * 2) * Math.max(0, Math.min(1, root.progress))
        radius: parent.radius - Constants.borderWidthThin
        color: MColors.accent
        antialiasing: Constants.enableAntialiasing
        
        Behavior on width {
            enabled: Constants.enableAnimations && !root.indeterminate
            SmoothedAnimation { velocity: 200 }
        }
        
        SequentialAnimation {
            running: root.indeterminate && Constants.enableAnimations
            loops: Animation.Infinite
            
            NumberAnimation {
                target: progressFill
                property: "x"
                from: 0
                to: root.width - progressFill.width - Constants.borderWidthThin * 2
                duration: 1000
                easing.type: Easing.InOutCubic
            }
            
            NumberAnimation {
                target: progressFill
                property: "x"
                from: root.width - progressFill.width - Constants.borderWidthThin * 2
                to: 0
                duration: 1000
                easing.type: Easing.InOutCubic
            }
        }
    }
}

