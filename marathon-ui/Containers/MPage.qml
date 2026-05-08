import MarathonUI.Core
import MarathonUI.Theme
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
            height: 56
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
                    size: 24
                    color: MColors.textPrimary
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
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
            height: parent.height - (showTopBar ? 56 : 0) - (showBottomBar ? 72 : 0)
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
            height: 72
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
