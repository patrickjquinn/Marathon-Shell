pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Effects
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// Make it yours: the wallpaper, and with it the system's colours.
Item {
    id: root

    signal done

    Column {
        anchors.fill: parent
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        spacing: Silica.Theme.paddingLarge

        Silica.Label {
            width: parent.width
            text: qsTr("Make it yours")
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeExtraLarge
            wrapMode: Text.WordWrap
        }

        Silica.Label {
            width: parent.width
            //: Setup, wallpaper step: why the choice matters
            text: qsTr("Your wallpaper sets Marathon's colours, everywhere.")
            color: Silica.Theme.secondaryHighlightColor
            wrapMode: Text.WordWrap
        }

        OobeGridPreview {
            id: preview

            objectName: "lookPreview"
            width: parent.width
            height: Math.max(Silica.Theme.itemSizeHuge, parent.height - y - strip.height - button.height - 2 * parent.spacing)
            rows: 2
        }

        ListView {
            id: strip

            objectName: "wallpaperStrip"
            width: parent.width
            height: Silica.Theme.itemSizeLarge
            orientation: ListView.Horizontal
            spacing: Silica.Theme.paddingMedium
            clip: true
            model: AmbienceService.wallpapers

            delegate: Item {
                id: thumb

                required property var modelData
                readonly property bool selected: SettingsManagerCpp.wallpaperPath.toString() === modelData.path.toString()

                function choose() {
                    SettingsManagerCpp.wallpaperPath = modelData.path;
                    const p = thumb.mapToItem(preview, width / 2, height / 2);
                    preview.wallpaper.reveal(modelData.path, p.x, p.y);
                }

                objectName: "wallpaper-" + modelData.name
                width: strip.height
                height: strip.height
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.name
                Accessible.checked: selected

                Item {
                    id: face

                    anchors.fill: parent
                    anchors.margins: Silica.Theme.paddingSmall
                    visible: false
                    layer.enabled: true

                    Image {
                        anchors.fill: parent
                        source: thumb.modelData.path
                        sourceSize: Qt.size(width, height)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                Rectangle {
                    id: round

                    anchors.fill: face
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: face
                    source: face
                    maskEnabled: true
                    maskSource: round
                }

                Rectangle {
                    objectName: "ring"
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: thumb.selected ? Silica.Theme.paddingSmall / 2 : 0
                    border.color: Silica.Theme.highlightColor
                }

                TapHandler {
                    onTapped: thumb.choose()
                }
            }
        }

        Silica.Button {
            id: button

            objectName: "lookContinue"

            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Continue")
            onClicked: root.done()
        }
    }
}
