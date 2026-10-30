pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Ngf 1.0

Row {
    id: root

    enum ModState {
        Idle,
        Armed,
        Locked
    }

    property int ctrlState: VirtualKeyRow.Idle
    property int altState: VirtualKeyRow.Idle
    readonly property int modifiers: (ctrlState !== VirtualKeyRow.Idle ? Qt.ControlModifier : 0) | (altState !== VirtualKeyRow.Idle ? Qt.AltModifier : 0)

    readonly property var keys: [
        {
            label: "Esc" // i18n: literal (standard keyboard legend)
            ,
            name: qsTr("Escape"),
            key: Qt.Key_Escape,
            text: ""
        } // i18n: not user-facing
        ,
        {
            label: "Tab" // i18n: literal (standard keyboard legend)
            ,
            name: qsTr("Tab"),
            key: Qt.Key_Tab,
            text: ""
        } // i18n: not user-facing
        ,
        {
            label: "Ctrl" // i18n: literal (standard keyboard legend)
            ,
            name: qsTr("Control"),
            kind: "ctrl"
        } // i18n: not user-facing
        ,
        {
            label: "Alt" // i18n: literal (standard keyboard legend)
            ,
            name: qsTr("Alt"),
            kind: "alt"
        } // i18n: not user-facing
        ,
        {
            label: "|",
            name: qsTr("Pipe"),
            key: Qt.Key_Bar,
            text: "|",
            alt: "\\",
            altName: qsTr("backslash")
        },
        {
            label: "~",
            name: qsTr("Tilde"),
            key: Qt.Key_AsciiTilde,
            text: "~",
            alt: "`",
            altName: qsTr("backtick")
        },
        {
            icon: "left",
            name: qsTr("Left"),
            key: Qt.Key_Left,
            text: ""
        },
        {
            icon: "down",
            name: qsTr("Down"),
            key: Qt.Key_Down,
            text: ""
        },
        {
            icon: "up",
            name: qsTr("Up"),
            key: Qt.Key_Up,
            text: ""
        },
        {
            icon: "right",
            name: qsTr("Right"),
            key: Qt.Key_Right,
            text: ""
        }
    ]

    signal keyTriggered(int key, string text, int modifiers)

    // A tap arms a modifier for the next key, a long press locks it.
    function toggle(state) {
        return state === VirtualKeyRow.Idle ? VirtualKeyRow.Armed : VirtualKeyRow.Idle;
    }

    function consumeArmed() {
        if (ctrlState === VirtualKeyRow.Armed)
            ctrlState = VirtualKeyRow.Idle;
        if (altState === VirtualKeyRow.Armed)
            altState = VirtualKeyRow.Idle;
    }

    function trigger(key, text) {
        keyTriggered(key, text, modifiers);
        consumeArmed();
    }

    height: Theme.itemSizeSmall

    NonGraphicalFeedback {
        id: feedback
        event: "feedback_press"
    }

    Repeater {
        model: root.keys

        BackgroundItem {
            id: keyItem

            required property var modelData
            required property int index

            readonly property bool isModifier: !!modelData.kind
            readonly property int modState: modelData.kind === "ctrl" ? root.ctrlState : modelData.kind === "alt" ? root.altState : VirtualKeyRow.Idle

            objectName: "key_" + (modelData.label || modelData.icon)
            width: root.width / root.keys.length
            height: root.height
            highlighted: down
            Accessible.name: modelData.name
            Accessible.description: modelData.alt ? qsTr("Hold for %1").arg(modelData.altName) : isModifier ? qsTr("Tap for the next key, hold to lock") : ""
            Accessible.checkable: isModifier
            Accessible.checked: modState !== VirtualKeyRow.Idle

            onPressed: feedback.play()
            onClicked: {
                if (modelData.kind === "ctrl")
                    root.ctrlState = root.toggle(root.ctrlState);
                else if (modelData.kind === "alt")
                    root.altState = root.toggle(root.altState);
                else
                    root.trigger(modelData.key, modelData.text);
            }
            onPressAndHold: {
                if (modelData.kind === "ctrl")
                    root.ctrlState = VirtualKeyRow.Locked;
                else if (modelData.kind === "alt")
                    root.altState = VirtualKeyRow.Locked;
                else if (modelData.alt)
                    root.trigger(0, modelData.alt);
                else
                    root.trigger(modelData.key, modelData.text);
            }

            // The hold alternate sits beside the key's own character, as large
            // and on the same baseline, dimmed.
            Row {
                id: legend

                visible: !!keyItem.modelData.label
                anchors.centerIn: parent
                anchors.verticalCenterOffset: lockMark.visible ? -lockMark.height / 2 : 0
                spacing: Theme.paddingSmall

                Label {
                    id: keyLabel

                    objectName: "keyLabel"
                    text: keyItem.modelData.label || ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: keyItem.highlighted || keyItem.modState !== VirtualKeyRow.Idle ? Theme.highlightColor : Theme.primaryColor
                    font.underline: keyItem.modState === VirtualKeyRow.Armed
                }

                Label {
                    objectName: "altLabel"
                    visible: !!keyItem.modelData.alt
                    anchors.baseline: keyLabel.baseline
                    text: keyItem.modelData.alt || ""
                    font.pixelSize: keyLabel.font.pixelSize
                    color: keyItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }

            Icon {
                id: lockMark

                objectName: "lockMark"
                visible: keyItem.modState === VirtualKeyRow.Locked
                anchors.top: legend.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                sourceSize.width: Theme.iconSizeExtraSmall
                sourceSize.height: Theme.iconSizeExtraSmall
                source: "image://theme/icon-s-lock"
                highlighted: true
            }

            Icon {
                visible: !!keyItem.modelData.icon
                anchors.centerIn: parent
                source: keyItem.modelData.icon ? "image://theme/icon-m-" + keyItem.modelData.icon : ""
                highlighted: keyItem.highlighted
            }
        }
    }
}
