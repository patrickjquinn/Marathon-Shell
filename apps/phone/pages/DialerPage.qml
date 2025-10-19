import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    color: MColors.background
    
    property string dialedNumber: ""
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Constants.spacingMedium
        spacing: Constants.spacingLarge
        
        Item { Layout.preferredHeight: Constants.spacingLarge }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Constants.touchTargetLarge * 1.5
            color: MColors.surface
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthMedium
            border.color: MColors.border
            antialiasing: Constants.enableAntialiasing
            
            Text {
                anchors.centerIn: parent
                text: dialedNumber.length > 0 ? dialedNumber : "🔥 420 BLAZE IT! 🔥"
                font.pixelSize: Constants.fontSizeXLarge
                font.family: "Courier New"
                color: dialedNumber.length > 0 ? MColors.text : MColors.textSecondary
            }
        }
        
        Item { Layout.preferredHeight: Constants.spacingMedium }
        
        Grid {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width
            columns: 3
            columnSpacing: Constants.spacingMedium
            rowSpacing: Constants.spacingMedium
            
            Repeater {
                model: [
                    { digit: "1", letters: "" },
                    { digit: "2", letters: "ABC" },
                    { digit: "3", letters: "DEF" },
                    { digit: "4", letters: "GHI" },
                    { digit: "5", letters: "JKL" },
                    { digit: "6", letters: "MNO" },
                    { digit: "7", letters: "PQRS" },
                    { digit: "8", letters: "TUV" },
                    { digit: "9", letters: "WXYZ" },
                    { digit: "*", letters: "" },
                    { digit: "0", letters: "+" },
                    { digit: "#", letters: "" }
                ]
                
                Rectangle {
                    width: (parent.width - Constants.spacingMedium * 2) / 3
                    height: Constants.touchTargetLarge
                    color: MColors.glass
                    radius: Constants.borderRadiusSharp
                    border.width: Constants.borderWidthMedium
                    border.color: MColors.glassBorder
                    antialiasing: Constants.enableAntialiasing
                    scale: mouseArea.pressed ? 0.95 : 1.0
                    
                    Behavior on scale {
                        SpringAnimation {
                            spring: 2.0
                            damping: 0.25
                            epsilon: 0.01
                        }
                    }
                    
                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                    
                    // Inner border for depth
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Constants.borderWidthThin
                        radius: parent.radius - Constants.borderWidthThin
                        color: "transparent"
                        border.width: Constants.borderWidthThin
                        border.color: MColors.borderInner
                        antialiasing: Constants.enableAntialiasing
                    }
                    
                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.digit
                            font.pixelSize: Constants.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: MColors.text
                        }
                        
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.letters
                            font.pixelSize: Constants.fontSizeXSmall
                            color: MColors.textSecondary
                            visible: modelData.letters.length > 0
                        }
                    }
                    
                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        onPressed: {
                            parent.color = MColors.hover
                            HapticService.light()
                        }
                        onReleased: {
                            parent.color = MColors.glass
                        }
                        onCanceled: {
                            parent.color = MColors.glass
                        }
                        onClicked: {
                            if (modelData.digit === "0" && dialedNumber.length === 0) {
                                dialedNumber = "+"
                            } else {
                                dialedNumber += modelData.digit
                            }
                        }
                    }
                }
            }
        }
        
        Item { Layout.fillHeight: true }
        
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width
            spacing: Constants.spacingLarge
            
            MIconButton {
                icon: "delete"
                size: Constants.touchTargetLarge
                variant: "secondary"
                disabled: dialedNumber.length === 0
                onClicked: {
                    if (dialedNumber.length > 0) {
                        dialedNumber = dialedNumber.slice(0, -1)
                    }
                }
            }
            
            MButton {
                text: "Call"
                iconName: "phone"
                iconLeft: true
                variant: "primary"
                size: "large"
                disabled: dialedNumber.length === 0
                implicitWidth: Constants.touchTargetLarge * 2
                onClicked: {
                    console.log("Calling:", dialedNumber)
                }
            }
        }
    }
}

