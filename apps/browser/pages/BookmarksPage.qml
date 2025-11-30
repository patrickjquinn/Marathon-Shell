import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Containers

Rectangle {
    id: bookmarksPage
    color: MColors.background

    signal bookmarkSelected(string url)
    signal deleteBookmark(string url)

    property var bookmarks: []

    ListView {
        id: bookmarksList
        anchors.fill: parent
        clip: true

        model: bookmarksPage.bookmarks

        delegate: MSettingsListItem {
            title: modelData.title || modelData.url
            subtitle: modelData.url
            iconName: "star"
            showChevron: true

            onSettingClicked: {
                Logger.info("BookmarksPage", "Bookmark clicked: " + modelData.url);
                bookmarksPage.bookmarkSelected(modelData.url);
            }

            property real swipeX: 0

            transform: Translate {
                x: swipeX
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Constants.touchTargetLarge
                color: MColors.error
                visible: parent.swipeX < -10

                Icon {
                    anchors.centerIn: parent
                    name: "trash-2"
                    size: Constants.iconSizeMedium
                    color: MColors.background
                }
            }

            MouseArea {
                id: swipeArea
                anchors.fill: parent
                propagateComposedEvents: true

                property real startX: 0
                property real currentX: 0

                onPressed: mouse => {
                    startX = mouse.x;
                    currentX = mouse.x;
                }

                onPositionChanged: mouse => {
                    currentX = mouse.x;
                    var deltaX = currentX - startX;

                    if (deltaX < 0 && deltaX > -Constants.touchTargetLarge) {
                        parent.swipeX = deltaX;
                    }
                }

                onReleased: {
                    if (parent.swipeX < -Constants.touchTargetMedium) {
                        bookmarksPage.deleteBookmark(modelData.url);
                    }
                    parent.swipeX = 0;
                }

                onClicked: mouse => {
                    if (parent.swipeX === 0) {
                        mouse.accepted = false;
                    } else {
                        parent.swipeX = 0;
                    }
                }
            }

            Behavior on swipeX {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            visible: bookmarksPage.bookmarks.length === 0
            anchors.centerIn: parent
            text: "No bookmarks yet"
            font.pixelSize: MTypography.sizeLarge
            color: MColors.textTertiary
        }
    }
}
