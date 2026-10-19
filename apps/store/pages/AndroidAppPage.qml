pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// An Android app: from F-Droid's catalogue (`app`), or an .apk opened from a
// file (`apkPath`, described by the handler's apk-inspect.json). Installs go
// through Deckard; Android's own installer never shows.
Page {
    id: root

    property var store
    property var app: null
    property string apkPath: ""

    readonly property bool fromFile: apkPath !== ""
    readonly property var info: fromFile ? store.apkInfo : null
    readonly property bool inspecting: fromFile && info === null
    readonly property bool fileOk: fromFile && info !== null && info.ok === true
    readonly property string pkg: fromFile ? (fileOk ? info.pkg : "") : (app ? app.pkg : "")
    readonly property string appId: pkg !== "" ? "android:" + pkg : ""
    readonly property string name: fromFile ? (fileOk ? (info.name || info.pkg) : "") : (app ? app.name : "")
    readonly property string versionName: fromFile ? (fileOk ? info.versionName : "") : (app ? app.version.name : "")
    readonly property var permissionNames: fromFile ? (fileOk ? info.permissions : []) : (app ? app.version.permissions : [])
    readonly property var permissions: store.describeAndroidPermissions(permissionNames)
    readonly property var antiFeatures: !fromFile && app ? app.antiFeatures : []
    readonly property bool installed: appId !== "" && store.isInstalled(appId)
    readonly property var job: appId !== "" ? store.jobFor(appId) : null
    readonly property bool busy: job !== null && store.jobRunning(job)
    readonly property bool isUpdate: fromFile && fileOk && info.installedVersionCode !== null && info.installedVersionCode !== undefined

    function uninstall() {
        remorse.execute(qsTr("Uninstalled %1").arg(root.name), function () {
            root.store.uninstallApp(root.appId);
        });
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: body.height + Theme.paddingLarge

        PullDownMenu {
            visible: root.installed || (!root.fromFile && root.app && root.app.website !== "")
            MenuItem {
                text: qsTr("Uninstall")
                visible: root.installed
                onClicked: root.uninstall()
            }
            MenuItem {
                text: qsTr("Visit website")
                visible: !root.fromFile && root.app !== null && root.app.website !== ""
                onClicked: root.store.openExternally(root.app.website)
            }
        }

        Column {
            id: body

            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: root.fromFile ? (root.isUpdate ? qsTr("Update app") : qsTr("Install app")) : root.name
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: root.inspecting
                visible: running
            }
            InfoLabel {
                objectName: "apkError"
                visible: root.fromFile && root.info !== null && !root.fileOk
                text: qsTr("This file can't be installed")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: root.fromFile && root.info !== null && !root.fileOk
                horizontalAlignment: Text.AlignHCenter
                text: root.info && root.info.message ? root.info.message : ""
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            // ── Header ────────────────────────────────────
            Item {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Math.max(bigIcon.height, headerText.height)
                visible: root.name !== ""

                AppIcon {
                    id: bigIcon
                    width: Theme.iconSizeExtraLarge
                    height: width
                    source: root.fromFile ? (root.fileOk ? root.info.icon : "") : root.store.iconFor(root.app)
                }
                Column {
                    id: headerText
                    anchors.left: bigIcon.right
                    anchors.leftMargin: Theme.paddingLarge
                    anchors.right: parent.right
                    anchors.verticalCenter: bigIcon.verticalCenter
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width
                        text: root.name
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeLarge
                        truncationMode: TruncationMode.Fade
                        visible: root.fromFile
                    }
                    Label {
                        width: parent.width
                        text: !root.fromFile && root.app ? root.app.author : ""
                        visible: text !== ""
                        color: Theme.highlightColor
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: root.fromFile ? qsTr("Android app · from a file") : qsTr("Android app · from F-Droid")
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: root.isUpdate ? qsTr("Version %1, replacing %2").arg(root.versionName).arg(root.info.installedVersionName) : qsTr("Version %1").arg(root.versionName)
                        visible: root.versionName !== ""
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.Wrap
                    }
                }
            }

            GetButton {
                objectName: "androidAction"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !root.fromFile && root.appId !== ""
                store: root.store
                appId: root.appId
                large: true
            }
            // An .apk: Install (or Update) until the job starts, then its progress.
            Button {
                objectName: "apkInstall"
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthMedium
                visible: root.fileOk && !root.busy && !(root.job && root.job.state === "done")
                text: root.isUpdate ? qsTr("Update") : qsTr("Install")
                onClicked: root.store.installApk(root.apkPath, root.pkg, root.name)
            }
            GetButton {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: root.fileOk && (root.busy || (root.job !== null && root.job.state === "done"))
                store: root.store
                appId: root.appId !== "" ? root.appId : "android:none.none"
                large: true
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: root.job !== null && root.job.state === "failed"
                text: qsTr("Couldn't install. %1").arg(root.job && root.job.error ? root.job.error : root.store.jobError(root.job))
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            // ── Anti-features, up front ───────────────────
            Repeater {
                model: root.antiFeatures
                delegate: Item {
                    id: anti

                    required property string modelData

                    x: Theme.horizontalPageMargin
                    width: root.width - 2 * Theme.horizontalPageMargin
                    height: Math.max(antiIcon.height, antiText.height)
                    Accessible.role: Accessible.StaticText
                    Accessible.name: antiText.text

                    Icon {
                        id: antiIcon
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-warning"
                        color: Theme.errorColor
                    }
                    Label {
                        id: antiText
                        anchors.left: antiIcon.right
                        anchors.leftMargin: Theme.paddingMedium
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.store.antiFeatureText[anti.modelData] || anti.modelData
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.Wrap
                    }
                }
            }

            // ── What it can do ────────────────────────────
            SectionHeader {
                text: qsTr("It can")
                visible: root.permissions.length > 0
            }
            Repeater {
                model: root.permissions
                delegate: Label {
                    required property string modelData

                    x: Theme.horizontalPageMargin
                    width: root.width - 2 * Theme.horizontalPageMargin
                    text: "• " + modelData
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: root.name !== ""
                text: root.permissions.length > 0 ? qsTr("It asks before using your location, camera, microphone, contacts or files.") : qsTr("It asks for no special permissions.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
            }

            // ── About ─────────────────────────────────────
            SectionHeader {
                text: qsTr("About")
                visible: !root.fromFile && root.app !== null && root.app.description !== ""
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !root.fromFile && root.app !== null
                text: root.app ? (root.app.description || root.app.summary) : ""
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            SectionHeader {
                text: qsTr("Information")
                visible: !root.fromFile && root.app !== null
            }
            Repeater {
                model: !root.fromFile && root.app ? [
                    {
                        "label": qsTr("Version"),
                        "value": root.app.version.name
                    },
                    {
                        "label": qsTr("Download"),
                        "value": root.store.formatSize(root.app.version.size)
                    },
                    {
                        "label": qsTr("Licence"),
                        "value": root.app.license
                    },
                    {
                        "label": qsTr("Updated"),
                        "value": root.app.lastUpdated > 0 ? new Date(root.app.lastUpdated * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat) : ""
                    }
                ].filter(r => r.value) : []
                delegate: DetailItem {
                    required property var modelData
                    label: modelData.label
                    value: modelData.value
                }
            }
        }
    }
}
