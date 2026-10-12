pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// The current mode sits on a highlight disc.
Rectangle {
    id: root

    property string mode: "photo"

    signal selected(string mode)

    width: row.width + 2 * Theme.paddingSmall
    height: row.height + 2 * Theme.paddingSmall
    radius: height / 2
    color: Theme.rgba(Theme.darkPrimaryColor, Theme.opacityLow)

    Row {
        id: row

        anchors.centerIn: parent

        Repeater {
            model: ListModel {
                ListElement { mode: "photo"; glyph: "image://theme/icon-m-camera"; label: qsTr("Photo") }
                ListElement { mode: "video"; glyph: "image://theme/icon-m-video"; label: qsTr("Video") }
            }

            delegate: IconButton {
                id: option

                required property string mode
                required property string glyph
                required property string label
                readonly property bool current: root.mode === mode

                objectName: mode + "Mode"
                width: Theme.itemSizeSmall
                height: Theme.itemSizeSmall
                icon.source: glyph
                icon.color: Theme.lightPrimaryColor
                Accessible.role: Accessible.RadioButton
                Accessible.name: label
                Accessible.checkable: true
                Accessible.checked: current
                onClicked: root.selected(mode)

                Rectangle {
                    z: -1
                    anchors.centerIn: parent
                    width: parent.width
                    height: width
                    radius: width / 2
                    color: Theme.highlightBackgroundColor
                    visible: option.current
                }
            }
        }
    }
}
