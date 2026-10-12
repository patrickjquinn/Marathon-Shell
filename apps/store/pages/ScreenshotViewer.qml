pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// Screenshots full screen, one per page, swiped sideways.
Page {
    id: root

    property var store
    property var screenshots: []
    property int startIndex: 0
    property alias currentIndex: pages.currentIndex

    SilicaListView {
        id: pages

        objectName: "screenshotPages"
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        model: root.screenshots
        Component.onCompleted: positionViewAtIndex(root.startIndex, ListView.Beginning)
        delegate: Item {
            id: slide

            required property var modelData
            required property int index

            width: pages.width
            height: pages.height
            Accessible.role: Accessible.Graphic
            Accessible.name: (modelData.caption || "") !== "" ? modelData.caption : qsTr("Screenshot %1 of %2").arg(index + 1).arg(root.screenshots.length)

            Image {
                id: shot
                anchors.fill: parent
                anchors.topMargin: Theme.paddingLarge
                anchors.bottomMargin: caption.height + dots.height + Theme.paddingLarge
                source: root.store.safeImageUrl((root.store.pickScreenshot(slide.modelData, 4096) || {}).src || "")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
            }
            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Large
                running: shot.status === Image.Loading
            }
            Label {
                id: caption
                anchors.bottom: parent.bottom
                anchors.bottomMargin: dots.height + Theme.paddingLarge
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: slide.modelData.caption || ""
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    PageIndicator {
        id: dots
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.paddingLarge
        anchors.horizontalCenter: parent.horizontalCenter
        count: root.screenshots.length
        currentIndex: pages.currentIndex
    }
}
