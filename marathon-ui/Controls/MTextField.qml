import QtQuick
import QtQuick.Controls
import MarathonUI.Theme
import MarathonOS.Shell

// Single-line text field with DS chrome — label above, rounded surface
// underneath, teal focus accent. Used by Mail compose (To/Cc/Subject)
// and Mail IMAP setup; pattern is reusable for any future form field.
//
// API mirrors the QtQuick.Controls TextField conventions plus a `label`
// slot and a `placeholder` alias (so callers don't need to learn the
// upstream "placeholderText" key). `text` is read+write and binds two-way
// like a TextField; `enabled` controls whether the user can interact.
Item {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property alias text: field.text
    property alias placeholder: field.placeholderText
    property alias echoMode: field.echoMode
    property alias inputMethodHints: field.inputMethodHints
    property alias validator: field.validator
    property string label: ""

    // Read-only flag mirrored from the inner TextField so callers can
    // bind to `focus` semantics without reaching inside.
    readonly property bool focused: field.activeFocus

    implicitWidth: parent ? parent.width : 240
    implicitHeight: labelLabel.implicitHeight + (root.label !== "" ? 4 : 0) + Math.max(44, field.implicitHeight + 16)

    Text {
        id: labelLabel
        visible: root.label !== ""
        text: root.label
        color: MColors.textSecondary
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeFootnote
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
    }

    Rectangle {
        id: surface
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.label !== "" ? labelLabel.bottom : parent.top
        anchors.topMargin: root.label !== "" ? 4 : 0
        height: Math.max(44, field.implicitHeight + 16)
        radius: MRadius.md
        color: root.enabled ? MColors.bb10Surface : Qt.rgba(0, 0, 0, 0.2)
        border.width: 1
        border.color: field.activeFocus ? MColors.marathonTeal : MColors.borderGlass

        TextField {
            id: field
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            color: MColors.textPrimary
            placeholderTextColor: MColors.textTertiary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeBody
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            // Drop the upstream FrameStyle — we draw the surround ourselves.
            background: null
            enabled: root.enabled
        }
    }
}
