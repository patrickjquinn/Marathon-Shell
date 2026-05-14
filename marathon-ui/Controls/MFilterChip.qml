import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · filter chip (pill).
//
// Active: solid tealBright fill, black text, tealBorder.
// Inactive: transparent fill, secondary text, whiteOverlay08 border.
// 7 px / 14 px padding, radius pill (999), 13 px / 500 label.
//
// Used by the Hub filter row (All · Messages · Mail · Work · Calls)
// but reusable on any pill-chip control.
Rectangle {
    id: chip

    property string label: ""
    property string count: ""              // optional — appended after label
    property bool active: false

    signal activated

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 28
    radius: MRadius.full
    color: active ? MColors.marathonTealBright : "transparent"
    border.width: 1
    border.color: active ? MColors.tealBorder : MColors.whiteOverlay08

    Behavior on color {
        ColorAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: chip.label
            color: chip.active ? "#000000" : MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
            font.weight: MTypography.weightMedium
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: chip.count
            visible: chip.count.length > 0
            color: chip.active ? "#000000" : MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeEyebrow
            font.weight: MTypography.weightDemiBold
            font.features: ({
                    "tnum": 1
                })
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: chip.activated()
        onPressed: chip.scale = 0.96
        onReleased: chip.scale = 1.0
    }
    Behavior on scale {
        NumberAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutBack
        }
    }
}
