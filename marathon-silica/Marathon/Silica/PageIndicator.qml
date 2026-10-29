import QtQuick
import Sailfish.Silica as S

// Dots for the pages of a horizontally paged view.
Item {
    id: root

    property int count
    property int currentIndex
    property bool interactive: false
    property color color: S.Theme.secondaryColor
    property color highlightColor: S.Theme.highlightColor

    readonly property real _dot: S.Theme.paddingMedium
    readonly property real _gap: S.Theme.paddingMedium

    function _select(index) {
        root.currentIndex = Math.max(0, Math.min(root.count - 1, index));
    }

    implicitWidth: count > 0 ? count * _dot + (count - 1) * _gap + 2 * _gap : 0
    implicitHeight: interactive ? Math.max(44, S.Theme.itemSizeExtraSmall / 2) : _dot + 2 * _gap
    activeFocusOnTab: interactive
    Accessible.role: Accessible.Indicator
    Accessible.name: qsTr("Page %1 of %2").arg(currentIndex + 1).arg(count)
    Keys.enabled: interactive
    Keys.onPressed: function (event) {
        switch (event.key) {
        case Qt.Key_Right:
            root._select(root.currentIndex + 1);
            break;
        case Qt.Key_Left:
            root._select(root.currentIndex - 1);
            break;
        case Qt.Key_Home:
            root._select(0);
            break;
        case Qt.Key_End:
            root._select(root.count - 1);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    Row {
        anchors.centerIn: parent
        spacing: root._gap

        Repeater {
            model: root.count

            Rectangle {
                required property int index

                width: root._dot
                height: root._dot
                radius: width / 2
                color: index === root.currentIndex ? root.highlightColor : root.color
                opacity: index === root.currentIndex ? 1 : S.Theme.opacityHigh
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        onClicked: function (mouse) {
            if (root.count > 0)
                root._select(Math.floor(mouse.x / (root.width / root.count)));
        }
    }

    FocusFrame {
        parent: root
    }
}
