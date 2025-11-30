import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

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
            display = digit;
            newNumber = false;
        } else {
            display = display === "0" ? digit : display + digit;
        }
    }

    function appendDecimal() {
        if (newNumber) {
            display = "0.";
            newNumber = false;
        } else if (display.indexOf(".") === -1) {
            display += ".";
        }
    }

    function setOperator(op) {
        currentValue = parseFloat(display);
        currentOperator = op;
        newNumber = true;
    }

    function calculate() {
        var result = currentValue;
        var value = parseFloat(display);

        switch (currentOperator) {
        case "+":
            result = currentValue + value;
            break;
        case "-":
            result = currentValue - value;
            break;
        case "×":
            result = currentValue * value;
            break;
        case "÷":
            result = value !== 0 ? currentValue / value : 0;
            break;
        }

        display = result.toString();
        currentOperator = "";
        newNumber = true;
    }

    function clear() {
        display = "0";
        currentValue = 0;
        currentOperator = "";
        newNumber = true;
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: MSpacing.md
            spacing: MSpacing.md

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                color: MColors.surface
                radius: Constants.borderRadiusSharp
                border.width: Constants.borderWidthThin
                border.color: MColors.border

                MLabel {
                    anchors.fill: parent
                    anchors.margins: MSpacing.md
                    text: calcApp.display
                    variant: "primary"
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
                rowSpacing: MSpacing.sm
                columnSpacing: MSpacing.sm

                Repeater {
                    model: ["C", "÷", "×", "⌫", "7", "8", "9", "-", "4", "5", "6", "+", "1", "2", "3", "=", "0", ".", "", ""]

                    Item {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 60
                        visible: modelData !== ""

                        MCircularIconButton {
                            anchors.centerIn: parent
                            text: modelData
                            buttonSize: Math.min(parent.width, parent.height) - 10
                            iconSize: 24
                            variant: {
                                if (modelData === "=")
                                    return "primary";
                                if (modelData === "C" || modelData === "⌫")
                                    return "secondary";
                                if ("+-×÷".indexOf(modelData) !== -1)
                                    return "secondary";
                                return "secondary";
                            }
                            onClicked: {
                                HapticService.light();
                                if (modelData === "C") {
                                    calcApp.clear();
                                } else if (modelData === "⌫") {
                                    if (calcApp.display.length > 1) {
                                        calcApp.display = calcApp.display.slice(0, -1);
                                    } else {
                                        calcApp.display = "0";
                                    }
                                } else if (modelData === "=") {
                                    calcApp.calculate();
                                } else if ("+-×÷".indexOf(modelData) !== -1) {
                                    calcApp.setOperator(modelData);
                                } else if (modelData === ".") {
                                    calcApp.appendDecimal();
                                } else {
                                    calcApp.appendDigit(modelData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
