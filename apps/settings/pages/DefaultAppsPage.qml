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

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("browser", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("browser", modelData.id);
                    browserSheet.hide();
                }
            }
        }
    }

    MSheet {
        id: dialerSheet

        title: "Choose Phone App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("dialer", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("dialer", modelData.id);
                    dialerSheet.hide();
                }
            }
        }
    }

    MSheet {
        id: messagingSheet

        title: "Choose Messaging App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("messaging", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("messaging", modelData.id);
                    messagingSheet.hide();
                }
            }
        }
    }

    MSheet {
        id: emailSheet

        title: "Choose Email App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("email", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("email", modelData.id);
                    emailSheet.hide();
                }
            }
        }
    }

    MSheet {
        id: cameraSheet

        title: "Choose Camera App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("camera", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("camera", modelData.id);
                    cameraSheet.hide();
                }
            }
        }
    }

    MSheet {
        id: gallerySheet

        title: "Choose Gallery App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("gallery", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("gallery", modelData.id);
                    gallerySheet.hide();
                }
            }
        }
    }

    MSheet {
        id: musicSheet

        title: "Choose Music App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("music", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("music", modelData.id);
                    musicSheet.hide();
                }
            }
        }
    }

    MSheet {
        id: videoSheet

        title: "Choose Video App"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("video", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("video", modelData.id);
                    videoSheet.hide();
                }
            }
        }
    }

    MSheet {
        id: filesSheet

        title: "Choose File Manager"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        content: ListView {
            width: parent.width
            height: parent.height
            model: SettingsController.appsForHandler("files", SettingsController.appSourceRevision)
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    SettingsController.setDefaultApp("files", modelData.id);
                    filesSheet.hide();
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
                    onSettingClicked: browserSheet.show()
                }

                MSettingsListItem {
                    title: "Phone"
                    value: SettingsController.defaultAppName("dialer", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "phone"
                    onSettingClicked: dialerSheet.show()
                }

                MSettingsListItem {
                    title: "Messaging"
                    value: SettingsController.defaultAppName("messaging", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "message-circle"
                    onSettingClicked: messagingSheet.show()
                }

                MSettingsListItem {
                    title: "Email"
                    value: SettingsController.defaultAppName("email", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "mail"
                    onSettingClicked: emailSheet.show()
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
                    onSettingClicked: cameraSheet.show()
                }

                MSettingsListItem {
                    title: "Gallery"
                    value: SettingsController.defaultAppName("gallery", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "image"
                    onSettingClicked: gallerySheet.show()
                }

                MSettingsListItem {
                    title: "Music"
                    value: SettingsController.defaultAppName("music", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "music"
                    onSettingClicked: musicSheet.show()
                }

                MSettingsListItem {
                    title: "Video"
                    value: SettingsController.defaultAppName("video", SettingsController.defaultAppsRevision)
                    showChevron: true
                    iconName: "video"
                    onSettingClicked: videoSheet.show()
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
                    onSettingClicked: filesSheet.show()
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
