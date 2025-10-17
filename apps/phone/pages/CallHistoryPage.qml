import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    color: MColors.background
    
    ListView {
        id: historyList
        anchors.fill: parent
        anchors.margins: Constants.spacingMedium
        spacing: Constants.spacingSmall
        clip: true
        
        model: phoneApp.callHistory
        
        delegate: Rectangle {
            width: historyList.width
            height: Constants.touchTargetLarge
            color: MColors.surface
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthThin
            border.color: MColors.border
            antialiasing: Constants.enableAntialiasing
            
            Row {
                anchors.fill: parent
                anchors.margins: Constants.spacingMedium
                spacing: Constants.spacingMedium
                
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.type === "incoming" ? "phone-incoming" : 
                          modelData.type === "outgoing" ? "phone-outgoing" : "phone-missed"
                    size: Constants.iconSizeMedium
                    color: modelData.type === "missed" ? MColors.error : MColors.accent
                }
                
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.spacing * 3 - Constants.iconSizeMedium * 2
                    spacing: Constants.spacingXSmall
                    
                    Text {
                        width: parent.width
                        text: modelData.contactName
                        font.pixelSize: Constants.fontSizeMedium
                        font.weight: Font.DemiBold
                        color: MColors.text
                        elide: Text.ElideRight
                    }
                    
                    Row {
                        spacing: Constants.spacingSmall
                        
                        Text {
                            text: modelData.phone
                            font.pixelSize: Constants.fontSizeSmall
                            color: MColors.textSecondary
                        }
                        
                        Text {
                            text: "•"
                            font.pixelSize: Constants.fontSizeSmall
                            color: MColors.textSecondary
                            visible: modelData.duration > 0
                        }
                        
                        Text {
                            text: formatDuration(modelData.duration)
                            font.pixelSize: Constants.fontSizeSmall
                            color: MColors.textSecondary
                            visible: modelData.duration > 0
                        }
                    }
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: formatTimestamp(modelData.timestamp)
                    font.pixelSize: Constants.fontSizeSmall
                    color: MColors.textTertiary
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
                    console.log("Call back:", modelData.phone)
                }
            }
        }
        
        Text {
            anchors.centerIn: parent
            visible: historyList.count === 0
            text: "No call history"
            font.pixelSize: Constants.fontSizeLarge
            color: MColors.textSecondary
        }
    }
    
    function formatDuration(seconds) {
        var mins = Math.floor(seconds / 60)
        var secs = seconds % 60
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }
    
    function formatTimestamp(timestamp) {
        var now = Date.now()
        var diff = now - timestamp
        
        if (diff < 1000 * 60 * 60) {
            return Math.floor(diff / (1000 * 60)) + "m ago"
        } else if (diff < 1000 * 60 * 60 * 24) {
            return Math.floor(diff / (1000 * 60 * 60)) + "h ago"
        } else {
            return Math.floor(diff / (1000 * 60 * 60 * 24)) + "d ago"
        }
    }
}

