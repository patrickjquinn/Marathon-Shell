import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

MApp {
    id: templateApp

    // App metadata (passed from launcher)
    // Note: These shadow MApp's properties but are set before MApp's onCompleted
    property string _appId: ""
    property string _appName: ""
    property string _appIcon: ""

    // Bind to MApp's properties
    appId: _appId
    appName: _appName
    appIcon: _appIcon

    // Template apps have no navigation depth, so back gesture will close them automatically
    navigationDepth: 0

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        MPage {
            anchors.fill: parent
            title: appName
            showBackButton: false

            content: Item {
                width: parent.width
                height: parent.height

                Column {
                    anchors.centerIn: parent
                    spacing: MSpacing.xl

                    Icon {
                        name: {
                            var iconPath = appIcon.replace("qrc:/images/", "").replace(".svg", "");
                            // Map app icons to lucide icon names (all downloaded from lucide icon set)
                            if (iconPath === "phone")
                                return "phone";
                            if (iconPath === "messages")
                                return "message-square";
                            if (iconPath === "browser")
                                return "globe";
                            if (iconPath === "camera")
                                return "camera";
                            if (iconPath === "gallery" || iconPath === "photos")
                                return "image";
                            if (iconPath === "music")
                                return "music";
                            if (iconPath === "calendar")
                                return "calendar";
                            if (iconPath === "clock")
                                return "clock";
                            if (iconPath === "maps")
                                return "map";
                            if (iconPath === "calculator")
                                return "calculator";
                            if (iconPath === "notes")
                                return "file-text";
                            if (iconPath === "files")
                                return "folder";
                            if (iconPath === "email")
                                return "mail";
                            if (iconPath === "settings")
                                return "settings";
                            // Generic fallback for unmapped apps
                            return "grid";
                        }
                        size: 128
                        color: MColors.text
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: appName
                        color: MColors.text
                        font.pixelSize: MTypography.sizeXLarge
                        font.weight: MTypography.weightBold
                        font.family: MTypography.fontFamily
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "App is running"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }  // End Rectangle (content)
}
