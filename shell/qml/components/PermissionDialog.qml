import QtQuick
import QtQuick.Controls
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import MarathonOS.Shell

MModal {
    id: permissionDialog

    // CRITICAL: Must be parented to shell root overlay to appear above apps
    parent: Overlay.overlay

    // MModal uses 'showing' property for visibility/animation
    showing: PermissionManager.promptActive

    property string appId: PermissionManager.currentAppId
    property string permission: PermissionManager.currentPermission
    property string appName: getAppName(appId)
    property string permissionDesc: PermissionManager.getPermissionDescription(permission)

    // MModal already handles width/height in its internal container,
    // but we can override content size if needed.
    // However, MModal's contentItem fills the remaining space.
    // Let's just let MModal handle the container size.

    title: "Permission Request"

    function getAppName(id) {
        // Try to get app name from registry
        if (!id)
            return "Unknown App";
        return AppStore.getAppName(id) || id;
    }

    Column {
        width: parent.width
        spacing: 20

        // App info
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 15

            // App icon (if available)
            Rectangle {
                width: 48
                height: 48
                radius: 12
                color: MColors.bb10Card
                border.color: MColors.borderGlass
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: permissionDialog.appName.charAt(0).toUpperCase()
                    font.pixelSize: 24
                    font.weight: Font.Bold
                    color: MColors.marathonTeal
                }
            }

            Column {
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: permissionDialog.appName
                    font.pixelSize: 16
                    font.weight: Font.Medium
                }

                Text {
                    text: "wants to:"
                    font.pixelSize: 14
                    color: MColors.textSecondary
                }
            }
        }

        // Permission description
        Rectangle {
            width: parent.width
            height: permissionDescText.height + 40
            radius: 8
            color: MColors.bb10Elevated

            Row {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 12

                Text {
                    text: "●"
                    font.pixelSize: 24
                    color: MColors.marathonTeal
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: permissionDescText
                    text: permissionDialog.permissionDesc
                    font.pixelSize: 14
                    width: parent.width - 36
                    wrapMode: Text.WordWrap
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Warning text
        Text {
            width: parent.width
            text: "You can change this permission later in Settings."
            font.pixelSize: 12
            color: MColors.textSecondary
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // Action buttons
        Column {
            width: parent.width
            spacing: 10

            MButton {
                text: "Allow"
                variant: "primary"
                width: parent.width
                onClicked: PermissionManager.setPermission(permissionDialog.appId, permissionDialog.permission, true, true)
            }

            MButton {
                text: "Allow Once"
                variant: "secondary"
                width: parent.width
                onClicked: PermissionManager.setPermission(permissionDialog.appId, permissionDialog.permission, true, false)
            }

            MButton {
                text: "Deny"
                variant: "tertiary"
                width: parent.width
                onClicked: PermissionManager.setPermission(permissionDialog.appId, permissionDialog.permission, false, true)
            }
        }
    }

    function getPermissionIcon(perm) {
        const icons = {
            "network": "network",
            "location": "location_on",
            "camera": "camera_alt",
            "microphone": "mic",
            "contacts": "contacts",
            "calendar": "event",
            "storage": "folder",
            "notifications": "notifications",
            "telephony": "phone",
            "sms": "message",
            "bluetooth": "bluetooth",
            "system": "settings"
        };
        return icons[perm] || "help";
    }
}
