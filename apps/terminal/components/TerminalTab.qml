import QtQuick
import QtQuick.Controls
import Qt.labs.platform as Platform
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: terminalTab
    
    property string title: "Terminal"
    property bool active: false
    property alias processRunning: process.running
    
    color: MColors.background
    
    signal closeRequested()
    
    Platform.StandardPaths {
        id: standardPaths
    }
    
    Process {
        id: process
        
        property string output: ""
        property bool running: process.state === Process.Running
        
        workingDirectory: standardPaths.writableLocation(Platform.StandardPaths.HomeLocation)
        
        program: {
            if (Qt.platform.os === "osx") {
                return "/bin/zsh"
            } else {
                var shellEnv = process.environment.SHELL
                return shellEnv || "/bin/bash"
            }
        }
        
        arguments: ["-i"]
        
        processChannelMode: Process.MergedChannels
        
        onReadyReadStandardOutput: {
            var newOutput = readAllStandardOutput()
            output += newOutput
            terminalOutputText.text = output
            
            Qt.callLater(function() {
                terminalFlickable.contentY = terminalFlickable.contentHeight - terminalFlickable.height
            })
        }
        
        onReadyReadStandardError: {
            var errorOutput = readAllStandardError()
            output += errorOutput
            terminalOutputText.text = output
        }
        
        onFinished: {
            output += "\n[Process exited with code " + exitCode + "]\n"
            terminalOutputText.text = output
        }
        
        onErrorOccurred: {
            output += "\n[Error: " + errorString() + "]\n"
            terminalOutputText.text = output
        }
        
        Component.onCompleted: {
            start()
        }
        
        Component.onDestruction: {
            if (running) {
                terminate()
            }
        }
    }
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Flickable {
            id: terminalFlickable
            width: parent.width
            height: parent.height - terminalInput.height
            contentWidth: terminalOutputText.width
            contentHeight: terminalOutputText.height
            clip: true
            
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: Constants.scrollBarWidth
                
                contentItem: Rectangle {
                    implicitWidth: Constants.scrollBarWidth
                    radius: Constants.borderRadiusSharp
                    color: parent.pressed ? MColors.accentPressed : (parent.hovered ? MColors.accent : MColors.textTertiary)
                    opacity: parent.active ? 1.0 : 0.5
                    
                    Behavior on color {
                        ColorAnimation { duration: MMotion.quick }
                    }
                }
                
                background: Rectangle {
                    color: "transparent"
                }
            }
            
            TextEdit {
                id: terminalOutputText
                width: terminalFlickable.width - Constants.spacingMedium * 2
                x: Constants.spacingMedium
                y: Constants.spacingMedium
                
                text: ""
                readOnly: true
                selectByMouse: true
                selectByKeyboard: true
                wrapMode: TextEdit.NoWrap
                
                font.family: "Menlo, Monaco, 'Courier New', monospace"
                font.pixelSize: Constants.fontSizeMedium
                color: MColors.text
                
                textFormat: TextEdit.PlainText
            }
        }
        
        Rectangle {
            id: terminalInput
            width: parent.width
            height: Constants.touchTargetLarge
            color: MColors.surface
            border.width: Constants.borderWidthThin
            border.color: terminalInputField.activeFocus ? MColors.accent : MColors.border
            
            Behavior on border.color {
                ColorAnimation { duration: MMotion.quick }
            }
            
            Row {
                anchors.fill: parent
                anchors.margins: Constants.spacingSmall
                spacing: Constants.spacingSmall
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "❯"
                    font.family: "Menlo, Monaco, 'Courier New', monospace"
                    font.pixelSize: Constants.fontSizeLarge
                    color: MColors.accent
                }
                
                TextInput {
                    id: terminalInputField
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 80
                    
                    font.family: "Menlo, Monaco, 'Courier New', monospace"
                    font.pixelSize: Constants.fontSizeMedium
                    color: MColors.text
                    selectionColor: MColors.accent
                    selectedTextColor: MColors.textOnAccent
                    
                    focus: true
                    
                    Keys.onReturnPressed: {
                        if (text.length > 0 && process.running) {
                            process.write(text + "\n")
                            text = ""
                        }
                    }
                    
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                            if (process.running) {
                                process.terminate()
                                process.start()
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                            process.output = ""
                            terminalOutputText.text = ""
                            if (process.running) {
                                process.write("clear\n")
                            }
                            event.accepted = true
                        }
                    }
                }
            }
        }
    }
}
