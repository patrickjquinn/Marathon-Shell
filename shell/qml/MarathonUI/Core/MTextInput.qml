import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: root
    
    property alias text: textInput.text
    property alias placeholderText: placeholder.text
    property alias echoMode: textInput.echoMode
    property alias textInput: textInput
    property bool disabled: false
    property string variant: "default"
    property color backgroundColor: MColors.surface
    
    signal accepted()
    
    implicitWidth: 280
    implicitHeight: Constants.touchTargetMedium
    radius: Constants.borderRadiusSharp
    
    color: backgroundColor
    border.width: Constants.borderWidthThin
    border.color: {
        if (disabled) return MColors.borderLight
        if (textInput.activeFocus) return MColors.accentBright
        return MColors.borderOuter
    }
    
    antialiasing: Constants.enableAntialiasing
    
    Behavior on border.color { 
        enabled: Constants.enableAnimations
        ColorAnimation { duration: Constants.animationFast } 
    }
    
    // Inner border for depth (shell pattern)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Constants.borderRadiusSharp
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MColors.borderInner
        antialiasing: Constants.enableAntialiasing
    }
    
    TextInput {
        id: textInput
        anchors.fill: parent
        anchors.margins: Constants.spacingMedium
        color: disabled ? MColors.textDisabled : MColors.text
        font.pixelSize: Constants.fontSizeMedium
        font.family: MTypography.fontFamily
        verticalAlignment: TextInput.AlignVCenter
        enabled: !root.disabled
        selectByMouse: true
        selectedTextColor: MColors.background
        selectionColor: MColors.accent
        clip: true
        
        onAccepted: root.accepted()
    }
    
    Text {
        id: placeholder
        anchors.fill: parent
        anchors.margins: Constants.spacingMedium
        visible: !textInput.text && !textInput.activeFocus
        color: MColors.textTertiary
        font.pixelSize: Constants.fontSizeMedium
        font.family: MTypography.fontFamily
        verticalAlignment: Text.AlignVCenter
    }
}

