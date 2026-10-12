import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Modal {
    id: textInputModal

    property alias inputText: textInput.text
    property string placeholderText: ""

    signal accepted(string text)

    Column {
        width: parent.width
        spacing: Silica.Theme.paddingLarge

        Silica.TextField {
            id: textInput

            width: parent.width
            textLeftMargin: 0
            textRightMargin: 0
            placeholderText: textInputModal.placeholderText
        }

        Row {
            width: parent.width
            spacing: Silica.Theme.paddingMedium
            z: 10

            Silica.Button {
                text: "Cancel"
                width: (parent.width - Silica.Theme.paddingMedium) / 2
                onClicked: {
                    console.log("Cancel clicked");
                    textInputModal.close();
                }
            }

            Silica.Button {
                text: "Save"
                width: (parent.width - Silica.Theme.paddingMedium) / 2
                onClicked: {
                    console.log("Save clicked, text:", textInput.text);
                    textInputModal.accepted(textInput.text);
                    textInputModal.close();
                }
            }
        }
    }
}
