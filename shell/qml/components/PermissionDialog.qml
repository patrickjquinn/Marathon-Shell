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
//   • No close X — Deny, Allow, or back (= Deny; for Android, cancel).
Item {
    id: permissionDialog

    property string appId: PermissionManager && PermissionManager.currentAppId ? PermissionManager.currentAppId : ""
    property var appData: appId ? AppStore.getApp(appId) : ({})
    property string appName: (appData && appData.name) ? appData.name : (appId || "Unknown App")
    property string appIconSource: (appData && appData.icon) ? appData.icon : ""
    // No publisher field in the manifest yet (see marathon-core/marathonappregistry.cpp).
    // For built-ins ("isProtected") the by-line is the OS itself; otherwise we fall back
    // to a derived name from the appId until manifests gain a publisher field.
    property var allPermissions: (PermissionManager && PermissionManager.currentPermissions) ? PermissionManager.currentPermissions : []
    // Declared but restricted to protected system apps: listed, never offered.
    property var refusedPermissions: (PermissionManager && PermissionManager.currentRefused) ? PermissionManager.currentRefused : []
    readonly property bool asking: allPermissions.length > 0
    // Android apps' prompts (deckardd): kind, once, accuracy, preciseDefault.
    property var options: (PermissionManager && PermissionManager.currentOptions) ? PermissionManager.currentOptions : ({})
    readonly property string kind: options.kind || ""

    onOptionsChanged: {
        onceSwitch.checked = false;
        preciseSwitch.checked = !!options.preciseDefault;
    }

    function answer(granted) {
        PermissionManager.respondWith(granted, granted && onceSwitch.visible && onceSwitch.checked, granted && preciseSwitch.visible && preciseSwitch.checked);
    }

    function permissionTitle(p) {
        return p ? PermissionManager.getPermissionLabel(p) : "";
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
            "alarms": "alarm",
            "telephony": "phone",
            "sms": "chat-circle",
            "bluetooth": "bluetooth",
            "sensors": "gauge",
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

    function phrase(list) {
        const titles = list.map(p => permissionTitle(p).toLowerCase());
        if (titles.length <= 2)
            return titles.join(" and ");
        return titles.slice(0, -1).join(", ") + ", and " + titles[titles.length - 1];
    }

    function descriptionText() {
        const parts = [];
        if (kind === "background")
            return allPermissions[0] === "location" ? qsTr("%1 wants to use your location all the time, even when you aren't using it.").arg(appName) : qsTr("%1 wants access to %2 all the time, even when you aren't using it.").arg(appName).arg(phrase(allPermissions));
        if (kind === "precise")
            return qsTr("%1 wants your precise location.").arg(appName);
        if (options.accuracy === "approximate")
            return qsTr("%1 is requesting access to your approximate location.").arg(appName);
        if (asking)
            parts.push(qsTr("%1 is requesting access to %2.").arg(appName).arg(phrase(allPermissions)));
        if (refusedPermissions.length > 0)
            parts.push(asking ? qsTr("It also asked for %1, which only Marathon's system apps can have.").arg(phrase(refusedPermissions)) : qsTr("%1 asked for %2, which only Marathon's system apps can have.").arg(appName).arg(phrase(refusedPermissions)));
        return parts.join(" ");
    }

    anchors.fill: parent
    z: 10000
    visible: opacity > 0
    opacity: (PermissionManager && PermissionManager.promptActive) ? 1 : 0

    // A full-screen system dialog on the ambience, which asks for app
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
            visible: permissionDialog.asking
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Deny")
            Accessible.onPressAction: permissionDialog.answer(false)
            anchors.left: parent.left
            width: parent.width / 2
            height: parent.height
            onClicked: permissionDialog.answer(false)

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
            Accessible.name: allowLabel.text
            Accessible.onPressAction: permissionDialog.answer(permissionDialog.asking)
            anchors.right: parent.right
            width: parent.width / 2
            height: parent.height
            onClicked: permissionDialog.answer(permissionDialog.asking)

            Silica.Label {
                id: allowLabel

                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: permissionDialog.asking ? qsTr("Allow") : qsTr("OK")
                font.pixelSize: Silica.Theme.fontSizeLarge
                color: Silica.Theme.highlightColor
            }
        }
    }

    // Scrolls when the permissions outgrow a short screen.
    Silica.SilicaFlickable {
        objectName: "permissionFlickable"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Constants.navBarHeight
        clip: true
        contentHeight: content.y + content.height + Silica.Theme.paddingLarge

        Column {
            id: content

            y: Silica.Theme.paddingLarge
            width: parent.width
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
                visible: permissionDialog.asking
                text: qsTr("Permissions")
            }

            Repeater {
                objectName: "askedPermissions"
                model: permissionDialog.allPermissions

                delegate: PermissionRow {}
            }

            // Android's "only this time" and precise location: choices,
            // so the prompt keeps its two actions.
            Silica.TextSwitch {
                id: onceSwitch

                objectName: "onceSwitch"
                visible: !!permissionDialog.options.once
                text: qsTr("Only this time")
                description: qsTr("%1 asks again next time it needs it").arg(permissionDialog.appName)
            }

            Silica.TextSwitch {
                id: preciseSwitch

                objectName: "preciseSwitch"
                visible: permissionDialog.options.accuracy === "choice"
                text: qsTr("Precise location")
                description: qsTr("When off, %1 learns only roughly where you are").arg(permissionDialog.appName)
            }

            Silica.SectionHeader {
                visible: permissionDialog.refusedPermissions.length > 0
                text: qsTr("Not allowed")
            }

            Repeater {
                objectName: "refusedPermissions"
                model: permissionDialog.refusedPermissions

                delegate: PermissionRow {
                    refused: true
                }
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                topPadding: Silica.Theme.paddingLarge
                wrapMode: Text.Wrap
                text: qsTr("You can change this anytime in Settings → Installed apps → %1.").arg(permissionDialog.appName)
                color: Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
            }
        }

        Silica.VerticalScrollDecorator {}
    }

    component PermissionRow: Item {
        id: permRow

        required property string modelData
        property bool refused: false

        width: parent ? parent.width : 0
        height: Math.max(Silica.Theme.itemSizeMedium, rowText.height + Silica.Theme.paddingMedium * 2)
        opacity: refused ? Silica.Theme.opacityHigh : 1

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
                text: permRow.refused ? qsTr("Only Marathon's system apps can have this") : permissionDialog.permissionSubtitle(permRow.modelData)
                visible: text.length > 0
                wrapMode: Text.Wrap
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
                color: Silica.Theme.secondaryColor
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.quick
        }
    }
}
