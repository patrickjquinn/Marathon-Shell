import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: root

    property string title: "Terminal"
    property bool active: false
    property bool canClose: true

    signal clicked
    signal closeClicked

    width: 160
    height: 36
    color: active ? MColors.accent : MColors.elevated
    radius: Constants.borderRadiusSmall
    border.width: 1
    border.color: active ? MColors.accentBright : MColors.border

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.xs
        spacing: MSpacing.xs

        Icon {
            name: "terminal"
            size: 16
            color: active ? "black" : MColors.text
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.title
            font.pixelSize: MTypography.sizeBody
            font.weight: active ? MTypography.weightDemiBold : MTypography.weightNormal
            font.family: MTypography.fontFamily
            color: active ? "black" : MColors.text
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        MIconButton {
            iconName: "x"
            iconSize: 12
            implicitWidth: 24
            implicitHeight: 24
            variant: "ghost"
            visible: root.canClose
            onClicked: root.closeClicked()
            Layout.alignment: Qt.AlignVCenter
            iconColor: active ? "black" : MColors.text
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: {
            root.clicked();
            HapticService.light();
        }
    }
}
