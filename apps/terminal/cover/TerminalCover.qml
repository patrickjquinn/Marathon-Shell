pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

CoverBackground {
    id: cover

    property var session
    property var lines: []

    signal newSessionRequested

    function refresh() {
        lines = session ? session.recentLines(3) : [];
    }

    onSessionChanged: refresh()

    // The screen has no change signal QML can see; poll while the cover shows.
    Timer {
        interval: 1000
        repeat: true
        running: cover.status === Cover.Active
        triggeredOnStart: true
        onTriggered: cover.refresh()
    }

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: cover.lines.length === 0
        text: qsTr("Terminal")
        icon.source: "image://theme/icon-m-keyboard"
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: Theme.paddingLarge
            bottomMargin: cover.coverActionArea.height + Theme.paddingMedium
        }
        spacing: Theme.paddingSmall

        Repeater {
            objectName: "coverLines"
            model: cover.lines

            Label {
                required property string modelData

                width: parent.width
                text: modelData
                font.family: "JetBrains Mono"
                font.pixelSize: Theme.fontSizeMedium
                truncationMode: TruncationMode.Fade
            }
        }
    }

    CoverActionList {
        CoverAction {
            objectName: "newSessionAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: cover.newSessionRequested()
        }
    }
}
