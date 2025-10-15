import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers

MApp {
    id: calcApp
    appId: "calculator"
    appName: "Calculator"
    appIcon: "qrc:/images/calculator.svg"
    
    property string display: "0"
    property real currentValue: 0
    property string currentOperator: ""
    property bool newNumber: true
    
    function appendDigit(digit) {
        if (newNumber) {
            display = digit
            newNumber = false
        } else {
            display = display === "0" ? digit : display + digit
        }
    }
    
    function appendDecimal() {
        if (newNumber) {
            display = "0."
            newNumber = false
        } else if (display.indexOf(".") === -1) {
            display += "."
        }
    }
    
    function setOperator(op) {
        currentValue = parseFloat(display)
        currentOperator = op
        newNumber = true
    }
    
    function calculate() {
        var result = currentValue
        var value = parseFloat(display)
        
        switch (currentOperator) {
            case "+":
                result = currentValue + value
                break
            case "-":
                result = currentValue - value
                break
            case "×":
                result = currentValue * value
                break
            case "÷":
                result = value !== 0 ? currentValue / value : 0
                break
        }
        
        display = result.toString()
        currentOperator = ""
        newNumber = true
    }
    
    function clear() {
        display = "0"
        currentValue = 0
        currentOperator = ""
        newNumber = true
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: Colors.background
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Constants.spacingMedium
            spacing: Constants.spacingMedium
            
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                color: Colors.surface
                radius: Constants.borderRadiusMedium
                
                Text {
                    anchors.fill: parent
                    anchors.margins: Constants.spacingMedium
                    text: calcApp.display
                    color: Colors.text
                    font.pixelSize: 48
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideLeft
                }
            }
            
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 4
                rowSpacing: Constants.spacingSmall
                columnSpacing: Constants.spacingSmall
                
                Repeater {
                    model: [
                        "C", "÷", "×", "⌫",
                        "7", "8", "9", "-",
                        "4", "5", "6", "+",
                        "1", "2", "3", "=",
                        "0", ".", "", ""
                    ]
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 60
                        color: {
                            if (modelData === "") return "transparent"
                            if (modelData === "=") return Colors.accent
                            if ("+-×÷".indexOf(modelData) !== -1) return Colors.surfaceLight
                            if (modelData === "C" || modelData === "⌫") return Colors.error
                            return Colors.surface
                        }
                        radius: Constants.borderRadiusMedium
                        visible: modelData !== ""
                        
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: Colors.text
                            font.pixelSize: 24
                            font.weight: Font.Medium
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (modelData === "C") {
                                    calcApp.clear()
                                } else if (modelData === "⌫") {
                                    if (calcApp.display.length > 1) {
                                        calcApp.display = calcApp.display.slice(0, -1)
                                    } else {
                                        calcApp.display = "0"
                                    }
                                } else if (modelData === "=") {
                                    calcApp.calculate()
                                } else if ("+-×÷".indexOf(modelData) !== -1) {
                                    calcApp.setOperator(modelData)
                                } else if (modelData === ".") {
                                    calcApp.appendDecimal()
                                } else {
                                    calcApp.appendDigit(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

