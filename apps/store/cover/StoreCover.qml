import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// A running install first, then the update count, else the placeholder.
CoverBackground {
    id: root

    required property var store
    readonly property string jobId: store.activeJobId
    readonly property var job: jobId !== "" ? store.jobFor(jobId) : null
    readonly property int updates: store.updateApps.length
    readonly property string mode: job !== null ? "job" : updates > 0 ? "updates" : "idle"

    signal searchRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: root.mode === "idle"
        text: qsTr("App Store")
        icon.source: "image://theme/icon-l-package"
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall
        visible: root.mode !== "idle"

        Label {
            objectName: "coverTitle"
            width: parent.width
            text: root.mode === "job" ? (root.job.state === "removing" ? qsTr("Removing") : root.job.state === "cancelling" ? qsTr("Cancelling") : root.job.percent >= 0 ? root.job.percent + "%" : qsTr("Waiting")) : root.updates
            font.pixelSize: Theme.fontSizeHuge
            fontSizeMode: Text.HorizontalFit
        }
        Label {
            objectName: "coverSubtitle"
            width: parent.width
            text: root.mode === "job" ? root.store.nameOf(root.jobId) : root.updates === 1 ? qsTr("update available") : qsTr("updates available")
            font.pixelSize: Theme.fontSizeMedium
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    CoverActionList {
        enabled: root.mode === "job" && root.store.canCancel(root.job)

        CoverAction {
            objectName: "cancelAction"
            iconSource: "image://theme/icon-cover-cancel"
            onTriggered: root.store.cancelJob(root.jobId)
        }
    }
    CoverActionList {
        enabled: root.mode === "updates"

        CoverAction {
            objectName: "updateAllAction"
            iconSource: "image://theme/icon-cover-sync"
            onTriggered: root.store.updateAll()
        }
    }
    CoverActionList {
        enabled: root.mode === "idle"

        CoverAction {
            objectName: "searchAction"
            iconSource: "image://theme/icon-cover-search"
            onTriggered: root.searchRequested()
        }
    }
}
