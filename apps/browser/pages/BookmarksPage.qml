import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: bookmarksPage

    property var bookmarks: []

    // The page the browser is currently showing, so this page can offer to
    // bookmark it. This replaced the always-on star inside the address
    // pill, which cost the host the room it needed to render.
    property string currentPageUrl: ""
    property string currentPageTitle: ""
    property bool currentPageBookmarked: false
    property bool bookmarksDisabled: false
    // Supplied by BrowserApp so this page shares the app's single scheme
    // predicate rather than carrying a third regex dialect of its own.
    property var schemeOf: function (url) {
        return /^https?:\/\//.test(url || "") ? "secure" : "none";
    }

    signal bookmarkSelected(string url)
    signal deleteBookmark(string url)
    signal toggleCurrentBookmark

    color: MColors.background

    // A plain sibling above the list, NOT a ListView.header: a header whose
    // size settles after the view does leaves the list scrolled with the
    // row's top half under the drawer tab bar, and positionViewAtBeginning
    // races the same bindings that cause it.
    MSettingsListItem {
        id: bookmarkCurrentRow

        readonly property bool actionable: bookmarksPage.schemeOf(bookmarksPage.currentPageUrl) !== "none" // qmllint disable use-proper-function

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        visible: actionable
        height: actionable ? implicitHeight : 0
        title: bookmarksPage.currentPageBookmarked ? "Remove bookmark" : "Bookmark this page"
        subtitle: bookmarksPage.currentPageTitle || bookmarksPage.currentPageUrl
        iconName: bookmarksPage.currentPageBookmarked ? "star" : "plus"
        // Dimmed but still tappable: Item.enabled false propagates to the
        // row's own MouseArea, so the tap never reached the handler and the
        // "Bookmarks are disabled in Private Browsing" toast it raises was
        // dead code. A disabled-looking control that explains itself when
        // pressed beats one that silently does nothing.
        opacity: bookmarksPage.bookmarksDisabled ? 0.45 : 1
        onSettingClicked: bookmarksPage.toggleCurrentBookmark()
    }

    // A sibling of the list, not a child of it: a ListView reparents its
    // children onto contentItem, whose width is unbounded, so centreIn there
    // let the message run off the edge of the drawer.
    MEmptyState {
        anchors.centerIn: bookmarksList
        width: bookmarksList.width - MSpacing.lg * 2
        visible: bookmarksPage.bookmarks.length === 0
        iconName: "star"
        title: "No bookmarks yet"
        message: "Pages you bookmark show up here."
    }

    ListView {
        id: bookmarksList

        anchors.top: bookmarkCurrentRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: bookmarksPage.bookmarks

        delegate: MSettingsListItem {
            property real swipeX: 0

            title: modelData.title || modelData.url
            subtitle: modelData.url
            iconName: "star"
            showChevron: true
            onSettingClicked: {
                Logger.info("BookmarksPage", "Bookmark clicked: " + modelData.url);
                bookmarksPage.bookmarkSelected(modelData.url);
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

                property real startX: 0
                property real currentX: 0

                anchors.fill: parent
                propagateComposedEvents: true
                onPressed: mouse => {
                    startX = mouse.x;
                    currentX = mouse.x;
                }
                onPositionChanged: mouse => {
                    currentX = mouse.x;
                    var deltaX = currentX - startX;
                    if (deltaX < 0 && deltaX > -Constants.touchTargetLarge)
                        parent.swipeX = deltaX;
                }
                onReleased: {
                    if (parent.swipeX < -Constants.touchTargetMedium)
                        bookmarksPage.deleteBookmark(modelData.url);

                    parent.swipeX = 0;
                }
                onClicked: mouse => {
                    if (parent.swipeX === 0)
                        mouse.accepted = false;
                    else
                        parent.swipeX = 0;
                }
            }

            transform: Translate {
                x: swipeX
            }

            Behavior on swipeX {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
