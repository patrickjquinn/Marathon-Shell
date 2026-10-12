import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

Page {
    id: page

    property var music
    readonly property Player player: music.player
    readonly property var track: player.currentTrack

    objectName: "playerPage"

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Now playing")
                description: page.track ? page.track.album : ""
            }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: width
                radius: Theme.paddingSmall
                color: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Icon {
                    anchors.centerIn: parent
                    width: Theme.iconSizeExtraLarge
                    height: width
                    source: "image://theme/icon-l-music"
                }
            }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin

                Label {
                    objectName: "playerTitle"
                    width: parent.width
                    text: page.track ? page.track.title : qsTr("Nothing playing")
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.highlightColor
                    truncationMode: TruncationMode.Fade
                    horizontalAlignment: Text.AlignHCenter
                }
                Label {
                    width: parent.width
                    text: page.track ? page.track.artist : ""
                    color: Theme.secondaryHighlightColor
                    truncationMode: TruncationMode.Fade
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            PositionSlider {
                objectName: "playerSlider"
                width: parent.width
                player: page.player
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium

                IconButton {
                    objectName: "shuffleButton"
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-shuffle"
                    highlighted: page.player.shuffle
                    Accessible.name: qsTr("Shuffle")
                    Accessible.checkable: true
                    Accessible.checked: page.player.shuffle
                    onClicked: page.player.shuffle = !page.player.shuffle
                }
                IconButton {
                    objectName: "previousButton"
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-media-previous"
                    enabled: page.track !== null
                    Accessible.name: qsTr("Previous")
                    onClicked: page.player.previous()
                }
                IconButton {
                    objectName: "playPauseButton"
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: page.player.playing ? "image://theme/icon-l-pause" : "image://theme/icon-l-play"
                    enabled: page.track !== null
                    Accessible.name: page.player.playing ? qsTr("Pause") : qsTr("Play")
                    onClicked: page.player.toggle()
                }
                IconButton {
                    objectName: "nextButton"
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-media-next"
                    enabled: page.track !== null
                    Accessible.name: qsTr("Next")
                    onClicked: page.player.next()
                }
                IconButton {
                    objectName: "repeatButton"
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: page.player.repeatMode === "one" ? "image://theme/icon-m-repeat-single" : "image://theme/icon-m-repeat"
                    highlighted: page.player.repeatMode !== "off"
                    Accessible.name: page.player.repeatMode === "off" ? qsTr("Repeat off")
                                   : page.player.repeatMode === "all" ? qsTr("Repeat all") : qsTr("Repeat one")
                    onClicked: page.player.cycleRepeat()
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
