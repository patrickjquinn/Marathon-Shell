import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// White for photos, red for video; a square stops recording or the self-timer.
MouseArea {
    id: root

    property bool video
    property bool recording
    property bool timing
    readonly property bool stopGlyph: recording || timing

    width: Theme.itemSizeExtraLarge
    height: width
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: timing ? qsTr("Cancel timer") : !video ? qsTr("Take photo") : recording ? qsTr("Stop recording") : qsTr("Start recording")
    Accessible.onPressAction: root.clicked(null)
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true;
            root.clicked(null);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Math.round(Theme.paddingSmall)
        border.color: root.recording ? Theme.errorColor : Theme.lightPrimaryColor
    }

    Rectangle {
        objectName: "shutterFill"
        anchors.centerIn: parent
        width: root.stopGlyph ? Theme.iconSizeMedium : root.width - 3 * Theme.paddingMedium
        height: width
        radius: root.stopGlyph ? Theme.paddingSmall : width / 2
        color: root.video ? Theme.errorColor : Theme.lightPrimaryColor
        opacity: root.pressed ? Theme.opacityHigh : 1

        Behavior on width {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
        Behavior on radius {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
    }

    FocusFrame {
        parent: root
        radius: width / 2
    }
}
