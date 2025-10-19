import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import "./pages"

MApp {
    id: phoneApp
    appId: "phone"
    appName: "Phone"
    appIcon: "assets/icon.svg"
    
    property var contacts: typeof ContactsManager !== 'undefined' ? ContactsManager.contacts : []
    property var callHistory: typeof CallHistoryManager !== 'undefined' ? CallHistoryManager.history : []
    
    property string dialedNumber: ""
    property bool inCall: typeof TelephonyService !== 'undefined' && TelephonyService.callState !== "idle"
    
    property int editingContactId: -1
    property string editingContactName: ""
    property string editingContactPhone: ""
    property string editingContactEmail: ""
    
    Connections {
        target: typeof TelephonyService !== 'undefined' ? TelephonyService : null
        function onIncomingCall(number) {
            Logger.info("Phone", "Incoming call from: " + number)
            var contactName = resolveContactName(number)
            incomingCallScreen.show(number, contactName)
        }
        
        function onCallStateChanged(state) {
            Logger.info("Phone", "Call state changed: " + state)
            if (state === "idle" && dialedNumber.length > 0) {
                dialedNumber = ""
            }
        }
    }
    
    function resolveContactName(number) {
        for (var i = 0; i < contacts.length; i++) {
            if (contacts[i].phone === number) {
                return contacts[i].name
            }
        }
        return "Unknown"
    }
    
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
            Logger.info("Phone", "Calling: " + dialedNumber)
            if (typeof TelephonyService !== 'undefined') {
                TelephonyService.dial(dialedNumber)
                var contactName = resolveContactName(dialedNumber)
                activeCallPage.show(dialedNumber, contactName)
            }
            HapticService.medium()
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
                            id: deleteButton
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: Constants.spacingMedium
                            anchors.topMargin: 0
                            width: Constants.touchTargetLarge
                            color: "#E74C3C"
                            radius: Constants.borderRadiusSharp
                            visible: callHistoryItem.x < -20
                            
                            Icon {
                                anchors.centerIn: parent
                                name: "trash"
                                size: Constants.iconSizeMedium
                                color: "white"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (typeof CallHistoryManager !== 'undefined') {
                                        CallHistoryManager.deleteCall(modelData.id)
                                    }
                                }
                            }
                        }
                        
                        Rectangle {
                            id: callHistoryItem
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            anchors.topMargin: 0
                            color: MColors.surface
                            radius: Constants.borderRadiusSharp
                            border.width: Constants.borderWidthThin
                            border.color: MColors.border
                            antialiasing: Constants.enableAntialiasing
                            
                            Behavior on x {
                                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                            }
                            
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
                                property real startX: 0
                                
                                onPressed: {
                                    startX = mouse.x
                                    parent.color = MColors.surface2
                                    HapticService.light()
                                }
                                onReleased: {
                                    parent.color = MColors.surface
                                    if (callHistoryItem.x < -100) {
                                        if (typeof CallHistoryManager !== 'undefined') {
                                            CallHistoryManager.deleteCall(modelData.id)
                                        }
                                    } else {
                                        callHistoryItem.x = 0
                                    }
                                }
                                onCanceled: {
                                    parent.color = MColors.surface
                                    callHistoryItem.x = 0
                                }
                                onPositionChanged: {
                                    if (pressed) {
                                        var delta = mouse.x - startX
                                        if (delta < 0) {
                                            callHistoryItem.x = Math.max(delta, -120)
                                        }
                                    }
                                }
                                onClicked: {
                                    if (callHistoryItem.x === 0) {
                                        dialedNumber = modelData.phone
                                        parent.parent.parent.parent.parent.currentIndex = 0
                                    } else {
                                        callHistoryItem.x = 0
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Contacts Page
                Rectangle {
                    color: MColors.background
                    
                    ListView {
                        id: contactsList
                        anchors.fill: parent
                        clip: true
                        
                        model: contacts
                        
                        delegate: Rectangle {
                            width: contactsList.width
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
                                        editingContactId = modelData.id || -1
                                        editingContactName = modelData.name || ""
                                        editingContactPhone = modelData.phone || ""
                                        editingContactEmail = modelData.email || ""
                                        contactEditorLoader.active = true
                                    }
                                }
                            }
                        }
                    }
                    
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Constants.spacingLarge
                        width: Constants.touchTargetLarge
                        height: Constants.touchTargetLarge
                        radius: Constants.touchTargetLarge / 2
                        color: MColors.accent
                        border.width: Constants.borderWidthThick
                        border.color: MColors.accentDark
                        antialiasing: true
                        
                        Icon {
                            anchors.centerIn: parent
                            name: "plus"
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
                                Logger.info("Phone", "Add new contact")
                                editingContactId = -1
                                editingContactName = ""
                                editingContactPhone = ""
                                editingContactEmail = ""
                                contactEditorLoader.active = true
                            }
                        }
                        
                        Behavior on scale {
                            NumberAnimation { duration: 100 }
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
        
        Loader {
            id: contactEditorLoader
            anchors.fill: parent
            active: false
            z: 999
            
            sourceComponent: ContactEditorPage {
                contactId: phoneApp.editingContactId
                contactName: phoneApp.editingContactName
                contactPhone: phoneApp.editingContactPhone
                contactEmail: phoneApp.editingContactEmail
                
                onContactSaved: {
                    contactEditorLoader.active = false
                }
                onCancelled: {
                    contactEditorLoader.active = false
                }
            }
        }
        
    IncomingCallScreen {
        id: incomingCallScreen
        anchors.fill: parent
    }
    
    ActiveCallPage {
        id: activeCallPage
        anchors.fill: parent
    }
}
}
