import QtQuick
import QtQuick.Controls
import "../Theme"

Rectangle {
    id: root
    
    property alias text: textInput.text
    property alias placeholderText: placeholder.text
    property alias echoMode: textInput.echoMode
    property bool disabled: false
    property string variant: "default"
    
    signal accepted()
    signal textChanged()
    
    implicitWidth: 280
    implicitHeight: 48
    radius: MRadius.md
    
    color: MColors.glass
    border.width: 1
    border.color: {
        if (disabled) return MColors.border
        if (textInput.activeFocus) return MColors.accent
        return MColors.glassBorder
    }
    
    Behavior on border.color { ColorAnimation { duration: 200 } }
    
    Row {
        anchors.fill: parent
        anchors.margins: MSpacing.md
        spacing: MSpacing.sm
        
        TextInput {
            id: textInput
            width: parent.width
            height: parent.height
            color: disabled ? MColors.textDisabled : MColors.text
            font.pixelSize: MTypography.sizeBody
            font.family: MTypography.fontFamily
            verticalAlignment: TextInput.AlignVCenter
            enabled: !root.disabled
            selectByMouse: true
            selectedTextColor: MColors.background
            selectionColor: MColors.accent
            clip: true
            
            onAccepted: root.accepted()
            onTextChanged: root.textChanged()
        }
        
        Text {
            id: placeholder
            visible: !textInput.text && !textInput.activeFocus
            color: MColors.textTertiary
            font.pixelSize: MTypography.sizeBody
            font.family: MTypography.fontFamily
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}

