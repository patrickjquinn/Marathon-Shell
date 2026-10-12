import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Silica TextField look: no box, an underline in primary that turns
// highlight on focus, placeholder in secondary.
Rectangle {
    id: root

    property alias text: textInput.text
    property alias placeholderText: placeholder.text
    property bool disabled: false
    property bool error: false
    // Screen-reader label when the purpose isn't obvious from nearby text.
    property string a11yName: placeholderText

    signal accepted

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))

    implicitWidth: parent ? parent.width : 240
    implicitHeight: Silica.Theme.itemSizeSmall

    Accessible.role: Accessible.EditableText
    Accessible.name: a11yName
    Accessible.description: error ? qsTr("Invalid value") : ""
    Accessible.ignored: disabled
    Accessible.focusable: !disabled
    Accessible.editable: !disabled

    color: "transparent"

    Rectangle {
        id: underline
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Silica.Theme.paddingSmall
        anchors.rightMargin: Silica.Theme.paddingSmall
        height: textInput.activeFocus ? root.borderWidth * 2 : root.borderWidth
        color: {
            if (root.error)
                return Silica.Theme.errorColor;
            if (textInput.activeFocus)
                return Silica.Theme.highlightColor;
            return Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35);
        }

        Behavior on color {
            ColorAnimation {
                duration: MMotion.xs
            }
        }
    }

    Text {
        id: placeholder
        anchors.left: parent.left
        anchors.leftMargin: Silica.Theme.paddingSmall
        anchors.verticalCenter: parent.verticalCenter
        color: textInput.activeFocus ? Silica.Theme.secondaryHighlightColor : Silica.Theme.secondaryColor
        font.pixelSize: Silica.Theme.fontSizeMedium
        font.family: Silica.Theme.fontFamily
        visible: textInput.text.length === 0 && textInput.preeditText.length === 0
    }

    TextInput {
        id: textInput
        anchors.fill: parent
        anchors.leftMargin: Silica.Theme.paddingSmall
        anchors.rightMargin: Silica.Theme.paddingSmall
        verticalAlignment: TextInput.AlignVCenter
        color: root.disabled ? Silica.Theme.secondaryColor : Silica.Theme.primaryColor
        selectedTextColor: Silica.Theme.highlightColor
        selectionColor: Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity)
        font.pixelSize: Silica.Theme.fontSizeMedium
        font.family: Silica.Theme.fontFamily
        enabled: !root.disabled

        onAccepted: root.accepted()
        onTextChanged: root.textChanged()
    }
}
