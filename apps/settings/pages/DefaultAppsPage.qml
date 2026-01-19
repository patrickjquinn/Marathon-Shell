pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: defaultAppsPage

    property string pageName: "defaultapps"

    pageTitle: "Default Apps"

    MSheet {
        id: browserSheet

        title: "Choose Browser"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("browser", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("browser", modelData.id);
                    browserSheet.visible = false;
                }
            }
        }
    }

    MSheet {
        id: dialerSheet

        title: "Choose Phone App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("dialer", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("dialer", modelData.id);
                    dialerSheet.visible = false;
                }
            }
        }
    }

    MSheet {
        id: messagingSheet

        title: "Choose Messaging App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("messaging", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("messaging", modelData.id);
                    messagingSheet.visible = false;
                }
            }
        }
    }

    MSheet {
        id: emailSheet

        title: "Choose Email App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("email", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("email", modelData.id);
                    emailSheet.visible = false;
                }
            }
        }
    }

    MSheet {
        id: cameraSheet

        title: "Choose Camera App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("camera", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("camera", modelData.id);
                    cameraSheet.visible = false;
                }
            }
        }
    }

    MSheet {
        id: gallerySheet

        title: "Choose Gallery App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("gallery", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("gallery", modelData.id);
                    gallerySheet.visible = false;
                }
            }
        }
    }

    MSheet {
        id: musicSheet

        title: "Choose Music App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("music", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("music", modelData.id);
                    musicSheet.visible = false;
                }
            }
        }
    }

    MSheet {
        id: videoSheet

        title: "Choose Video App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("video", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("video", modelData.id);
                    videoSheet.visible = false;
                }
            }
        }
    }

    MSheet {
        id: filesSheet

        title: "Choose File Manager"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: SettingsController.appsForHandler("files", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("files", modelData.id);
                    filesSheet.visible = false;
                }
            }
        }
    }

    content: Flickable {
        contentHeight: contentColumn.height + 40
        clip: true

        Column {
            id: contentColumn

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Communication"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Browser"
                    value: SettingsController.defaultAppName("browser", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "globe"
                    onSettingClicked: browserSheet.visible = true
                }

                MSettingsListItem {
                    title: "Phone"
                    value: SettingsController.defaultAppName("dialer", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "phone"
                    onSettingClicked: dialerSheet.visible = true
                }

                MSettingsListItem {
                    title: "Messaging"
                    value: SettingsController.defaultAppName("messaging", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "message-circle"
                    onSettingClicked: messagingSheet.visible = true
                }

                MSettingsListItem {
                    title: "Email"
                    value: SettingsController.defaultAppName("email", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "mail"
                    onSettingClicked: emailSheet.visible = true
                }
            }

            MSection {
                title: "Media"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Camera"
                    value: SettingsController.defaultAppName("camera", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "camera"
                    onSettingClicked: cameraSheet.visible = true
                }

                MSettingsListItem {
                    title: "Gallery"
                    value: SettingsController.defaultAppName("gallery", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "image"
                    onSettingClicked: gallerySheet.visible = true
                }

                MSettingsListItem {
                    title: "Music"
                    value: SettingsController.defaultAppName("music", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "music"
                    onSettingClicked: musicSheet.visible = true
                }

                MSettingsListItem {
                    title: "Video"
                    value: SettingsController.defaultAppName("video", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "video"
                    onSettingClicked: videoSheet.visible = true
                }
            }

            MSection {
                title: "Utilities"
                width: parent.width - 48

                MSettingsListItem {
                    title: "File Manager"
                    value: SettingsController.defaultAppName("files", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "folder"
                    onSettingClicked: filesSheet.visible = true
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
