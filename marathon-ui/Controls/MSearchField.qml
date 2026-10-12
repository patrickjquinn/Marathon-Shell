import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: "Search"

    signal accepted

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    function clear() {
        input.clear();
    }

    function focusInput() {
        input.forceActiveFocus();
    }

    implicitHeight: Math.round(44 * scaleFactor)
    radius: height / 2
    color: MColors.elev2
    border.width: 1
    border.color: input.activeFocus ? MColors.accent : MColors.border

    Accessible.role: Accessible.EditableText
    Accessible.name: placeholder

    MouseArea {
        anchors.fill: parent
        onClicked: {
            input.forceActiveFocus();
            Qt.inputMethod.show(); // qmllint disable missing-property
        }
    }

    Icon {
        id: glass

        anchors.left: parent.left
        anchors.leftMargin: MSpacing.md
        anchors.verticalCenter: parent.verticalCenter
        name: "magnifying-glass"
        size: Math.round(18 * root.scaleFactor)
        color: MColors.textSecondary
    }

    TextInput {
        id: input

        anchors.left: glass.right
        anchors.leftMargin: MSpacing.sm
        anchors.right: clearButton.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        color: MColors.textPrimary
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeBody
        selectionColor: MColors.accent
        clip: true
        inputMethodHints: Qt.ImhNoPredictiveText
        onAccepted: root.accepted()

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            text: root.placeholder
            color: MColors.textSecondary
            font: input.font
            visible: input.text.length === 0 && input.preeditText.length === 0
        }
    }

    Item {
        id: clearButton

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? root.height : 0
        height: root.height
        visible: input.text.length > 0

        Accessible.role: Accessible.Button
        Accessible.name: "Clear search"
        Accessible.onPressAction: input.clear()

        Icon {
            anchors.centerIn: parent
            name: "x"
            size: Math.round(16 * root.scaleFactor)
            color: MColors.textSecondary
        }

        MouseArea {
            anchors.fill: parent
            onClicked: input.clear()
        }
    }
}
