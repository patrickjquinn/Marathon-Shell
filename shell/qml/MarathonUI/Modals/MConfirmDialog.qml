import QtQuick
import MarathonOS.Shell

MModal {
    id: root
    
    property string message: ""
    property string confirmText: "Confirm"
    property string cancelText: "Cancel"
    
    content: [
        Column {
            width: parent.width
            spacing: Constants.spacingLarge
            
            Text {
                text: root.message
                font.pixelSize: Constants.fontSizeMedium
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
                width: parent.width
            }
            
            Row {
                spacing: Constants.spacingMedium
                anchors.right: parent.right
                
                MButton {
                    text: root.cancelText
                    variant: "secondary"
                    onClicked: root.closed()
                }
                
                MButton {
                    text: root.confirmText
                    variant: "primary"
                    onClicked: {
                        root.accepted()
                        root.closed()
                    }
                }
            }
        }
    ]
}

