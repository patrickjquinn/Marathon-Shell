pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

OobeSheet {
    id: root

    property string current

    //: Title of the language list on the first setup screen
    title: qsTr("Language")

    Repeater {
        model: SettingsManagerCpp.availableLanguages

        Silica.ListItem {
            id: row

            required property var modelData
            readonly property string nativeName: modelData.nativeName
            readonly property bool selected: modelData.code === root.current

            objectName: "language-" + modelData.code
            width: parent.width
            contentHeight: Silica.Theme.itemSizeMedium
            Accessible.role: Accessible.RadioButton
            Accessible.name: nativeName
            Accessible.checked: selected
            onClicked: {
                HapticManager.light();
                SettingsManagerCpp.language = modelData.code;
                root.open = false;
            }

            Column {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                anchors.verticalCenter: parent.verticalCenter

                Silica.Label {
                    width: parent.width
                    text: row.nativeName
                    color: row.selected || row.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    truncationMode: Silica.TruncationMode.Fade
                }

                Row {
                    spacing: Silica.Theme.paddingMedium

                    Silica.Label {
                        text: row.modelData.englishName
                        visible: text !== row.nativeName
                        color: row.selected || row.highlighted ? Silica.Theme.secondaryHighlightColor : Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    }

                    Silica.Label {
                        objectName: "preview-" + row.modelData.code
                        visible: row.modelData.status === "preview"
                        //: Marks a language whose translation is not finished
                        text: qsTr("Preview")
                        color: Silica.Theme.secondaryHighlightColor
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    }
                }
            }
        }
    }
}
