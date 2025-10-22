import QtQuick
import MarathonOS.Shell

Rectangle {
    id: root
    
    property string text: ""
    property bool checked: false
    property string group: ""
    
    signal clicked()
    signal toggled(bool checked)
    
    implicitWidth: row.implicitWidth
    implicitHeight: Constants.touchTargetSmall
    color: "transparent"
    
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingSmall
        
        Rectangle {
            id: indicator
            width: Constants.iconSizeMedium
            height: Constants.iconSizeMedium
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            
            color: MElevation.getSurface(0)
            border.width: Constants.borderWidthMedium
            border.color: root.checked ? MColors.accent : MColors.border
            antialiasing: true
            
            Behavior on border.color {
                enabled: Constants.enableAnimations
                ColorAnimation { duration: Constants.animationFast }
            }
            
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.5
                height: parent.height * 0.5
                radius: width / 2
                color: MColors.accent
                visible: root.checked
                scale: root.checked ? 1.0 : 0.0
                antialiasing: true
                
                Behavior on scale {
                    enabled: Constants.enableAnimations
                    NumberAnimation { 
                        duration: Constants.animationFast
                        easing.type: Easing.OutBack
                        easing.overshoot: 2
                    }
                }
            }
        }
        
        Text {
            text: root.text
            font.pixelSize: Constants.fontSizeMedium
            color: MColors.text
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!root.checked) {
                root.checked = true
                root.toggled(true)
                root.clicked()
                
                if (root.group !== "") {
                    var siblings = root.parent.children
                    for (var i = 0; i < siblings.length; i++) {
                        if (siblings[i] !== root && 
                            siblings[i].group === root.group &&
                            typeof siblings[i].checked !== 'undefined') {
                            siblings[i].checked = false
                        }
                    }
                }
            }
        }
    }
}

