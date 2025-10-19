import QtQuick
import MarathonUI.Theme

Item {
    id: ripple
    
    property point origin: Qt.point(width / 2, height / 2)
    property bool active: false
    property color rippleColor: MColors.ripple
    
    anchors.fill: parent
    clip: true
    
    Rectangle {
        id: rippleCircle
        width: 0
        height: 0
        radius: width / 2
        x: ripple.origin.x - width / 2
        y: ripple.origin.y - height / 2
        color: ripple.rippleColor
        opacity: 0
        
        states: State {
            name: "active"
            when: ripple.active
            PropertyChanges {
                target: rippleCircle
                width: Math.max(ripple.width, ripple.height) * 2.5  // MMotion.rippleMaxRadius
                height: width
                opacity: 0
            }
        }
        
        transitions: Transition {
            from: ""
            to: "active"
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { 
                        target: rippleCircle
                        properties: "width,height" 
                        from: 0
                        duration: 400  // MMotion.rippleDuration
                        easing.type: Easing.OutQuint  // MMotion.easingDecelerate
                    }
                    NumberAnimation { 
                        target: rippleCircle
                        property: "opacity"
                        from: 0.12  // MMotion.rippleOpacity
                        to: 0
                        duration: 400  // MMotion.rippleDuration
                        easing.type: Easing.Linear  // MMotion.easingLinear
                    }
                }
                ScriptAction { 
                    script: {
                        ripple.active = false
                        rippleCircle.width = 0
                        rippleCircle.height = 0
                    }
                }
            }
        }
    }
    
    function trigger(point) {
        if (point) {
            origin = point
        }
        active = true
    }
}

