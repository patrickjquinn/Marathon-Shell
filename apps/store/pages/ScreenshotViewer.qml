pragma ComponentBehavior: Bound

import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick

// Screenshots full screen, one per page, swiped sideways.
Rectangle {
    id: viewer

    required property var store
    required property var screenshots
    property int startIndex: 0

    color: "#000000"

    MTopBar {
        id: bar
        width: parent.width
        minimized: true
        showBack: true
        title: (pages.currentIndex + 1) + " of " + viewer.screenshots.length
        onBackClicked: viewer.store.goBack()
    }

    ListView {
        id: pages
        anchors.top: bar.bottom
        anchors.bottom: dots.top
        width: parent.width
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        model: viewer.screenshots
        Component.onCompleted: positionViewAtIndex(viewer.startIndex, ListView.Beginning)
        delegate: Item {
            id: slide
            required property var modelData
            width: pages.width
            height: pages.height

            Image {
                anchors.fill: parent
                anchors.margins: MSpacing.md
                source: viewer.store.safeImageUrl((viewer.store.pickScreenshot(slide.modelData, 4096) || {}).src || "")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
            }
            Text {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - MSpacing.md * 2
                horizontalAlignment: Text.AlignHCenter
                visible: (slide.modelData.caption || "") !== ""
                text: slide.modelData.caption || ""
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                elide: Text.ElideRight
            }
        }
    }

    MPageIndicator {
        id: dots
        anchors.bottom: parent.bottom
        anchors.bottomMargin: MSpacing.lg
        anchors.horizontalCenter: parent.horizontalCenter
        count: viewer.screenshots.length
        currentIndex: pages.currentIndex
    }
}
