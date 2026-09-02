import MarathonApp.Terminal
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    enum ModState {
        Idle,
        Armed,
        Locked
    }

    property int ctrlState: VirtualKeyRow.Idle
    property int altState: VirtualKeyRow.Idle
    readonly property bool ctrlActive: ctrlState !== VirtualKeyRow.Idle
    readonly property bool altActive: altState !== VirtualKeyRow.Idle

    readonly property var keyModel: [
        {
            "label": "Esc",
            "icon": "",
            "key": Qt.Key_Escape,
            "kind": "key"
        },
        {
            "label": "Tab",
            "icon": "",
            "key": Qt.Key_Tab,
            "kind": "key"
        },
        {
            "label": "Ctrl",
            "icon": "",
            "key": -1,
            "kind": "ctrl"
        },
        {
            "label": "Alt",
            "icon": "",
            "key": -1,
            "kind": "alt"
        },
        {
            "label": "|",
            "icon": "",
            "key": Qt.Key_Bar,
            "kind": "key",
            "popup": "\\"
        },
        {
            "label": "~",
            "icon": "",
            "key": Qt.Key_AsciiTilde,
            "kind": "key",
            "popup": "`"
        },
        {
            "label": "",
            "icon": "caret-left",
            "key": Qt.Key_Left,
            "kind": "arrow"
        },
        {
            "label": "",
            "icon": "caret-down",
            "key": Qt.Key_Down,
            "kind": "arrow"
        },
        {
            "label": "",
            "icon": "caret-up",
            "key": Qt.Key_Up,
            "kind": "arrow"
        },
        {
            "label": "",
            "icon": "caret-right",
            "key": Qt.Key_Right,
            "kind": "arrow"
        }
    ]

    signal keyTriggered(int key, int modifiers)

    function effectiveModifiers() {
        let m = 0;
        if (ctrlState !== VirtualKeyRow.Idle)
            m |= Qt.ControlModifier;
        if (altState !== VirtualKeyRow.Idle)
            m |= Qt.AltModifier;
        return m;
    }

    function consumeArmed() {
        if (ctrlState === VirtualKeyRow.Armed)
            ctrlState = VirtualKeyRow.Idle;
        if (altState === VirtualKeyRow.Armed)
            altState = VirtualKeyRow.Idle;
    }

    color: MColors.surface

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.sm
        anchors.rightMargin: MSpacing.sm
        anchors.topMargin: MSpacing.xs
        anchors.bottomMargin: MSpacing.xs
        spacing: MSpacing.xs

        Repeater {
            model: root.keyModel

            delegate: Rectangle {
                id: chip

                required property int index
                required property var modelData

                readonly property bool isCtrl: modelData.kind === "ctrl"
                readonly property bool isAlt: modelData.kind === "alt"
                readonly property bool isArrow: modelData.kind === "arrow"
                readonly property int chipState: {
                    if (isCtrl)
                        return root.ctrlState;
                    if (isAlt)
                        return root.altState;
                    return VirtualKeyRow.Idle;
                }
                readonly property bool locked: chipState === VirtualKeyRow.Locked
                readonly property bool armed: chipState === VirtualKeyRow.Armed

                Layout.fillWidth: true
                Layout.minimumWidth: Math.round(44 * Constants.scaleFactor)
                Layout.maximumWidth: Math.round(72 * Constants.scaleFactor)
                Layout.fillHeight: true
                radius: Math.round(8 * Constants.scaleFactor)
                color: locked ? MColors.marathonTealBright : (pressArea.pressed ? MColors.elevated : MColors.elev2)
                border.width: armed ? Math.max(1, Math.round(2 * Constants.scaleFactor)) : 1
                border.color: armed || locked ? MColors.marathonTealBright : MColors.borderSubtle

                Behavior on color {
                    ColorAnimation {
                        duration: MMotion.xs
                    }
                }

                Text {
                    visible: modelData.label.length > 0
                    anchors.centerIn: parent
                    text: modelData.label
                    font.pixelSize: Math.round(13 * Constants.scaleFactor)
                    font.family: MTypography.fontFamilyMono
                    font.weight: Font.Medium
                    color: chip.locked ? "#000000" : MColors.textPrimary
                }

                Icon {
                    visible: modelData.icon !== ""
                    anchors.centerIn: parent
                    name: modelData.icon
                    size: Math.round(18 * Constants.scaleFactor)
                    color: chip.locked ? "#000000" : MColors.textPrimary
                }

                Text {
                    visible: !!modelData.popup
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Math.round(3 * Constants.scaleFactor)
                    anchors.rightMargin: Math.round(5 * Constants.scaleFactor)
                    text: modelData.popup || ""
                    font.pixelSize: Math.round(9 * Constants.scaleFactor)
                    font.family: MTypography.fontFamilyMono
                    color: chip.locked ? Qt.rgba(0, 0, 0, 0.6) : MColors.textTertiary
                }

                MouseArea {
                    id: pressArea

                    anchors.fill: parent
                    onPressAndHold: {
                        if (chip.isCtrl) {
                            root.ctrlState = VirtualKeyRow.Locked;
                            HapticManager.medium();
                        } else if (chip.isAlt) {
                            root.altState = VirtualKeyRow.Locked;
                            HapticManager.medium();
                        }
                    }
                    onClicked: {
                        HapticManager.light();
                        if (chip.isCtrl) {
                            root.ctrlState = (root.ctrlState === VirtualKeyRow.Idle) ? VirtualKeyRow.Armed : VirtualKeyRow.Idle;
                            return;
                        }
                        if (chip.isAlt) {
                            root.altState = (root.altState === VirtualKeyRow.Idle) ? VirtualKeyRow.Armed : VirtualKeyRow.Idle;
                            return;
                        }
                        const mods = root.effectiveModifiers();
                        root.keyTriggered(modelData.key, mods);
                        root.consumeArmed();
                    }
                }
            }
        }
    }
}
