import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Modal {
    id: textInputModal
    
    property alias inputText: textInput.text
    property string placeholderText: ""
    
    signal accepted(string text)
    
    Column {
        width: parent.width
        spacing: Constants.spacingMedium
        
        Rectangle {
            width: parent.width
            height: 48
            color: Colors.backgroundDark
            radius: 4
            border.width: textInput.activeFocus ? 2 : 1
            border.color: textInput.activeFocus ? Colors.accent : Qt.rgba(255, 255, 255, 0.1)
            
            Behavior on border.color {
                ColorAnimation { duration: Constants.animationDurationFast }
            }
            
            TextInput {
                id: textInput
                anchors.fill: parent
                anchors.margins: 12
                color: Colors.text
                font.pixelSize: Typography.sizeBody
                font.family: Typography.fontFamily
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                
                Text {
                    visible: !textInput.text && !textInput.activeFocus
                    text: placeholderText
                    color: Colors.textTertiary
                    font: textInput.font
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
        
        Row {
            width: parent.width
            height: Constants.statusBarHeight
            spacing: Constants.spacingMedium
            z: 10
            
            Rectangle {
                width: (parent.width - 12) / 2
                height: Constants.statusBarHeight
                color: Colors.surfaceLight
                radius: 4
                border.width: 1
                border.color: Qt.rgba(255, 255, 255, 0.08)
                
                transform: Translate {
                    y: cancelMouseArea.pressed ? -2 : 0
                }
                
                Behavior on border.color {
                    ColorAnimation { duration: 200 }
                }
                
                Text {
                    text: "Cancel"
                    color: Colors.text
                    font.pixelSize: Typography.sizeBody
                    font.family: Typography.fontFamily
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: cancelMouseArea
                    anchors.fill: parent
                    
                    
                    z: 20
                    onClicked: {
                        console.log("Cancel clicked")
                        textInputModal.close()
                    }
                }
            }
            
            Rectangle {
                width: (parent.width - 12) / 2
                height: Constants.statusBarHeight
                radius: 4
                border.width: 1
                border.color: Qt.rgba(20, 184, 166, 0.4)
                
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(20, 184, 166, 0.78) }
                    GradientStop { position: 1.0; color: Qt.rgba(20, 184, 166, 0.35) }
                }
                
                transform: Translate {
                    y: saveMouseArea.pressed ? -2 : 0
                }
                
                Behavior on border.color {
                    ColorAnimation { duration: 200 }
                }
                
                // Glow effect on hover
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: saveMouseArea.pressed ? 1 : 0
                    border.color: Qt.rgba(20, 184, 166, 0.3)
                    opacity: saveMouseArea.pressed ? 1 : 0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }
                
                Text {
                    text: "Save"
                    color: Colors.text
                    font.pixelSize: Typography.sizeBody
                    font.weight: Font.DemiBold
                    font.family: Typography.fontFamily
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: saveMouseArea
                    anchors.fill: parent
                    
                    
                    z: 20
                    onClicked: {
                        console.log("Save clicked, text:", textInput.text)
                        textInputModal.accepted(textInput.text)
                        textInputModal.close()
                    }
                }
            }
        }
    }
}

