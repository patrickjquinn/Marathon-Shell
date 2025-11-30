import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: root

    property alias text: textArea.text
    property alias placeholderText: placeholder.text
    property bool disabled: false
    property bool error: false
    property int wrapMode: TextEdit.Wrap

    signal accepted

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real innerMargin: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real defaultHeight: Math.round(120 * scaleFactor)

    implicitWidth: parent ? parent.width : 240
    implicitHeight: defaultHeight

    radius: MRadius.md
    color: MColors.bb10Surface
    border.width: borderWidth
    border.color: {
        if (error)
            return MColors.error;
        if (textArea.activeFocus)
            return MColors.marathonTeal;
        return Qt.rgba(1, 1, 1, 0.08);
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
        border.color: textArea.activeFocus ? Qt.rgba(0, 191 / 255, 165 / 255, 0.15) : Qt.rgba(1, 1, 1, 0.04)

        Behavior on border.color {
            ColorAnimation {
                duration: MMotion.xs
            }
        }
    }

    Text {
        id: placeholder
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: MSpacing.md
        anchors.topMargin: MSpacing.md
        color: MColors.textHint
        font.pixelSize: MTypography.sizeBody
        font.family: MTypography.fontFamily
        visible: textArea.text.length === 0 && !textArea.activeFocus
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: MSpacing.md
        contentHeight: textArea.contentHeight
        clip: true

        TextEdit {
            id: textArea
            width: parent.width
            color: disabled ? MColors.textHint : MColors.textPrimary
            selectedTextColor: MColors.textOnAccent
            selectionColor: MColors.marathonTeal
            font.pixelSize: MTypography.sizeBody
            font.family: MTypography.fontFamily
            wrapMode: root.wrapMode
            enabled: !disabled
        }
    }
}
