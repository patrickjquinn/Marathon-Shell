pragma ComponentBehavior: Bound
import MarathonOS.Shell
import QtQuick

Rectangle {
    id: languageSelector

    visible: false

    signal languageSelected(string languageId)
    signal dismissed

    width: parent.width
    height: languageSelector.visible ? selectorColumn.implicitHeight + Math.round(20 * Constants.scaleFactor) : 0
    color: "#2a2a2a"
    radius: Math.round(12 * Constants.scaleFactor)
    opacity: languageSelector.visible ? 1 : 0
    clip: true

    Column {
        id: selectorColumn

        anchors.centerIn: parent
        width: parent.width - Math.round(20 * Constants.scaleFactor)
        spacing: Math.round(4 * Constants.scaleFactor)

        Text {
            width: parent.width
            text: "Select Language"
            color: "#ffffff"
            font.pixelSize: Math.round(14 * Constants.scaleFactor)
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            width: parent.width
            height: 1
            color: "#444444"
        }

        Grid {
            id: languageGrid

            width: parent.width
            columns: 5
            spacing: Math.round(4 * Constants.scaleFactor)

            Repeater {
                model: LanguageManager.availableLanguages

                delegate: Rectangle {
                    id: langDelegate

                    required property string modelData

                    width: (languageGrid.width - languageGrid.spacing * 4) / 5
                    height: Math.round(50 * Constants.scaleFactor)
                    color: LanguageManager.currentLanguage === langDelegate.modelData ? "#4a9eff" : "#3a3a3a"
                    radius: Math.round(8 * Constants.scaleFactor)

                    Column {
                        anchors.centerIn: parent
                        spacing: Math.round(2 * Constants.scaleFactor)

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: LanguageManager.getFlag(langDelegate.modelData)
                            font.pixelSize: Math.round(20 * Constants.scaleFactor)
                            font.family: "Noto Color Emoji"
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: langDelegate.modelData.split("_")[0].toUpperCase()
                            color: "#ffffff"
                            font.pixelSize: Math.round(10 * Constants.scaleFactor)
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            LanguageManager.loadLanguage(langDelegate.modelData);
                            languageSelector.languageSelected(langDelegate.modelData);
                            languageSelector.dismissed();
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: {
            languageSelector.dismissed();
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 150
        }
    }
}
