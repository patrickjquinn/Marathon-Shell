import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Modals
import "../components"

SettingsPageTemplate {
    id: defaultAppsPage
    pageTitle: "Default Apps"

    property string pageName: "defaultapps"

    function getAppsForHandler(handler) {
        var eligible = [];
        for (var i = 0; i < AppModel.rowCount(); i++) {
            var app = AppModel.getApp(i);
            if (app && app.defaultFor && app.defaultFor.indexOf(handler) >= 0) {
                eligible.push(app);
            }
        }
        return eligible;
    }

    function getDefaultAppName(handler) {
        var defaultAppId = SettingsManagerCpp.defaultApps[handler] || "";

        if (!defaultAppId) {
            var eligible = getAppsForHandler(handler);
            if (eligible.length > 0) {
                var defaults = SettingsManagerCpp.defaultApps;
                defaults[handler] = eligible[0].id;
                SettingsManagerCpp.defaultApps = defaults;
                Logger.info("DefaultApps", "Auto-assigned " + handler + " to " + eligible[0].id);
                defaultAppId = eligible[0].id;
            } else {
                return "None";
            }
        }

        for (var i = 0; i < AppModel.rowCount(); i++) {
            var app = AppModel.getApp(i);
            if (app && app.id === defaultAppId) {
                return app.name;
            }
        }
        return "None";
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
                    value: getDefaultAppName("browser")
                    showChevron: true
                    iconName: "globe"
                    onSettingClicked: browserSheet.visible = true
                }

                MSettingsListItem {
                    title: "Phone"
                    value: getDefaultAppName("dialer")
                    showChevron: true
                    iconName: "phone"
                    onSettingClicked: dialerSheet.visible = true
                }

                MSettingsListItem {
                    title: "Messaging"
                    value: getDefaultAppName("messaging")
                    showChevron: true
                    iconName: "message-circle"
                    onSettingClicked: messagingSheet.visible = true
                }

                MSettingsListItem {
                    title: "Email"
                    value: getDefaultAppName("email")
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
                    value: getDefaultAppName("camera")
                    showChevron: true
                    iconName: "camera"
                    onSettingClicked: cameraSheet.visible = true
                }

                MSettingsListItem {
                    title: "Gallery"
                    value: getDefaultAppName("gallery")
                    showChevron: true
                    iconName: "image"
                    onSettingClicked: gallerySheet.visible = true
                }

                MSettingsListItem {
                    title: "Music"
                    value: getDefaultAppName("music")
                    showChevron: true
                    iconName: "music"
                    onSettingClicked: musicSheet.visible = true
                }

                MSettingsListItem {
                    title: "Video"
                    value: getDefaultAppName("video")
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
                    value: getDefaultAppName("files")
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

    MSheet {
        id: browserSheet
        title: "Choose Browser"
        height: Math.min(600, defaultAppsPage.height * 0.75)

        ListView {
            anchors.fill: parent
            model: getAppsForHandler("browser")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["browser"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set browser to " + modelData.id);
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
            model: getAppsForHandler("dialer")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["dialer"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set dialer to " + modelData.id);
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
            model: getAppsForHandler("messaging")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["messaging"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set messaging to " + modelData.id);
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
            model: getAppsForHandler("email")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["email"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set email to " + modelData.id);
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
            model: getAppsForHandler("camera")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["camera"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set camera to " + modelData.id);
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
            model: getAppsForHandler("gallery")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["gallery"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set gallery to " + modelData.id);
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
            model: getAppsForHandler("music")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["music"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set music to " + modelData.id);
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
            model: getAppsForHandler("video")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["video"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set video to " + modelData.id);
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
            model: getAppsForHandler("files")
            spacing: 0
            clip: true

            delegate: MSettingsListItem {
                required property var modelData

                title: modelData.name
                subtitle: modelData.id
                onSettingClicked: {
                    var defaults = SettingsManagerCpp.defaultApps;
                    defaults["files"] = modelData.id;
                    SettingsManagerCpp.defaultApps = defaults;
                    Logger.info("DefaultApps", "Set files to " + modelData.id);
                    filesSheet.visible = false;
                }
            }
        }
    }
}
