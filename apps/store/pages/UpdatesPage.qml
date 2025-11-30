import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: page
    anchors.fill: parent
    color: MColors.background

    MLabel {
        anchors.centerIn: parent
        text: "Updates"
    }
}
