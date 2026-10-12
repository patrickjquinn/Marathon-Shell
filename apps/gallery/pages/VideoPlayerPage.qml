import QtQuick
import QtMultimedia
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Share 1.0
import "../GalleryModel.js" as Model

FullscreenContentPage {
    id: root

    property var store
    property var video
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    // Tap shows or hides the controls; they stay up while paused.
    property bool controlsRequested: true
    readonly property bool controlsShown: !playing || controlsRequested

    function toggle() {
        if (playing)
            player.pause();
        else
            player.play();
    }

    // Vertical drags open the pulley, so the page goes back sideways.
    navigationStyle: PageNavigation.Horizontal
    palette.colorScheme: Theme.LightOnDark
    onStatusChanged: if (status === PageStatus.Active) forceActiveFocus()
    Keys.onSpacePressed: toggle()
    Keys.onEscapePressed: pageStack.pop()

    Rectangle {
        anchors.fill: parent
        color: Theme.darkPrimaryColor
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: height

        PullDownMenu {
            id: menu

            MenuItem {
                objectName: "deleteAction"
                text: qsTr("Delete")
                onClicked: remorse.execute(qsTr("Deleted"), function () {
                    root.store.deletePhoto(root.video.id);
                    pageStack.pop();
                })
            }
            MenuItem {
                objectName: "shareAction"
                text: qsTr("Share")
                visible: KeelShareService.available()
                onClicked: share.trigger()
            }
            MenuItem {
                objectName: "detailsAction"
                text: qsTr("Details")
                onClicked: pageStack.push(Qt.resolvedUrl("PhotoDetailsPage.qml"), { photo: root.video })
            }
        }

        Video {
            id: player

            objectName: "player"
            anchors.fill: parent
            source: root.video ? root.video.path : ""
            fillMode: VideoOutput.PreserveAspectFit
            Accessible.role: Accessible.Animation
            Accessible.name: Model.fileName(root.video)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.controlsRequested = !root.controlsRequested
        }
    }

    Label {
        x: Theme.horizontalPageMargin
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.horizontalPageMargin
        visible: root.controlsShown && !menu.active
        text: root.video && root.video.timestamp
              ? Format.formatDate(new Date(root.video.timestamp), Formatter.DateLong) : Model.fileName(root.video)
        truncationMode: TruncationMode.Fade
    }

    IconButton {
        objectName: "playButton"
        anchors.centerIn: parent
        visible: root.controlsShown && !menu.active
        icon.source: root.playing ? "image://theme/icon-l-pause" : "image://theme/icon-l-play"
        Accessible.name: root.playing ? qsTr("Pause") : qsTr("Play")
        onClicked: root.toggle()
    }

    Slider {
        id: slider

        objectName: "positionSlider"
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: Theme.paddingLarge
        }
        visible: root.controlsShown && !menu.active
        minimumValue: 0
        maximumValue: Math.max(1, player.duration)
        enabled: player.seekable
        valueText: Format.formatDuration(value / 1000, Formatter.DurationShort)
        label: Format.formatDuration(player.duration / 1000, Formatter.DurationShort)
        // Playback moves the value only while the slider is not held.
        onValueChanged: if (!down && Math.abs(value - player.position) > 500) player.seek(value)

        Binding on value {
            when: !slider.down
            value: player.position
        }
    }

    RemorsePopup {
        id: remorse

        objectName: "remorse"
    }

    ShareAction {
        id: share

        mimeType: "video/*"
        title: qsTr("Share video")
        resources: root.video ? [root.video.path] : []
    }
}
