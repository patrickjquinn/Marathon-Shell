import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: inputContainer

    property alias text: textInput.text
    property string placeholder: ""
    property string label: ""
    property bool password: false
    property bool disabled: false
    property string errorText: ""
    property bool hasError: errorText !== ""

    signal inputTextChanged(string text)
    signal accepted
    signal focused
    signal unfocused

    width: parent.width
    height: label !== "" ? 90 : 68
    color: "transparent"

    Column {
        anchors.fill: parent
        spacing: Constants.spacingSmall

        Text {
            visible: label !== ""
            text: label
            color: hasError ? "#CC0000" : "#FFFFFF"
            font.pixelSize: Constants.fontSizeSmall
            font.weight: Font.Medium
            font.family: MTypography.fontFamily
        }

        Rectangle {
            width: parent.width
            height: Constants.inputHeight
            radius: Constants.borderRadiusSmall
            color: "#1A1A1A"
            border.width: Constants.borderWidthMedium
            border.color: {
                if (hasError)
                    return "#CC0000";
                if (textInput.activeFocus)
                    return "#006666";
                return "#333333";
            }

            Behavior on border.color {
                ColorAnimation {
                    duration: 200
                }
            }

            TextInput {
                id: textInput
                anchors.fill: parent
                anchors.margins: 12
                color: disabled ? "#666666" : "#FFFFFF"
                font.pixelSize: Constants.fontSizeMedium
                font.family: MTypography.fontFamily
                echoMode: password ? TextInput.Password : TextInput.Normal
                enabled: !disabled
                verticalAlignment: TextInput.AlignVCenter

                Text {
                    visible: parent.text === "" && !parent.activeFocus
                    text: placeholder
                    color: "#666666"
                    font: parent.font
                    anchors.verticalCenter: parent.verticalCenter
                }

                onTextChanged: inputContainer.inputTextChanged(text)
                onAccepted: inputContainer.accepted()
                onActiveFocusChanged: {
                    if (activeFocus)
                        inputContainer.focused();
                    else
                        inputContainer.unfocused();
                }
            }
        }

        Text {
            visible: hasError
            text: errorText
            color: "#CC0000"
            font.pixelSize: Constants.fontSizeSmall
            font.family: MTypography.fontFamily
        }
    }
}
