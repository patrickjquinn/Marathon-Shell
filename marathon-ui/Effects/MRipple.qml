import QtQuick
import MarathonUI.Theme

Item {
    id: root

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
        x: root.origin.x - width / 2
        y: root.origin.y - height / 2
        color: root.rippleColor
        opacity: 0

        states: State {
            name: "active"
            when: root.active
            PropertyChanges {
                target: rippleCircle
                width: Math.max(root.width, root.height) * MMotion.rippleMaxRadius
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
                        duration: MMotion.rippleDuration
                        easing.bezierCurve: MMotion.easingDecelerateCurve
                    }
                    NumberAnimation {
                        target: rippleCircle
                        property: "opacity"
                        from: MMotion.rippleOpacity
                        to: 0
                        duration: MMotion.rippleDuration
                        easing.type: Easing.Linear
                    }
                }
                ScriptAction {
                    script: {
                        root.active = false;
                        rippleCircle.width = 0;
                        rippleCircle.height = 0;
                    }
                }
            }
        }
    }

    function trigger(point) {
        if (point) {
            origin = point;
        }
        active = true;
    }
}
