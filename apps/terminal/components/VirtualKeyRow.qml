import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: root

    property bool ctrlActive: false
    property bool altActive: false

    signal keyTriggered(int key, int modifiers)

    color: MColors.surface

    property var keyModel: [
        {
            label: "Esc",
            key: Qt.Key_Escape,
            isModifier: false,
            modifier: 0,
            requireCtrl: false
        },
        {
            label: "Tab",
            key: Qt.Key_Tab,
            isModifier: false,
            modifier: 0,
            requireCtrl: false
        },
        {
            label: "Ctrl",
            key: -1,
            isModifier: true,
            modifier: Qt.ControlModifier,
            requireCtrl: false
        },
        {
            label: "Alt",
            key: -1,
            isModifier: true,
            modifier: Qt.AltModifier,
            requireCtrl: false
        },
        {
            label: "▲",
            key: Qt.Key_Up,
            isModifier: false,
            modifier: 0,
            requireCtrl: false
        },
        {
            label: "▼",
            key: Qt.Key_Down,
            isModifier: false,
            modifier: 0,
            requireCtrl: false
        },
        {
            label: "◀",
            key: Qt.Key_Left,
            isModifier: false,
            modifier: 0,
            requireCtrl: false
        },
        {
            label: "▶",
            key: Qt.Key_Right,
            isModifier: false,
            modifier: 0,
            requireCtrl: false
        },
        {
            label: "C",
            key: Qt.Key_C,
            isModifier: false,
            modifier: 0,
            requireCtrl: true
        }
    ]

    ScrollView {
        id: scrollView
        anchors.fill: parent
        contentHeight: parent.height
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AlwaysOff

        Row {
            id: keyRow
            padding: MSpacing.sm
            spacing: MSpacing.xs
            height: parent.height

            Repeater {
                model: root.keyModel

                MButton {
                    width: 48
                    height: keyRow.height - (keyRow.padding * 2)
                    anchors.verticalCenter: parent.verticalCenter

                    required property int index
                    required property var modelData

                    text: modelData.label

                    variant: {
                        if (modelData.isModifier) {
                            if (modelData.modifier === Qt.ControlModifier && root.ctrlActive)
                                return "primary";
                            if (modelData.modifier === Qt.AltModifier && root.altActive)
                                return "primary";
                        }
                        return "secondary";
                    }

                    onClicked: {
                        if (modelData.isModifier) {
                            if (modelData.modifier === Qt.ControlModifier)
                                root.ctrlActive = !root.ctrlActive;
                            if (modelData.modifier === Qt.AltModifier)
                                root.altActive = !root.altActive;
                            return;
                        }

                        var modifiers = 0;
                        if (root.ctrlActive)
                            modifiers |= Qt.ControlModifier;
                        if (root.altActive)
                            modifiers |= Qt.AltModifier;

                        if (modelData.requireCtrl) {
                            modifiers |= Qt.ControlModifier;
                        }

                        root.keyTriggered(modelData.key, modifiers);
                    }
                }
            }
        }
    }
}
