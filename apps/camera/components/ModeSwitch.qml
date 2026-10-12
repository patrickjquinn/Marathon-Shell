pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Row {
    id: root

    property string mode: "photo"

    signal selected(string mode)

    spacing: Theme.paddingLarge

    Repeater {
        model: ListModel {
            ListElement { mode: "photo"; glyph: "image://theme/icon-m-camera"; label: qsTr("Photo") }
            ListElement { mode: "video"; glyph: "image://theme/icon-m-video"; label: qsTr("Video") }
        }

        delegate: Column {
            id: option

            required property string mode
            required property string glyph
            required property string label
            readonly property bool current: root.mode === mode

            IconButton {
                objectName: option.mode + "Mode"
                anchors.horizontalCenter: parent.horizontalCenter
                highlighted: option.current || down
                icon.source: option.glyph
                icon.color: Theme.lightPrimaryColor
                Accessible.role: Accessible.RadioButton
                Accessible.name: option.label
                Accessible.checkable: true
                Accessible.checked: option.current
                onClicked: root.selected(option.mode)
            }

            Label {
                objectName: option.mode + "ModeLabel"
                anchors.horizontalCenter: parent.horizontalCenter
                text: option.label
                font.pixelSize: Theme.fontSizeExtraSmall
                color: option.current ? Theme.highlightColor : Theme.lightPrimaryColor
            }
        }
    }
}
