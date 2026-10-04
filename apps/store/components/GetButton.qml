import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// The action every app row and the detail page share. Label and behaviour
// follow the app's install state; while flatpak runs it becomes a progress
// pill of the same footprint, so rows don't reflow mid-install.
Item {
    id: root

    required property var store
    required property string appId
    property bool large: false
    // The solid teal button is for a page's main action (hero, detail
    // header). In lists it is a quiet pill so a column of rows isn't a
    // column of teal blocks.
    property bool prominent: large

    readonly property var job: store.jobFor(appId)
    readonly property bool busy: job !== null && (job.state === "pending" || job.state === "installing" || job.state === "removing")
    readonly property string action: {
        if (job !== null && job.state === "failed")
            return "retry";
        if (store.hasUpdate(appId))
            return "update";
        if (store.isInstalled(appId))
            return "open";
        return "get";
    }

    implicitWidth: Math.max(button.implicitWidth, store.dp(large ? 112 : 76))
    implicitHeight: button.implicitHeight

    MButton {
        id: button

        anchors.fill: parent
        visible: !root.busy
        size: root.large ? "default" : "compact"
        readonly property bool solid: root.prominent && root.action !== "open"
        variant: solid ? "primary" : "secondary"
        // Teal text marks the quiet pill as an action; "transparent" keeps
        // MButton's own colour for Open and for the solid button.
        textColor: !solid && root.action !== "open" ? MColors.marathonTealBright : "transparent"
        text: ({
                "get": "Get",
                "open": "Open",
                "update": "Update",
                "retry": "Retry"
            })[root.action]
        onClicked: {
            if (root.action === "open")
                root.store.openApp(root.appId);
            else if (root.action === "update")
                root.store.updateApp(root.appId);
            else
                root.store.installApp(root.appId);
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.busy
        radius: height / 2
        color: MColors.elev2
        border.width: 1
        border.color: MColors.tealBorder
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.job && root.job.percent > 0 ? parent.width * root.job.percent / 100 : 0
            color: MColors.tealTintDark

            Behavior on width {
                NumberAnimation {
                    duration: MMotion.quick
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: {
                if (!root.job)
                    return "";
                if (root.job.state === "removing")
                    return "Removing";
                return root.job.percent >= 0 ? root.job.percent + "%" : "Waiting";
            }
            color: MColors.marathonTealBright
            font.family: MTypography.fontFamily
            font.pixelSize: root.large ? MTypography.sizeSubhead : MTypography.sizeFootnote
            font.weight: Font.DemiBold
        }
    }
}
