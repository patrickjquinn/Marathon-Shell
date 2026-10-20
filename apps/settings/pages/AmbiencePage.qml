pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Page {
    id: page

    // Only present once the app runner shares the shell's wallpaper list.
    readonly property var store: typeof Wallpapers !== "undefined" ? Wallpapers : null

    SilicaGridView {
        id: grid

        objectName: "ambienceGrid"
        anchors.fill: parent
        cellWidth: width / 2
        cellHeight: Math.round(cellWidth * 1.6)
        model: page.store ? page.store.wallpapers : []
        header: PageHeader {
            title: qsTr("Ambience")
        }

        delegate: GridItem {
            id: item

            required property var modelData
            // GridItem reads model.index to make room for an open menu.
            required property var model
            readonly property bool current: Settings.wallpaperPath === modelData.path

            function choose() {
                Settings.wallpaperPath = modelData.path;
            }

            objectName: "ambience-" + modelData.name
            width: grid.cellWidth
            contentHeight: grid.cellHeight
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.name
            Accessible.checked: current
            Accessible.onPressAction: choose()
            Keys.onReturnPressed: choose()
            Keys.onSpacePressed: choose()
            onClicked: choose()

            Image {
                id: image

                anchors.fill: parent
                anchors.margins: Theme.paddingSmall
                source: item.modelData.path
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: item.highlighted ? Theme.opacityHigh : 1
            }
            Rectangle {
                anchors.fill: image
                visible: item.current
                color: "transparent"
                border.width: Theme.paddingSmall
                border.color: Theme.highlightColor
            }
            Rectangle {
                anchors {
                    left: image.left
                    right: image.right
                    bottom: image.bottom
                }
                height: name.height + 2 * Theme.paddingSmall
                color: Qt.rgba(0, 0, 0, 0.6)

                Label {
                    id: name

                    anchors {
                        left: parent.left
                        leftMargin: Theme.paddingMedium
                        right: check.left
                        verticalCenter: parent.verticalCenter
                    }
                    text: item.modelData.name
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: item.current || item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Icon {
                    id: check

                    anchors {
                        right: parent.right
                        rightMargin: Theme.paddingSmall
                        verticalCenter: parent.verticalCenter
                    }
                    visible: item.current
                    source: "image://theme/icon-s-accept"
                    color: Theme.highlightColor
                }
            }
            FocusFrame {
                parent: item
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: grid.count === 0
            text: qsTr("No ambiences")
            hintText: page.store ? "" : qsTr("Settings can't reach the ambience list on this device")
        }

        VerticalScrollDecorator {}
    }
}
