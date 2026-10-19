import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings

Dialog {
    id: dialog

    objectName: "androidResetDialog"

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Reset")
            title: qsTr("Reset Android?")
        }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            bottomPadding: Theme.paddingLarge
            wrapMode: Text.Wrap
            color: Theme.highlightColor
            text: qsTr("Every Android app is removed, with everything it stores: accounts, messages, downloads and settings.")
        }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("%n Android apps are installed. This can't be undone; your Marathon apps and files stay as they are.", "", AndroidApps.apps.length)
        }
    }
}
