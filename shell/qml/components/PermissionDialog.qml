pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

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
            "location": "map-pin",
            "camera": "camera",
            "microphone": "microphone",
            "contacts": "address-book",
            "calendar": "calendar",
            "storage": "archive",
            "notifications": "bell",
            "telephony": "phone",
            "sms": "chat-circle",
            "bluetooth": "bluetooth",
            // Phosphor doesn't have "cog"; use "gear". The empty placeholder
            // square in the System permission row was a missing glyph, not
            // styling.
            "system": "gear"
        };
        return m[p] || "shield";
    }

    function permissionSubtitle(p) {
        if (!p)
            return "";

        return PermissionManager.getPermissionDescription(p);
    }

    function descriptionText() {
        // The current single permission is the legacy single-prompt path.
        // Modern callers (Browser cold-start, Maps first-launch) batch
        // permission requests via currentPermissions — show all of them
        // by name so the body matches the inline list above instead of
        // mentioning only the first item and looking truncated.
        const list = allPermissions && allPermissions.length > 0 ? allPermissions : (permission ? [permission] : []);
        if (list.length === 0)
            return "";

        const titles = list.map(p => permissionTitle(p).toLowerCase());
        let phrase;
        if (titles.length === 1) {
            phrase = titles[0];
        } else if (titles.length === 2) {
            phrase = titles[0] + " and " + titles[1];
        } else {
            phrase = titles.slice(0, -1).join(", ") + ", and " + titles[titles.length - 1];
        }
        return appName + " is requesting access to " + phrase + ".";
    }

    anchors.fill: parent
    z: 10000
    visible: opacity > 0
    opacity: (PermissionManager && PermissionManager.promptActive) ? 1 : 0

    // A full-screen system dialog on the ambience, as Sailfish asks for app
    // permissions: Deny and Allow in the header corners, the app, then each
    // permission requested.
    KeelAmbienceBackground {
        width: permissionDialog.width
        height: permissionDialog.height
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
    }

    // Swallow touches meant for whatever is underneath.
    MouseArea {
        anchors.fill: parent
    }

    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight
        height: Silica.Theme.itemSizeLarge

        Silica.BackgroundItem {
            objectName: "denyButton"
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Deny")
            Accessible.onPressAction: PermissionManager.setPermissions(permissionDialog.appId, permissionDialog.allPermissions, false, true)
            anchors.left: parent.left
            width: parent.width / 2
            height: parent.height
            onClicked: PermissionManager.setPermissions(permissionDialog.appId, permissionDialog.allPermissions, false, true)

            Silica.Label {
                anchors.left: parent.left
                anchors.leftMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Deny")
                font.pixelSize: Silica.Theme.fontSizeLarge
                color: parent.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            }
        }
        Silica.BackgroundItem {
            objectName: "allowButton"
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Allow")
            Accessible.onPressAction: PermissionManager.setPermissions(permissionDialog.appId, permissionDialog.allPermissions, true, true)
            anchors.right: parent.right
            width: parent.width / 2
            height: parent.height
            onClicked: PermissionManager.setPermissions(permissionDialog.appId, permissionDialog.allPermissions, true, true)

            Silica.Label {
                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Allow")
                font.pixelSize: Silica.Theme.fontSizeLarge
                color: Silica.Theme.highlightColor
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Silica.Theme.paddingLarge
        spacing: Silica.Theme.paddingMedium

        MAppIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            source: permissionDialog.appIconSource
            size: Silica.Theme.iconSizeLauncher
            width: size
            height: size
        }

        Silica.Label {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            horizontalAlignment: Text.AlignHCenter
            text: permissionDialog.appName
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeLarge
            truncationMode: Silica.TruncationMode.Fade
        }

        Silica.Label {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: permissionDialog.descriptionText()
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
        }

        Silica.SectionHeader {
            text: qsTr("Permissions")
        }

        Repeater {
            model: permissionDialog.allPermissions && permissionDialog.allPermissions.length > 0
                   ? permissionDialog.allPermissions
                   : (permissionDialog.permission ? [permissionDialog.permission] : [])

            delegate: Item {
                id: permRow

                required property string modelData

                width: parent.width
                height: Math.max(Silica.Theme.itemSizeMedium, rowText.height + Silica.Theme.paddingMedium * 2)

                GlyphIcon {
                    id: rowIcon

                    x: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    name: permissionDialog.permissionIconName(permRow.modelData)
                    size: Silica.Theme.iconSizeSmall
                    color: Silica.Theme.primaryColor
                }

                Column {
                    id: rowText

                    anchors.left: rowIcon.right
                    anchors.leftMargin: Silica.Theme.paddingLarge
                    anchors.right: parent.right
                    anchors.rightMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        width: parent.width
                        text: permissionDialog.permissionTitle(permRow.modelData)
                        truncationMode: Silica.TruncationMode.Fade
                    }
                    Silica.Label {
                        width: parent.width
                        text: permissionDialog.permissionSubtitle(permRow.modelData)
                        visible: text.length > 0
                        wrapMode: Text.Wrap
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                        color: Silica.Theme.secondaryColor
                    }
                }
            }
        }

        Silica.Label {
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            topPadding: Silica.Theme.paddingLarge
            wrapMode: Text.Wrap
            text: qsTr("You can change this anytime in Settings → Apps → %1.").arg(permissionDialog.appName)
            color: Silica.Theme.secondaryColor
            font.pixelSize: Silica.Theme.fontSizeExtraSmall
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.quick
        }
    }
}
