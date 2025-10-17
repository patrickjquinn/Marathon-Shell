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
                text: dialedNumber.length > 0 ? dialedNumber : "Enter number"
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
                    color: MColors.surface
                    radius: Constants.borderRadiusSharp
                    border.width: Constants.borderWidthMedium
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing
                    
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
                        anchors.fill: parent
                        onPressed: {
                            parent.color = MColors.surface2
                            HapticService.light()
                        }
                        onReleased: {
                            parent.color = MColors.surface
                        }
                        onCanceled: {
                            parent.color = MColors.surface
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
            
            Rectangle {
                width: Constants.touchTargetLarge
                height: Constants.touchTargetLarge
                color: MColors.surface
                radius: Constants.borderRadiusSharp
                border.width: Constants.borderWidthMedium
                border.color: dialedNumber.length > 0 ? MColors.border : MColors.borderLight
                opacity: dialedNumber.length > 0 ? 1.0 : 0.5
                antialiasing: Constants.enableAntialiasing
                
                Icon {
                    anchors.centerIn: parent
                    name: "delete"
                    size: Constants.iconSizeMedium
                    color: MColors.text
                }
                
                MouseArea {
                    anchors.fill: parent
                    enabled: dialedNumber.length > 0
                    onPressed: {
                        if (enabled) {
                            parent.color = MColors.surface2
                            HapticService.light()
                        }
                    }
                    onReleased: {
                        parent.color = MColors.surface
                    }
                    onCanceled: {
                        parent.color = MColors.surface
                    }
                    onClicked: {
                        if (dialedNumber.length > 0) {
                            dialedNumber = dialedNumber.slice(0, -1)
                        }
                    }
                }
            }
            
            Rectangle {
                width: Constants.touchTargetLarge * 2
                height: Constants.touchTargetLarge
                color: dialedNumber.length > 0 ? MColors.accent : MColors.surface
                radius: Constants.borderRadiusSharp
                border.width: Constants.borderWidthMedium
                border.color: dialedNumber.length > 0 ? MColors.accentDark : MColors.border
                opacity: dialedNumber.length > 0 ? 1.0 : 0.5
                antialiasing: Constants.enableAntialiasing
                
                Row {
                    anchors.centerIn: parent
                    spacing: Constants.spacingSmall
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "phone"
                        size: Constants.iconSizeMedium
                        color: dialedNumber.length > 0 ? MColors.text : MColors.textSecondary
                    }
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Call"
                        font.pixelSize: Constants.fontSizeLarge
                        font.weight: Font.DemiBold
                        color: dialedNumber.length > 0 ? MColors.text : MColors.textSecondary
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    enabled: dialedNumber.length > 0
                    onPressed: {
                        if (enabled) {
                            parent.color = MColors.accentDim
                            HapticService.medium()
                        }
                    }
                    onReleased: {
                        parent.color = MColors.accent
                    }
                    onCanceled: {
                        parent.color = MColors.accent
                    }
                    onClicked: {
                        console.log("Calling:", dialedNumber)
                    }
                }
            }
        }
    }
}

