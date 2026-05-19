import MarathonUI.Core
import MarathonUI.Theme
import MarathonOS.Shell 1.0
import QtQuick

// Marathon DS · PermissionDialog (screens-shell.jsx PermissionDialog L1028).
//
// Layout per spec (top → bottom):
//   1. Header row  — 64×64 app-icon squircle (left) + name 20/500/-0.3 + by-line 13/secondary
//   2. Divider     — 1 px w-04, full width
//   3. Permission  — single inline list row (32×32 elev-3 chip + title + subtitle, no chev)
//   4. Description — 14/lineHeight 1.5, padding 16 22 4
//   5. Caption     — 12/secondary, padding 4 22 0
//   6. Actions     — two side-by-side buttons: Deny (secondary) + Allow (primary), gap 10
//
// Hard rules from the DS:
//   • App's own icon at the top — never a letter monogram.
//   • Header left-aligned, NOT centered.
//   • Maximum 2 actions per dialog. No "Allow Once / Allow While Using / Don't Allow."
//   • No "Marathon OS - {AppName}" header. The user already knows whose phone this is.
//   • No close X — the only way out is Deny or Allow.
Item {
    id: permissionDialog

    property string appId: PermissionManager && PermissionManager.currentAppId ? PermissionManager.currentAppId : ""
    property var appData: appId ? AppStore.getApp(appId) : ({})
    property string appName: (appData && appData.name) ? appData.name : (appId || "Unknown App")
    property string appIconSource: (appData && appData.icon) ? appData.icon : ""
    // No publisher field in the manifest yet (see marathon-core/marathonappregistry.cpp).
    // For built-ins ("isProtected") the by-line is the OS itself; otherwise we fall back
    // to a derived name from the appId until manifests gain a publisher field.
    property bool isInternal: appId.length > 0 && AppStore.isInternalApp(appId)
    property string byLine: {
        if (isInternal)
            return "by Marathon OS";

        if (appData && appData.publisher)
            return "by " + appData.publisher;

        return "by " + (appName || appId);
    }
    property string permission: (PermissionManager && PermissionManager.currentPermission) ? PermissionManager.currentPermission : ""
    property var allPermissions: (PermissionManager && PermissionManager.currentPermissions) ? PermissionManager.currentPermissions : []

    function permissionTitle(p) {
        if (!p)
            return "";

        return p.charAt(0).toUpperCase() + p.slice(1);
    }

    function permissionIconName(p) {
        const m = {
            "network": "wifi",
            "location": "map_pin",
            "camera": "camera",
            "microphone": "mic",
            "contacts": "contacts",
            "calendar": "calendar",
            "storage": "archive",
            "notifications": "bell",
            "telephony": "phone",
            "sms": "message",
            "bluetooth": "bluetooth",
            "system": "cog"
        };
        return m[p] || "shield";
    }

    function permissionSubtitle(p) {
        if (!p)
            return "";

        return PermissionManager.getPermissionDescription(p);
    }

    function descriptionText() {
        if (!permission)
            return "";

        return appName + " is requesting access to " + permissionTitle(permission).toLowerCase() + ".";
    }

    anchors.fill: parent
    z: 10000
    visible: opacity > 0
    opacity: (PermissionManager && PermissionManager.promptActive) ? 1 : 0

    // Scrim — dim the system under the dialog (DS rgba(0,0,0,0.72)). Tap-outside dismisses.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.72)

        MouseArea {
            anchors.fill: parent
            onClicked: PermissionManager.setPermissions(permissionDialog.appId, permissionDialog.allPermissions, false, false)
        }
    }

    // Dialog body. Max 340 design-px wide per DS Dialogs spec.
    Rectangle {
        id: dialog

        anchors.centerIn: parent
        width: Math.min(parent.width - Math.round(48 * Constants.scaleFactor), Math.round(340 * Constants.scaleFactor))
        height: contentColumn.implicitHeight
        radius: MRadius.md
        color: MColors.elev2
        scale: (PermissionManager && PermissionManager.promptActive) ? 1.0 : 0.96

        // Cast-down shadow per DS Dialogs · "0 24px 60px -20px rgba(0,0,0,0.8)".
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: Math.round(8 * Constants.scaleFactor)
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.55)
            z: -1
            opacity: 0.6
        }

        // Double-edge stroke: outer dark hairline + inset top-edge w-08 highlight.
        // DS Cards · "0 0 0 1px var(--border-dark), inset 0 1px 0 var(--w-08)".
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 1)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            anchors.topMargin: 1
            height: 1
            color: MColors.whiteOverlay08
        }

        // Block scrim-tap on the dialog body itself.
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            id: contentColumn

            width: parent.width
            spacing: 0

            // 1. Header: 64×64 app icon + name + by-line. Padding 24/22/18 per spec.
            Item {
                width: parent.width
                height: Math.max(headerIcon.height, headerText.implicitHeight) + Math.round(42 * Constants.scaleFactor)

                Item {
                    id: headerIcon

                    width: Math.round(64 * Constants.scaleFactor)
                    height: width
                    anchors.left: parent.left
                    anchors.leftMargin: Math.round(22 * Constants.scaleFactor)
                    anchors.top: parent.top
                    anchors.topMargin: Math.round(24 * Constants.scaleFactor)

                    MAppIcon {
                        anchors.fill: parent
                        source: permissionDialog.appIconSource
                        size: parent.width
                    }
                }

                Column {
                    id: headerText

                    anchors.left: headerIcon.right
                    anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
                    anchors.right: parent.right
                    anchors.rightMargin: Math.round(22 * Constants.scaleFactor)
                    anchors.verticalCenter: headerIcon.verticalCenter
                    spacing: 2

                    Text {
                        text: permissionDialog.appName
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: Math.round(20 * Constants.scaleFactor)
                        font.weight: MTypography.weightMedium
                        font.letterSpacing: -0.3
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: permissionDialog.byLine
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: Math.round(13 * Constants.scaleFactor)
                        font.weight: MTypography.weightRegular
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }

            // 2. Divider hairline (w-04, full width).
            Rectangle {
                width: parent.width
                height: 1
                color: MColors.whiteOverlay04
            }

            // 3. Permission row — 32×32 icon chip + title + subtitle, no chevron.
            // DS .m-row: padding 14/16, gap 14, min-height 60.
            Item {
                width: parent.width
                height: Math.max(Math.round(60 * Constants.scaleFactor), permissionRow.implicitHeight + Math.round(28 * Constants.scaleFactor))

                Row {
                    id: permissionRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Math.round(22 * Constants.scaleFactor)
                    anchors.rightMargin: Math.round(22 * Constants.scaleFactor)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.round(14 * Constants.scaleFactor)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(32 * Constants.scaleFactor)
                        height: width
                        radius: MRadius.md
                        color: MColors.elev3

                        Icon {
                            anchors.centerIn: parent
                            name: permissionDialog.permissionIconName(permissionDialog.permission)
                            size: Math.round(18 * Constants.scaleFactor)
                            color: MColors.textPrimary
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Math.round(46 * Constants.scaleFactor)
                        spacing: 2

                        Text {
                            text: permissionDialog.permissionTitle(permissionDialog.permission)
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: Math.round(15 * Constants.scaleFactor)
                            font.weight: MTypography.weightMedium
                            font.letterSpacing: -0.1
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: permissionDialog.permissionSubtitle(permissionDialog.permission)
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: Math.round(13 * Constants.scaleFactor)
                            font.weight: MTypography.weightRegular
                            elide: Text.ElideRight
                            width: parent.width
                            visible: text.length > 0
                        }
                    }
                }
            }

            // Bottom hairline above description block (matches Row default border).
            Rectangle {
                width: parent.width
                height: 1
                color: MColors.whiteOverlay04
            }

            // 4. Description sentence (14/lineHeight 1.5) + 5. caption (12/secondary).
            Item {
                width: parent.width
                height: descCol.implicitHeight + Math.round(20 * Constants.scaleFactor)

                Column {
                    id: descCol

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: Math.round(22 * Constants.scaleFactor)
                    anchors.rightMargin: Math.round(22 * Constants.scaleFactor)
                    anchors.topMargin: Math.round(16 * Constants.scaleFactor)
                    spacing: Math.round(6 * Constants.scaleFactor)

                    Text {
                        width: parent.width
                        text: permissionDialog.descriptionText()
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: Math.round(14 * Constants.scaleFactor)
                        font.weight: MTypography.weightRegular
                        lineHeight: 1.5
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        text: "You can change this anytime in Settings → Apps → " + permissionDialog.appName + "."
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: Math.round(12 * Constants.scaleFactor)
                        font.weight: MTypography.weightRegular
                        lineHeight: 1.45
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // 6. Actions: Deny secondary + Allow primary, side-by-side, flex:1.
            Item {
                width: parent.width
                height: Math.round(45 * Constants.scaleFactor) + Math.round(32 * Constants.scaleFactor)

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
                    anchors.rightMargin: Math.round(16 * Constants.scaleFactor)
                    anchors.topMargin: Math.round(16 * Constants.scaleFactor)
                    spacing: Math.round(10 * Constants.scaleFactor)

                    MButton {
                        width: (parent.width - Math.round(10 * Constants.scaleFactor)) / 2
                        text: "Deny"
                        variant: "secondary"
                        onClicked: PermissionManager.setPermissions(permissionDialog.appId, permissionDialog.allPermissions, false, true)
                    }

                    MButton {
                        width: (parent.width - Math.round(10 * Constants.scaleFactor)) / 2
                        text: "Allow"
                        variant: "primary"
                        onClicked: PermissionManager.setPermissions(permissionDialog.appId, permissionDialog.allPermissions, true, true)
                    }
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
