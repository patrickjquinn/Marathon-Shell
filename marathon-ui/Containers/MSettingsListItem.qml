import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Controls

Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    property string iconName: ""
    property string value: ""
    property bool showChevron: false
    property bool showToggle: false
    property bool toggleValue: false

    signal settingClicked
    signal toggleChanged(bool value)

    width: parent ? parent.width : 0
    height: subtitle !== "" ? 72 : 56
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, 0.02)
        opacity: mouseArea.pressed ? 1 : 0
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.04)
        radius: MRadius.sm

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: MColors.marathonTeal
        opacity: mouseArea.pressed ? 0.05 : 0
        radius: MRadius.sm

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.micro
                easing.type: Easing.OutCubic
            }
        }
    }

    transform: Translate {
        y: mouseArea.pressed && !showToggle ? -2 : 0

        Behavior on y {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: MSpacing.md

        Icon {
            id: iconImage
            visible: iconName !== ""
            name: iconName
            size: 24
            color: MColors.textPrimary
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            id: titleColumn
            anchors.left: iconImage.visible ? iconImage.right : parent.left
            anchors.leftMargin: iconImage.visible ? MSpacing.md : 0
            anchors.right: rightContent.left
            anchors.rightMargin: MSpacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: MSpacing.xs

            Text {
                text: title
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeBody
                font.weight: MTypography.weightDemiBold
                font.family: MTypography.fontFamily
                elide: Text.ElideRight
                width: parent.width
            }

            Text {
                visible: subtitle !== ""
                text: subtitle
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                elide: Text.ElideRight
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                opacity: 0.7
            }
        }

        Item {
            id: rightContent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: showToggle ? 76 : showChevron ? (valueText.visible ? valueText.width + 36 : 20) : (valueText.visible ? valueText.width : 0)
            height: parent.height

            MToggle {
                id: toggle
                visible: showToggle
                checked: toggleValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onToggled: {
                    root.toggleChanged(checked);
                }
            }

            Text {
                id: valueText
                visible: value !== "" && !showToggle
                text: value
                color: MColors.textTertiary
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                anchors.right: chevronIcon.visible ? chevronIcon.left : parent.right
                anchors.rightMargin: chevronIcon.visible ? MSpacing.md : 0
                anchors.verticalCenter: parent.verticalCenter
            }

            Icon {
                id: chevronIcon
                visible: showChevron && !showToggle
                name: "chevron-down"
                size: 16
                color: MColors.textSecondary
                rotation: -90
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: iconName !== "" ? 56 : MSpacing.md
        height: 1
        color: Qt.rgba(1, 1, 1, 0.08)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !showToggle

        onClicked: {
            root.settingClicked();
        }
    }
}
