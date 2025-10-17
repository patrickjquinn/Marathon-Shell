import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

MApp {
    id: phoneApp
    appId: "phone"
    appName: "Phone"
    appIcon: "assets/icon.svg"
    
    property var contacts: [
        { id: 1, name: "Alice Johnson", phone: "+1 (555) 123-4567", favorite: true },
        { id: 2, name: "Bob Smith", phone: "+1 (555) 234-5678", favorite: false },
        { id: 3, name: "Carol Williams", phone: "+1 (555) 345-6789", favorite: true },
        { id: 4, name: "David Brown", phone: "+1 (555) 456-7890", favorite: false },
        { id: 5, name: "Emma Davis", phone: "+1 (555) 567-8901", favorite: true }
    ]
    
    property var callHistory: [
        { id: 1, contactName: "Alice Johnson", phone: "+1 (555) 123-4567", type: "outgoing", timestamp: Date.now() - 1000 * 60 * 15, duration: 180 },
        { id: 2, contactName: "Bob Smith", phone: "+1 (555) 234-5678", type: "incoming", timestamp: Date.now() - 1000 * 60 * 60 * 2, duration: 420 },
        { id: 3, contactName: "Unknown", phone: "+1 (555) 999-8888", type: "missed", timestamp: Date.now() - 1000 * 60 * 60 * 4, duration: 0 },
        { id: 4, contactName: "Carol Williams", phone: "+1 (555) 345-6789", type: "outgoing", timestamp: Date.now() - 1000 * 60 * 60 * 24, duration: 600 },
        { id: 5, contactName: "David Brown", phone: "+1 (555) 456-7890", type: "incoming", timestamp: Date.now() - 1000 * 60 * 60 * 24 * 2, duration: 120 }
    ]
    
    property string dialedNumber: ""
    
    function formatTimestamp(timestamp) {
        var now = Date.now()
        var diff = now - timestamp
        var minutes = Math.floor(diff / (1000 * 60))
        var hours = Math.floor(diff / (1000 * 60 * 60))
        var days = Math.floor(diff / (1000 * 60 * 60 * 24))
        
        if (minutes < 60) return minutes + "m"
        if (hours < 24) return hours + "h"
        return days + "d"
    }
    
    function formatDuration(seconds) {
        var minutes = Math.floor(seconds / 60)
        var remainingSeconds = seconds % 60
        return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds
    }
    
    function addDigit(digit) {
        dialedNumber += digit
        HapticService.light()
    }
    
    function deleteDigit() {
        if (dialedNumber.length > 0) {
            dialedNumber = dialedNumber.slice(0, -1)
            HapticService.light()
        }
    }
    
    function clearNumber() {
        dialedNumber = ""
        HapticService.light()
    }
    
    function makeCall() {
        if (dialedNumber.length > 0) {
            console.log("Calling:", dialedNumber)
            HapticService.medium()
            // TODO: Actually make the call
        }
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            property int currentIndex: 0
            
            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentIndex
                
                // Dialer Page
                Rectangle {
                    color: MColors.background
                    
                    Column {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingLarge
                        spacing: Constants.spacingLarge
                        
                        // Display
                        Rectangle {
                            width: parent.width
                            height: Constants.touchTargetLarge
                            color: MColors.surface
                            radius: Constants.borderRadiusSharp
                            border.width: Constants.borderWidthThin
                            border.color: MColors.border
                            antialiasing: Constants.enableAntialiasing
                            
                            Text {
                                anchors.centerIn: parent
                                text: dialedNumber || "Enter number"
                                font.pixelSize: Constants.fontSizeLarge
                                font.weight: Font.DemiBold
                                color: dialedNumber ? MColors.text : MColors.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        
                        // Keypad
                        Grid {
                            width: parent.width
                            height: parent.height - Constants.touchTargetLarge - Constants.touchTargetLarge - Constants.spacingLarge * 3
                            columns: 3
                            rows: 4
                            spacing: Constants.spacingSmall
                            
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
                                    width: (parent.width - parent.spacing * 2) / 3
                                    height: (parent.height - parent.spacing * 3) / 4
                                    color: "transparent"
                                    border.width: Constants.borderWidthThin
                                    border.color: MColors.border
                                    radius: Constants.borderRadiusSharp
                                    antialiasing: Constants.enableAntialiasing
                                    
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Constants.spacingXSmall
                                        
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.digit
                                            font.pixelSize: Constants.fontSizeXLarge
                                            font.weight: Font.Bold
                                            color: MColors.text
                                        }
                                        
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.letters
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
                                        }
                                    }
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        onPressed: {
                                            parent.color = MColors.surface
                                            HapticService.light()
                                        }
                                        onReleased: {
                                            parent.color = "transparent"
                                        }
                                        onCanceled: {
                                            parent.color = "transparent"
                                        }
                                        onClicked: {
                                            addDigit(modelData.digit)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Call/Delete buttons
                        Row {
                            width: parent.width
                            spacing: Constants.spacingLarge
                            
                            Rectangle {
                                width: (parent.width - parent.spacing) / 2
                                height: Constants.touchTargetLarge
                                color: "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: MColors.border
                                radius: Constants.borderRadiusSharp
                                antialiasing: Constants.enableAntialiasing
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: "delete"
                                    size: Constants.iconSizeLarge
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        parent.color = MColors.surface
                                        HapticService.light()
                                    }
                                    onReleased: {
                                        parent.color = "transparent"
                                    }
                                    onCanceled: {
                                        parent.color = "transparent"
                                    }
                                    onClicked: {
                                        deleteDigit()
                                    }
                                }
                            }
                            
                            Rectangle {
                                width: (parent.width - parent.spacing) / 2
                                height: Constants.touchTargetLarge
                                color: MColors.accent
                                border.width: Constants.borderWidthMedium
                                border.color: MColors.accentDark
                                radius: Constants.borderRadiusSharp
                                antialiasing: Constants.enableAntialiasing
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: "phone"
                                    size: Constants.iconSizeLarge
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        parent.scale = 0.9
                                        HapticService.medium()
                                    }
                                    onReleased: {
                                        parent.scale = 1.0
                                    }
                                    onCanceled: {
                                        parent.scale = 1.0
                                    }
                                    onClicked: {
                                        makeCall()
                                    }
                                }
                                
                                Behavior on scale {
                                    NumberAnimation { duration: 100 }
                                }
                            }
                        }
                    }
                }
                
                // Call History Page
                ListView {
                    width: parent.width
                    height: parent.height
                    clip: true
                    
                    model: callHistory
                    
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: Constants.touchTargetLarge + Constants.spacingSmall
                        color: "transparent"
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            anchors.topMargin: 0
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
                                    name: modelData.type === "outgoing" ? "phone-outgoing" : 
                                          modelData.type === "incoming" ? "phone-incoming" : "phone-missed"
                                    size: Constants.iconSizeMedium
                                    color: modelData.type === "missed" ? MColors.error : MColors.accent
                                }
                                
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.spacing * 2 - Constants.iconSizeMedium * 2
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
                                        }
                                        
                                        Text {
                                            text: formatDuration(modelData.duration)
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
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
                                    dialedNumber = modelData.phone
                                    parent.parent.parent.parent.parent.currentIndex = 0
                                }
                            }
                        }
                    }
                }
                
                // Contacts Page
                ListView {
                    width: parent.width
                    height: parent.height
                    clip: true
                    
                    model: contacts
                    
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: Constants.touchTargetLarge + Constants.spacingSmall
                        color: "transparent"
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            anchors.topMargin: 0
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
                                    name: "user"
                                    size: Constants.iconSizeMedium
                                    color: MColors.accent
                                }
                                
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.spacing * 2 - Constants.iconSizeMedium * 2
                                    spacing: Constants.spacingXSmall
                                    
                                    Text {
                                        width: parent.width
                                        text: modelData.name
                                        font.pixelSize: Constants.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: MColors.text
                                        elide: Text.ElideRight
                                    }
                                    
                                    Text {
                                        text: modelData.phone
                                        font.pixelSize: Constants.fontSizeSmall
                                        color: MColors.textSecondary
                                    }
                                }
                                
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData.favorite ? "star" : "star-off"
                                    size: Constants.iconSizeMedium
                                    color: modelData.favorite ? MColors.accent : MColors.textTertiary
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
                                    dialedNumber = modelData.phone
                                    parent.parent.parent.parent.parent.currentIndex = 0
                                }
                            }
                        }
                    }
                }
            }
            
            Rectangle {
                id: tabBar
                width: parent.width
                height: Constants.actionBarHeight
                color: MColors.surface
                
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: MColors.border
                }
                
                Row {
                    anchors.fill: parent
                    spacing: 0
                    
                    Repeater {
                        model: [
                            { icon: "phone", label: "Dial" },
                            { icon: "clock", label: "History" },
                            { icon: "users", label: "Contacts" }
                        ]
                        
                        Rectangle {
                            width: tabBar.width / 3
                            height: tabBar.height
                            color: "transparent"
                            
                            Rectangle {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.8
                                height: Constants.borderWidthThick
                                color: MColors.accent
                                opacity: tabBar.parent.currentIndex === index ? 1.0 : 0.0
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: Constants.animationFast }
                                }
                            }
                            
                            Column {
                                anchors.centerIn: parent
                                spacing: Constants.spacingXSmall
                                
                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: modelData.icon
                                    size: Constants.iconSizeMedium
                                    color: tabBar.parent.currentIndex === index ? MColors.accent : MColors.textSecondary
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationFast }
                                    }
                                }
                                
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    font.pixelSize: Constants.fontSizeXSmall
                                    color: tabBar.parent.currentIndex === index ? MColors.accent : MColors.textSecondary
                                    font.weight: tabBar.parent.currentIndex === index ? Font.DemiBold : Font.Normal
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationFast }
                                    }
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light()
                                    tabBar.parent.currentIndex = index
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
