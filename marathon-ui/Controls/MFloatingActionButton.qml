import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

// The page's create action. Anchor it bottom-right, inside the thumb zone.
Item {
    id: root

    required property string label
    property string iconName: "plus"

    signal clicked

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    implicitWidth: Math.round(64 * scaleFactor)
    implicitHeight: Math.round(64 * scaleFactor)

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: clicked()

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: mouseArea.pressed ? MColors.accentDark : MColors.accent
        scale: mouseArea.pressed ? 0.94 : 1

        Behavior on scale {
            enabled: !MMotion.reduceMotion

            NumberAnimation {
                duration: MMotion.micro
            }
        }

        Icon {
            anchors.centerIn: parent
            name: root.iconName
            size: Math.round(28 * root.scaleFactor)
            weight: "bold"
            color: MColors.textOnAccent
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        anchors.margins: -Math.round(8 * root.scaleFactor)
        onClicked: {
            MHaptics.light();
            root.clicked();
        }
    }
}
