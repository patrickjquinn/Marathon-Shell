import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import Terminal

MApp {
    id: terminalApp
    appId: "terminal"
    appName: "Terminal"
    appIcon: "assets/icon.svg"
    
    property int currentTabIndex: 0
    property var tabs: []
    property int nextTabId: 1
    
    function createNewTab() {
        tabs.push({
            id: nextTabId,
            title: "Terminal " + nextTabId,
            content: "Tab " + nextTabId + " content"
        })
        
        nextTabId++
        currentTabIndex = tabs.length - 1
        tabsChanged()
        
        Logger.info("Terminal", "Created new tab: " + currentTabIndex)
        HapticService.light()
    }
    
    function closeTab(index) {
        if (tabs.length === 1) {
            Logger.info("Terminal", "Cannot close last tab")
            return
        }
        
        if (index >= 0 && index < tabs.length) {
            tabs.splice(index, 1)
            
            if (currentTabIndex >= tabs.length) {
                currentTabIndex = tabs.length - 1
            }
            
            tabsChanged()
            Logger.info("Terminal", "Closed tab: " + index)
            HapticService.light()
        }
    }
    
    Component.onCompleted: {
        createNewTab()
    }
    
    content: Rectangle {
        id: contentRoot
        anchors.fill: parent
        color: MColors.background
        
        // Real C++ Terminal Engine
        TerminalEngine {
            id: terminalEngine
            
            Component.onCompleted: {
                start()
            }
        }
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            // Tab Bar
            Rectangle {
                id: tabBar
                width: parent.width
                height: 56
                color: MColors.surface
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: MColors.border
                }
                
                // Layout: ScrollView (tabs) + Add Button (fixed)
                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.rightMargin: Constants.spacingMedium
                    
                    // Scrollable tab area
                    ScrollView {
                        id: tabScrollView
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: addButton.left
                        anchors.rightMargin: Constants.spacingSmall
                        clip: true
                        
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                        
                        Row {
                            height: tabScrollView.height
                            spacing: Constants.spacingSmall
                            
                            Repeater {
                                model: terminalApp.tabs.length
                                
                                Rectangle {
                                    id: tabButton
                                    width: 180
                                    height: 40
                                    y: (parent.height - height) / 2
                                    color: index === currentTabIndex ? MColors.accent : MColors.elevated
                                    radius: Constants.borderRadiusSmall
                                    border.width: 1
                                    border.color: index === currentTabIndex ? MColors.accentBright : MColors.border
                                    
                                    scale: tabMouseArea.pressed ? 0.96 : 1.0
                                    
                                    Behavior on scale {
                                        enabled: Constants.enableAnimations
                                        NumberAnimation { duration: 100 }
                                    }
                                    
                                    Behavior on color {
                                        enabled: Constants.enableAnimations
                                        ColorAnimation { duration: MMotion.quick }
                                    }
                                    
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: Constants.spacingMedium
                                        anchors.rightMargin: Constants.spacingSmall
                                        spacing: Constants.spacingSmall
                                        
                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "terminal"
                                            size: 16
                                            color: index === currentTabIndex ? MColors.textOnAccent : MColors.text
                                        }
                                        
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: terminalApp.tabs[index] ? terminalApp.tabs[index].title : ""
                                            font.pixelSize: MTypography.sizeBody
                                            font.weight: index === currentTabIndex ? MTypography.weightDemiBold : MTypography.weightNormal
                                            font.family: MTypography.fontFamily
                                            color: index === currentTabIndex ? MColors.textOnAccent : MColors.text
                                            elide: Text.ElideRight
                                            width: 100
                                        }
                                        
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 20
                                            height: 20
                                            radius: 10
                                            color: closeMouseArea.pressed ? (index === currentTabIndex ? Qt.rgba(0, 0, 0, 0.2) : MColors.hover) : "transparent"
                                            visible: terminalApp.tabs.length > 1
                                            
                                            Icon {
                                                anchors.centerIn: parent
                                                name: "x"
                                                size: 12
                                                color: index === currentTabIndex ? MColors.textOnAccent : MColors.text
                                            }
                                            
                                            MouseArea {
                                                id: closeMouseArea
                                                anchors.fill: parent
                                                onClicked: {
                                                    terminalApp.closeTab(index)
                                                }
                                            }
                                        }
                                    }
                                    
                                    MouseArea {
                                        id: tabMouseArea
                                        anchors.fill: parent
                                        onClicked: {
                                            currentTabIndex = index
                                            HapticService.light()
                                        }
                                        z: -1
                                    }
                                }
                            }
                        }
                    }
                    
                    // Fixed add button (always visible)
                    Rectangle {
                        id: addButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        radius: 16
                        color: newTabMouseArea.pressed ? MColors.pressed : (newTabMouseArea.containsMouse ? MColors.hover : MColors.accent)
                        border.width: 1
                        border.color: MColors.accentBright
                        
                        Behavior on color {
                            enabled: Constants.enableAnimations
                            ColorAnimation { duration: MMotion.quick }
                        }
                        
                        Icon {
                            anchors.centerIn: parent
                            name: "plus"
                            size: 16
                            color: MColors.textOnAccent
                        }
                        
                        MouseArea {
                            id: newTabMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                terminalApp.createNewTab()
                                HapticService.light()
                            }
                        }
                    }
                }
            }
            
            // Terminal Content
            Rectangle {
                id: terminalContent
                width: parent.width
                height: parent.height - tabBar.height - inputArea.height
                color: MColors.background
                
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: Constants.spacingMedium
                    
                    TextArea {
                        id: terminalOutput
                        width: parent.width
                        height: Math.max(implicitHeight, terminalContent.height - Constants.spacingMedium * 2)
                        color: MColors.success
                        font.family: "Monaco, 'Courier New', monospace"
                        font.pixelSize: MTypography.sizeSmall
                        selectByMouse: true
                        readOnly: true
                        wrapMode: TextArea.Wrap
                        text: terminalEngine.output
                        
                        background: Rectangle {
                            color: "transparent"
                        }
                    }
                }
            }
            
            // Input Area - Edge to edge at bottom
            Rectangle {
                id: inputArea
                width: parent.width
                height: 48
                color: MColors.surface
                
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: MColors.border
                }
                
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.rightMargin: Constants.spacingMedium
                    spacing: Constants.spacingSmall
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "$ "
                        color: MColors.success
                        font.family: "Monaco, 'Courier New', monospace"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                    }
                    
                    TextInput {
                        id: commandInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 40
                        color: MColors.text
                        font.family: "Monaco, 'Courier New', monospace"
                        font.pixelSize: MTypography.sizeBody
                        selectByMouse: true
                        verticalAlignment: TextInput.AlignVCenter
                        
                        onAccepted: {
                            if (text.trim() !== "") {
                                terminalEngine.sendInput(text)
                                text = ""
                            }
                        }
                        
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                                terminalEngine.sendCtrlC()
                                text = ""
                            } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                                terminalEngine.sendCtrlD()
                                text = ""
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Handle deep link requests
    Connections {
        target: NavigationRouter
        function onDeepLinkRequested(appId, route, params) {
            if (appId === "terminal") {
                Logger.info("Terminal", "Deep link requested: " + route)
                
                // Handle specific routes
                if (route === "new-tab") {
                    createNewTab()
                }
            }
        }
    }
}
