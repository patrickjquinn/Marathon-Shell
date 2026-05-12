import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: root

    property alias text: textInput.text
    property alias placeholderText: placeholder.text
    property bool disabled: false
    property bool error: false
    // Optional screen-reader label distinct from placeholder; callers should
    // set this when the input's purpose isn't already obvious from a visible
    // label adjacent in the layout.
    property string a11yName: placeholderText

    signal accepted

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real innerMargin: Math.max(1, Math.round(1 * scaleFactor))

    implicitWidth: parent ? parent.width : 240
    implicitHeight: MSpacing.touchTargetMin

    Accessible.role: Accessible.EditableText
    Accessible.name: a11yName
    Accessible.description: error ? qsTr("Invalid value") : ""
    Accessible.ignored: disabled
    Accessible.focusable: !disabled
    Accessible.editable: !disabled

    radius: MRadius.md
    color: MColors.bb10Surface
    border.width: borderWidth
    border.color: {
        if (error)
            return MColors.error;
        if (textInput.activeFocus)
            return MColors.marathonTeal;
        return MColors.borderGlass;
    }

    Behavior on border.color {
        ColorAnimation {
            duration: MMotion.xs
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: innerMargin
        radius: parent.radius > innerMargin ? parent.radius - innerMargin : 0
        color: "transparent"
        border.width: borderWidth
        border.color: textInput.activeFocus ? Qt.rgba(0, 191 / 255, 165 / 255, 0.15) : MColors.borderSubtle

        Behavior on border.color {
            ColorAnimation {
                duration: MMotion.xs
            }
        }
    }

    Text {
        id: placeholder
        anchors.left: parent.left
        anchors.leftMargin: MSpacing.md
        anchors.verticalCenter: parent.verticalCenter
        color: MColors.textHint
        font.pixelSize: MTypography.sizeBody
        font.family: MTypography.fontFamily
        visible: textInput.text.length === 0 && !textInput.activeFocus
    }

    TextInput {
        id: textInput
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        verticalAlignment: TextInput.AlignVCenter
        color: disabled ? MColors.textHint : MColors.textPrimary
        selectedTextColor: MColors.textOnAccent
        selectionColor: MColors.marathonTeal
        font.pixelSize: MTypography.sizeBody
        font.family: MTypography.fontFamily
        enabled: !disabled

        onAccepted: root.accepted()
        onTextChanged: root.textChanged()
    }
}
