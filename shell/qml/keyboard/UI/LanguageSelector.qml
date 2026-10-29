pragma ComponentBehavior: Bound

import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: languageSelector

    signal languageSelected(string languageId)
    signal dismissed

    visible: false
    height: visible ? header.height + languageList.height : 0
    clip: true

    Behavior on height {
        enabled: !MMotion.reduceMotion
        NumberAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
    }

    Silica.SectionHeader {
        id: header

        text: qsTr("Keyboard language")
    }

    Silica.SilicaListView {
        id: languageList

        anchors.top: header.bottom
        width: parent.width
        height: Math.min(count, 4) * Silica.Theme.itemSizeSmall
        clip: true
        model: LanguageManager.availableLanguages

        delegate: Silica.ListItem {
            id: languageItem

            required property string modelData
            readonly property bool current: LanguageManager.currentLanguage === modelData
            readonly property alias text: languageLabel.text

            objectName: "language_" + modelData
            width: languageList.width

            onClicked: {
                LanguageManager.loadLanguage(modelData);
                languageSelector.languageSelected(modelData);
                languageSelector.dismissed();
            }

            Silica.Label {
                id: languageLabel

                readonly property string nativeName: Qt.locale(languageItem.modelData).nativeLanguageName

                anchors.verticalCenter: parent.verticalCenter
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * Silica.Theme.horizontalPageMargin
                text: nativeName.charAt(0).toLocaleUpperCase() + nativeName.slice(1)
                color: languageItem.highlighted || languageItem.current ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                font.pixelSize: Silica.Theme.fontSizeMedium
                truncationMode: Silica.TruncationMode.Fade
            }
        }
    }
}
