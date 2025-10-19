import QtQuick
import MarathonOS.Shell

Item {
    id: root
    
    property int size: Constants.iconSizeLarge
    property color color: MColors.accent
    property bool running: true
    property int speed: 1000
    
    implicitWidth: size
    implicitHeight: size
    
    Repeater {
        model: 8
        
        Rectangle {
            id: bar
            x: root.size / 2 - width / 2
            y: root.size / 2 - height / 2
            width: root.size * 0.15
            height: root.size * 0.35
            radius: width / 2
            color: root.color
            opacity: 0.3 + (index / 8) * 0.7
            antialiasing: Constants.enableAntialiasing
            
            transform: Rotation {
                origin.x: bar.width / 2
                origin.y: root.size / 2 - bar.y
                angle: index * 45
            }
        }
    }
    
    RotationAnimation {
        target: root
        property: "rotation"
        from: 0
        to: 360
        duration: root.speed
        loops: Animation.Infinite
        running: root.running && Constants.enableAnimations
    }
}

