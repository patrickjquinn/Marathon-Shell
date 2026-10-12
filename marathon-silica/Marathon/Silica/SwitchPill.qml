import QtQuick
import Sailfish.Silica as S

// The on/off pill that Marathon's switches show at the end of their row.
Rectangle {
    id: pill

    // The switch it belongs to, for its state and palette.
    property Item control

    objectName: "toggle"
    width: Math.round(S.Theme.itemSizeExtraSmall * 0.75)
    height: Math.round(width * 0.56)
    radius: height / 2
    opacity: control.enabled ? 1 : S.Theme.opacityLow
    color: control.checked ? S.Theme.rgba(control.palette.highlightColor, control.highlighted ? 0.6 : 0.45)
                           : S.Theme.rgba(control.palette.primaryColor, control.highlighted ? 0.3 : 0.2)

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Rectangle {
        readonly property real inset: Math.round(pill.height * 0.12)

        objectName: "toggleKnob"
        width: pill.height - inset * 2
        height: width
        radius: width / 2
        y: inset
        x: pill.control.checked ? pill.width - width - inset : inset
        color: pill.control.checked ? pill.control.palette.highlightColor : pill.control.palette.primaryColor

        SequentialAnimation on opacity {
            running: pill.control.busy
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: S.Theme.opacityLow; duration: 450 }
            NumberAnimation { to: 1; duration: 450 }
        }
        Behavior on x {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }
}
