import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// The detail page's install action. Label and behaviour follow the app's
// install state; while flatpak runs it becomes progress of the same
// footprint, with a cancel button beside the full-width bar.
Item {
    id: root

    required property var store
    required property string appId
    // The detail page's full-width variant: a ProgressBar instead of a circle.
    property bool large: false

    readonly property var job: store.jobFor(appId)
    readonly property bool busy: job !== null && store.jobRunning(job)
    readonly property string action: {
        if (job !== null && job.state === "failed")
            return "retry";
        if (store.hasUpdate(appId))
            return "update";
        if (store.isInstalled(appId))
            return store.canOpen(appId) ? "open" : "";
        return "get";
    }
    readonly property string progressText: {
        if (!job)
            return "";
        if (job.state === "removing")
            return qsTr("Removing");
        if (job.state === "cancelling")
            return qsTr("Cancelling");
        return job.percent >= 0 ? qsTr("Installing %1%").arg(job.percent) : qsTr("Waiting");
    }

    function trigger() {
        if (action === "open")
            store.openApp(appId);
        else if (action === "update")
            store.updateApp(appId);
        else
            store.installApp(appId);
    }

    implicitWidth: large ? Theme.buttonWidthMedium : Theme.buttonWidthTiny
    implicitHeight: large && busy ? bar.height : action === "" ? 0 : button.height

    Button {
        id: button

        objectName: "getButton"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        preferredWidth: root.large ? Theme.buttonWidthMedium : Theme.buttonWidthTiny
        visible: !root.busy && root.action !== ""
        text: ({
                "get": qsTr("Get"),
                "open": qsTr("Open"),
                "update": qsTr("Update"),
                "retry": qsTr("Retry")
            })[root.action]
        onClicked: root.trigger()
    }

    ProgressCircle {
        anchors.centerIn: parent
        width: Theme.iconSizeMedium
        height: width
        visible: !root.large && root.busy && root.job.percent >= 0
        value: root.job && root.job.percent > 0 ? root.job.percent / 100 : 0
        Accessible.role: Accessible.ProgressBar
        Accessible.name: root.progressText
    }
    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Small
        running: !root.large && root.busy && !(root.job.percent >= 0)
        visible: running
        Accessible.role: Accessible.ProgressBar
        Accessible.name: root.progressText
    }

    ProgressBar {
        id: bar

        objectName: "installProgress"
        width: parent.width - (cancel.visible ? cancel.width : 0)
        visible: root.large && root.busy
        leftMargin: 0
        rightMargin: 0
        indeterminate: !(root.job && root.job.percent >= 0)
        value: root.job && root.job.percent > 0 ? root.job.percent / 100 : 0
        label: root.progressText
        Accessible.role: Accessible.ProgressBar
        Accessible.name: root.progressText
    }
    IconButton {
        id: cancel

        objectName: "cancelButton"
        anchors.right: parent.right
        anchors.verticalCenter: bar.verticalCenter
        visible: root.large && root.busy && root.store.canCancel(root.job)
        icon.source: "image://theme/icon-m-cancel"
        Accessible.name: root.store.isInstalled(root.appId) ? qsTr("Cancel update") : qsTr("Cancel installation")
        onClicked: root.store.cancelJob(root.appId)
    }
}
