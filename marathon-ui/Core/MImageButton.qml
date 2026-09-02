import MarathonUI.Theme
import QtQuick

Rectangle {
    id: root

    property string iconSource: ""
    property alias source: buttonImage.source
    property bool disabled: false
    // Named controlState, not state: `state` is QQuickItem's own property, the
    // one the States/Transitions system selects on. Shadowing it silently
    // disables that machinery for this component and for anything that
    // subclasses it.
    property string controlState: "default"
    // Override at the call site with a meaningful label (e.g. "Lock device").
    property string a11yName: ""

    signal clicked
    signal pressed
    signal released

    implicitWidth: buttonImage.implicitWidth
    implicitHeight: buttonImage.implicitHeight
    color: "transparent"
    Accessible.role: Accessible.Button
    Accessible.name: a11yName.length > 0 ? a11yName : (iconSource.length > 0 ? iconSource : "Button")
    Accessible.onPressAction: {
        if (!disabled && controlState === "default") {
            clicked();
        }
    }
    scale: mouseArea.pressed && !disabled ? 0.96 : 1

    Image {
        id: buttonImage

        anchors.centerIn: parent
        fillMode: Image.PreserveAspectFit
        opacity: root.disabled ? 0.4 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.xs
            }
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        enabled: !root.disabled && root.controlState === "default"
        onPressed: function (mouse) {
            root.pressed();
        }
        onReleased: root.released()
        onClicked: root.clicked()
    }

    Behavior on scale {
        SpringAnimation {
            spring: 3
            damping: 0.4
            epsilon: 0.001
        }
    }
}
