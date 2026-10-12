import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

DockedPanel {
    id: panel

    property var music
    readonly property Player player: music.player
    readonly property var track: player.currentTrack

    width: parent ? parent.width : 0
    height: content.height + Theme.paddingMedium
    dock: Dock.Bottom

    Column {
        id: content

        width: parent.width

        Item {
            width: parent.width
            height: Theme.itemSizeLarge

            BackgroundItem {
                id: details

                objectName: "panelDetails"
                anchors {
                    left: parent.left
                    right: controls.left
                    top: parent.top
                    bottom: parent.bottom
                }
                Accessible.name: qsTr("Now playing: %1").arg(titleLabel.text)
                onClicked: panel.music.openPlayer()

                Column {
                    x: Theme.horizontalPageMargin
                    width: parent.width - x - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        id: titleLabel

                        width: parent.width
                        text: panel.track ? panel.track.title : ""
                        truncationMode: TruncationMode.Fade
                        color: details.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        width: parent.width
                        text: panel.track ? panel.track.artist : ""
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeSmall
                        color: details.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    }
                }
            }

            Row {
                id: controls

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }

                IconButton {
                    objectName: "panelPrevious"
                    icon.source: "image://theme/icon-m-media-previous"
                    Accessible.name: qsTr("Previous")
                    onClicked: panel.player.previous()
                }
                IconButton {
                    objectName: "panelPlayPause"
                    icon.source: panel.player.playing ? "image://theme/icon-m-media-pause" : "image://theme/icon-m-media-play"
                    Accessible.name: panel.player.playing ? qsTr("Pause") : qsTr("Play")
                    onClicked: panel.player.toggle()
                }
                IconButton {
                    objectName: "panelNext"
                    icon.source: "image://theme/icon-m-media-next"
                    Accessible.name: qsTr("Next")
                    onClicked: panel.player.next()
                }
            }
        }

        PositionSlider {
            objectName: "panelSlider"
            width: parent.width
            label: ""
            player: panel.player
        }
    }
}
