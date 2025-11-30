import QtQuick
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    id: root

    property string iconSource: ""
    property alias source: buttonImage.source
    property bool disabled: false
    property string state: "default"

    signal clicked
    signal pressed
    signal released

    implicitWidth: buttonImage.implicitWidth
    implicitHeight: buttonImage.implicitHeight

    color: "transparent"

    Image {
        id: buttonImage
        anchors.centerIn: parent
        fillMode: Image.PreserveAspectFit
        opacity: root.disabled ? 0.4 : 1.0

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.xs
            }
        }
    }

    scale: mouseArea.pressed && !disabled ? 0.96 : 1.0

    Behavior on scale {
        SpringAnimation {
            spring: 3.0
            damping: 0.4
            epsilon: 0.001
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !root.disabled && root.state === "default"

        onPressed: function (mouse) {
            root.pressed();
        }
        onReleased: root.released()
        onClicked: root.clicked()
    }
}
