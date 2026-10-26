pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// Off you go: the coordinator reads the flick on the bar; Enter goes too.
Item {
    id: root

    signal done

    Keys.onReturnPressed: root.done()
    Keys.onEnterPressed: root.done()
    onVisibleChanged: {
        if (visible)
            forceActiveFocus();
    }

    Column {
        x: Silica.Theme.horizontalPageMargin
        width: parent.width - 2 * x
        anchors.verticalCenter: parent.verticalCenter
        spacing: Silica.Theme.paddingMedium

        Silica.Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            //: Heading of the last setup step
            text: qsTr("You're ready")
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeExtraLarge
            wrapMode: Text.Wrap
        }

        Silica.Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            //: Last setup step: how to finish
            text: qsTr("Flick the bar up, the way you began, to go home.")
            color: Silica.Theme.secondaryHighlightColor
            wrapMode: Text.Wrap
        }
    }
}
