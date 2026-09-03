import MarathonUI.Core
import MarathonUI.Theme
import MarathonOS.Shell
import QtQuick

Rectangle {
    id: root

    property string title: ""
    property bool showBackButton: false
    property alias contentItem: scrollView.contentItem
    property alias content: contentContainer.data
    property bool showTopBar: true
    property bool showBottomBar: false
    property alias bottomBarContent: bottomBarContainer.data

    signal backClicked

    // Density factor — top bar / bottom bar / chevron size all scale with
    // the system. Without this, at 2× user scale every page had a tiny
    // chrome strip squeezing oversized children.
    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real topBarHeight: Math.round(56 * scaleFactor)
    readonly property real bottomBarHeight: Math.round(72 * scaleFactor)

    color: MColors.background
    // The page itself is a navigable region; Orca announces it as a Pane
    // with the page title. Override Accessible.* at the call site if needed.
    Accessible.role: Accessible.Pane
    Accessible.name: title.length > 0 ? title : "Page"

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: topBar

            visible: showTopBar
            width: parent.width
            height: root.topBarHeight
            color: MColors.elevated
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            z: 100

            Row {
                anchors.fill: parent
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                spacing: MSpacing.md

                Icon {
                    visible: showBackButton
                    name: "chevron-left"
                    size: Math.round(24 * root.scaleFactor)
                    color: MColors.textPrimary
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Math.round(12 * root.scaleFactor)
                        onClicked: root.backClicked()
                    }
                }

                Text {
                    text: root.title
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightDemiBold
                    font.family: MTypography.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Flickable {
            id: scrollView

            width: parent.width
            height: parent.height - (showTopBar ? root.topBarHeight : 0) - (showBottomBar ? root.bottomBarHeight : 0)
            contentHeight: contentContainer.height
            clip: true
            flickDeceleration: 5000
            maximumFlickVelocity: 2500

            Column {
                id: contentContainer

                width: parent.width
            }
        }

        Rectangle {
            id: bottomBar

            visible: showBottomBar
            width: parent.width
            height: root.bottomBarHeight
            color: MColors.elevated
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            z: 100

            Item {
                id: bottomBarContainer

                anchors.fill: parent
                anchors.margins: MSpacing.md
            }
        }
    }
}
