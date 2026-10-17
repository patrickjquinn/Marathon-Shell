pragma ComponentBehavior: Bound
import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// A notification's buttons, as GNOME Shell, Phosh and Android lay them out:
// at most three, "default" is the body tap, not a button. With the
// action-icons hint a key names an icon and its label is the accessible name.
Row {
    id: root

    property var actions: []
    property bool useIcons: false
    // Leads with a Reply button for an inline-reply sender.
    property bool reply: false
    // The width the buttons share; they shrink to fit it.
    property real availableWidth: 0
    readonly property var buttons: {
        const list = root.reply ? [
            {
                "key": "inline-reply",
                "label": qsTr("Reply")
            }
        ] : [];
        // The shell's own notifications name an action by "id".
        for (const action of root.actions || []) {
            const key = action && (action.key || action.id);
            if (key && key !== "default" && key !== "inline-reply")
                list.push({
                    "key": key,
                    "label": action.label
                });
        }
        return list.slice(0, 3);
    }

    signal invoked(string key)

    spacing: Silica.Theme.paddingSmall
    visible: buttons.length > 0

    Repeater {
        model: root.buttons

        delegate: Silica.BackgroundItem {
            id: button

            required property var modelData
            readonly property bool iconOnly: root.useIcons && modelData.key !== "inline-reply" && (icon.isGlyph || icon.hasImage)

            objectName: "notificationAction-" + modelData.key
            width: Math.min((iconOnly ? icon.width : label.implicitWidth) + Silica.Theme.paddingLarge * 2, (root.availableWidth - root.spacing * (root.buttons.length - 1)) / root.buttons.length)
            height: Silica.Theme.itemSizeExtraSmall
            Accessible.role: Accessible.Button
            Accessible.name: modelData.label || modelData.key
            onClicked: root.invoked(modelData.key)

            Silica.Label {
                id: label

                anchors.centerIn: parent
                width: Math.min(implicitWidth, button.width - Silica.Theme.paddingMedium * 2)
                visible: !button.iconOnly
                text: button.modelData.label || button.modelData.key
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeSmall
                truncationMode: Silica.TruncationMode.Fade
            }

            NotificationIcon {
                id: icon

                anchors.centerIn: parent
                visible: button.iconOnly
                source: root.useIcons ? button.modelData.key : ""
                fallback: ""
                size: Silica.Theme.iconSizeSmall
                color: Silica.Theme.highlightColor
            }
        }
    }
}
