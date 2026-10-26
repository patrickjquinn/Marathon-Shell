import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// The open-tab count inside a rounded square, as Sailfish Browser draws it.
BackgroundItem {
    id: root

    property int count: 0

    Accessible.name: count === 1 ? qsTr("1 tab open. Show tabs") : qsTr("%1 tabs open. Show tabs").arg(count)

    Rectangle {
        anchors.centerIn: parent
        width: Theme.iconSizeSmallPlus
        height: width
        radius: Theme.paddingSmall
        color: "transparent"
        border.width: Math.max(2, Math.round(Theme.pixelRatio * 2))
        border.color: root.highlighted ? Theme.highlightColor : Theme.primaryColor

        Label {
            anchors.centerIn: parent
            text: root.count > 99 ? ":D" : root.count // i18n: not user-facing
            font.pixelSize: Theme.fontSizeSmall
            color: root.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
    }
}
