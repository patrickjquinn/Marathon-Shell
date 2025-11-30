import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: page
    anchors.fill: parent
    color: MColors.background

    property string appId: ""

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        MLabel {
            text: "App Details: " + appId
            Layout.margins: MSpacing.md
        }
    }

    /*Connections {
        target: AppStoreService

        function onDownloadProgress(id, bytesReceived, bytesTotal) {
            if (id === appId) {
                isDownloading = true
                downloadProgress = bytesReceived / bytesTotal
            }
        }

        function onDownloadComplete(id, packagePath) {
            if (id === appId) {
                isDownloading = false
            }
        }

        function onDownloadFailed(id, error) {
            if (id === appId) {
                isDownloading = false
                errorText.text = error
            }
        }
    }

    Connections {
        target: AppInstaller

        function onInstallComplete(id) {
            if (id === appId) {
                isInstalled = true
            }
        }

        function onUninstallComplete(id) {
            if (id === appId) {
                isInstalled = false
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: contentColumn.height
        clip: true

        MColumn {
            id: contentColumn
            width: parent.width
            spacing: 25
            padding: 20

            // App Header
            Row {
                width: parent.width
                spacing: 20

                // App Icon
                Rectangle {
                    width: 80
                    height: 80
                    radius: 20
                    color: MTheme.surfaceVariant
                    border.color: MTheme.outline
                    border.width: 1

                    MIcon {
                        anchors.centerIn: parent
                        source: appData.icon || "apps"
                        size: 48
                        color: MTheme.primary
                    }
                }

                MColumn {
                    width: parent.width - 100
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    MText {
                        text: appData.name || "Unknown"
                        type: MText.Title
                    }

                    MText {
                        text: "by " + (appData.author || "Unknown Developer")
                        color: MTheme.onSurfaceVariant
                    }

                    Row {
                        spacing: 10

                        MIcon {
                            source: "star"
                            size: 16
                            color: "#FFC107"
                        }

                        MText {
                            text: (appData.rating || 0).toFixed(1) + " (" + (appData.downloads || 0) + " downloads)"
                            type: MText.Caption
                        }
                    }
                }
            }

            // Install/Uninstall Button
            MColumn {
                width: parent.width
                spacing: 10

                MButton {
                    text: {
                        if (isDownloading) return "Downloading..."
                        if (isInstalled) return "Uninstall"
                        return "Install"
                    }
                    type: isInstalled ? MButton.Outlined : MButton.Filled
                    width: parent.width
                    enabled: !isDownloading

                    onClicked: {
                        if (isInstalled) {
                            AppInstaller.uninstallApp(appId)
                        } else {
                            AppStoreService.downloadApp(appId)
                        }
                    }
                }

                // Download progress
                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: MTheme.surfaceVariant
                    visible: isDownloading

                    Rectangle {
                        width: parent.width * downloadProgress
                        height: parent.height
                        radius: 2
                        color: MTheme.primary

                        Behavior on width {
                            NumberAnimation { duration: 150 }
                        }
                    }
                }

                // Error message
                MText {
                    id: errorText
                    width: parent.width
                    color: MTheme.error
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                }
            }

            // Description
            MColumn {
                width: parent.width
                spacing: 10

                MText {
                    text: "About"
                    type: MText.Subtitle
                }

                MText {
                    width: parent.width
                    text: appData.description || "No description available."
                    wrapMode: Text.WordWrap
                }
            }

            // Permissions
            MColumn {
                width: parent.width
                spacing: 10
                visible: appData.permissions && appData.permissions.length > 0

                MText {
                    text: "Permissions"
                    type: MText.Subtitle
                }

                Repeater {
                    model: appData.permissions || []

                    delegate: Row {
                        width: parent.width
                        spacing: 12

                        MIcon {
                            source: getPermissionIcon(modelData)
                            size: 20
                            color: MTheme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        MText {
                            text: PermissionManager.getPermissionDescription(modelData)
                            width: parent.width - 32
                            wrapMode: Text.WordWrap
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // App Info
            MColumn {
                width: parent.width
                spacing: 10

                MText {
                    text: "Information"
                    type: MText.Subtitle
                }

                InfoRow {
                    label: "Version"
                    value: appData.version || "1.0.0"
                }

                InfoRow {
                    label: "Size"
                    value: formatSize(appData.size || 0)
                }

                InfoRow {
                    label: "Category"
                    value: appData.categories ? appData.categories[0] : "Uncategorized"
                }
            }
        }
    }

    function getPermissionIcon(permission) {
        const icons = {
            "network": "wifi",
            "location": "location_on",
            "camera": "camera_alt",
            "microphone": "mic",
            "contacts": "contacts",
            "storage": "folder"
        };
        return icons[permission] || "security";
    }

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
        return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }
    */
}
