import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: dialog
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.85)
    visible: false
    z: 1000
    
    property int editingAlarmId: -1
    property bool isEditMode: false
    
    signal alarmCreated(int hour, int minute)
    signal alarmUpdated(int alarmId, int hour, int minute)
    
    function open() {
        isEditMode = false
        editingAlarmId = -1
        hourTumbler.currentIndex = new Date().getHours()
        minuteTumbler.currentIndex = new Date().getMinutes()
        dialog.visible = true
    }
    
    function openForEdit(alarmId, hour, minute, label) {
        isEditMode = true
        editingAlarmId = alarmId
        hourTumbler.currentIndex = hour
        minuteTumbler.currentIndex = minute
        dialog.visible = true
    }
    
    function close() {
        dialog.visible = false
    }
    
    MouseArea {
        anchors.fill: parent
        onClicked: dialog.close()
    }
    
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, 400)
        height: 400
        color: MColors.surface2
        radius: Constants.borderRadiusSharp
        border.width: Constants.borderWidthThin
        border.color: MColors.border
        
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }
        
        Column {
            anchors.fill: parent
            anchors.margins: Constants.spacingLarge
            spacing: Constants.spacingLarge
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: isEditMode ? "Edit Alarm" : "Set Alarm Time"
                font.pixelSize: Constants.fontSizeLarge
                font.weight: Font.Bold
                color: MColors.text
            }
            
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Constants.spacingMedium
                
                Tumbler {
                    id: hourTumbler
                    width: 100
                    height: 200
                    model: 24
                    delegate: Text {
                        text: modelData.toString().padStart(2, '0')
                        font.pixelSize: Constants.fontSizeLarge
                        color: MColors.text
                        opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ":"
                    font.pixelSize: Constants.fontSizeXLarge
                    font.weight: Font.Bold
                    color: MColors.text
                }
                
                Tumbler {
                    id: minuteTumbler
                    width: 100
                    height: 200
                    model: 60
                    delegate: Text {
                        text: modelData.toString().padStart(2, '0')
                        font.pixelSize: Constants.fontSizeLarge
                        color: MColors.text
                        opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            
            Item { height: Constants.spacingLarge }
            
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Constants.spacingMedium
                
                MButton {
                    text: "Cancel"
                    variant: "secondary"
                    onClicked: dialog.close()
                }
                
                MButton {
                    text: "Save"
                    variant: "primary"
                    onClicked: {
                        if (isEditMode) {
                            dialog.alarmUpdated(editingAlarmId, hourTumbler.currentIndex, minuteTumbler.currentIndex)
                        } else {
                            dialog.alarmCreated(hourTumbler.currentIndex, minuteTumbler.currentIndex)
                        }
                        dialog.close()
                    }
                }
            }
        }
    }
}

