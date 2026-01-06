import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Item {
    id: permissionDialog

    property string appId: PermissionManager.currentAppId
    property string permission: PermissionManager.currentPermission
    property string appName: getAppName(appId)
    property string permissionDesc: PermissionManager.getPermissionDescription(permission)

    function getAppName(id) {
        // Try to get app name from registry
        if (!id)
            return "Unknown App";

        return AppStore.getAppName(id) || id;
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

    // CRITICAL: Must be parented to shell root overlay to appear above apps
    parent: Overlay.overlay
    anchors.fill: parent
    z: 10000
    visible: opacity > 0
    opacity: PermissionManager.promptActive ? 1 : 0

    // Backdrop (tap outside to deny once)
    Rectangle {
        anchors.fill: parent
        color: MColors.overlay

        MouseArea {
            anchors.fill: parent
            onClicked: PermissionManager.setPermission(permissionDialog.appId, permissionDialog.permission, false, false)
        }
    }

    // Card (match PowerMenu "popover" sizing: width constrained, height fits content)
    Rectangle {
        id: dialog

        readonly property real pad: MSpacing.xl

        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, Math.round(420 * Constants.scaleFactor))
        height: contentColumn.implicitHeight + pad * 2
        radius: MRadius.lg
        color: Qt.rgba(15 / 255, 15 / 255, 15 / 255, 0.98)
        border.width: Math.max(1, Math.round(Constants.scaleFactor))
        border.color: MColors.border
        scale: PermissionManager.promptActive ? 1 : 0.95

        // Inner glow
        Rectangle {
            anchors.fill: parent
            anchors.margins: Math.max(1, Math.round(Constants.scaleFactor))
            radius: parent.radius - Math.max(1, Math.round(Constants.scaleFactor))
            color: "transparent"
            border.width: Math.max(1, Math.round(Constants.scaleFactor))
            border.color: Qt.rgba(255 / 255, 255 / 255, 255 / 255, 0.05)
        }

        // Prevent click propagation
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            id: contentColumn

            anchors.centerIn: parent
            width: parent.width - dialog.pad * 2
            spacing: MSpacing.lg

            // Header (matches screenshot style)
            Row {
                width: parent.width
                spacing: MSpacing.md

                Text {
                    text: "Marathon OS - " + permissionDialog.appName
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightDemiBold
                    font.family: MTypography.fontFamily
                    color: MColors.textPrimary
                    elide: Text.ElideRight
                    width: parent.width - closeBtn.width - MSpacing.md
                }

                Item {
                    id: closeBtn

                    width: Math.round(32 * Constants.scaleFactor)
                    height: width

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.width / 2
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: Math.max(1, Math.round(Constants.scaleFactor))
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                    }

                    Icon {
                        anchors.centerIn: parent
                        name: "x"
                        size: Math.round(18 * Constants.scaleFactor)
                        color: MColors.textPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: PermissionManager.setPermission(permissionDialog.appId, permissionDialog.permission, false, false)
                    }
                }
            }

            // App info
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: MSpacing.md

                Rectangle {
                    width: Math.round(48 * Constants.scaleFactor)
                    height: width
                    radius: Math.round(12 * Constants.scaleFactor)
                    color: MColors.bb10Card
                    border.color: MColors.borderGlass
                    border.width: Math.max(1, Math.round(Constants.scaleFactor))

                    Text {
                        anchors.centerIn: parent
                        text: permissionDialog.appName.length > 0 ? permissionDialog.appName.charAt(0).toUpperCase() : "?"
                        font.pixelSize: Math.round(24 * Constants.scaleFactor)
                        font.weight: Font.Bold
                        color: MColors.marathonTeal
                    }
                }

                Column {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "wants to:"
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                    }
                }
            }

            // Permission description
            Rectangle {
                width: parent.width
                radius: MRadius.md
                color: MColors.bb10Elevated
                border.width: Math.max(1, Math.round(Constants.scaleFactor))
                border.color: MColors.borderSubtle
                implicitHeight: descRow.implicitHeight + MSpacing.lg * 2

                Row {
                    id: descRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: MSpacing.lg
                    spacing: MSpacing.md

                    Text {
                        text: "●"
                        font.pixelSize: Math.round(22 * Constants.scaleFactor)
                        color: MColors.marathonTeal
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: permissionDialog.permissionDesc
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        width: parent.width - Math.round(26 * Constants.scaleFactor)
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Text {
                width: parent.width
                text: "You can change this permission later in Settings."
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                color: MColors.textSecondary
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Column {
                width: parent.width
                spacing: MSpacing.md

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

        Behavior on scale {
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.quick
        }
    }
}
