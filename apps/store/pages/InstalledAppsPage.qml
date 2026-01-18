import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: page

    anchors.fill: parent
    color: MColors.background

    MLabel {
        anchors.centerIn: parent
        text: "Installed Apps"
    }
}
