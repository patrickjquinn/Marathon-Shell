import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: page

    property string appId: ""

    anchors.fill: parent
    color: MColors.background

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        MLabel {
            text: "App Details: " + appId
            Layout.margins: MSpacing.md
        }
    }
}
