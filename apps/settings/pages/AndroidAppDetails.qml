pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

// What an Android app's page in Installed apps shows beyond its name.
Column {
    id: details

    required property string pkg
    required property var app
    required property RemorsePopup remorse
    readonly property bool loaded: app.pkg === pkg
    readonly property var domains: app.domains || []

    objectName: "androidDetails"

    DetailItem {
        objectName: "androidVersionItem"
        visible: !!details.app.versionName
        label: qsTr("Version")
        value: details.app.versionName || ""
    }
    DetailItem {
        objectName: "androidKindItem"
        label: qsTr("Type")
        value: qsTr("Android app")
    }
    TextSwitch {
        objectName: "androidNotifySwitch"
        visible: details.loaded
        text: qsTr("Notifications")
        description: qsTr("Show this app's notifications")
        automaticCheck: false
        checked: !!details.app.notifications
        onClicked: AndroidApps.setNotifications(details.pkg, !checked)
    }

    SectionHeader {
        visible: details.loaded
        text: qsTr("Permissions")
    }
    Repeater {
        objectName: "androidPermissions"
        model: details.app.permissions || []

        TextSwitch {
            required property var modelData

            objectName: "androidPermission-" + modelData.name
            text: Permissions.describe(modelData.name).label
            description: Permissions.describe(modelData.name).description
            automaticCheck: false
            checked: modelData.granted
            enabled: !modelData.fixed
            onClicked: AndroidApps.setPermission(details.pkg, modelData.name, !checked)
        }
    }
    Label {
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        visible: details.loaded
        topPadding: Theme.paddingSmall
        bottomPadding: Theme.paddingMedium
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.secondaryHighlightColor
        text: (details.app.permissions || []).length === 0 ? qsTr("This app doesn't use any permissions.") : qsTr("Apps ask for these permissions the first time they need them.")
    }

    SectionHeader {
        visible: details.domains.length > 0
        text: qsTr("Links")
    }
    TextSwitch {
        objectName: "linksSwitch"
        visible: details.domains.length > 0
        text: qsTr("Open supported links")
        description: details.domains.length === 1 ? qsTr("Links to %1 open in this app").arg(details.domains[0]) : qsTr("Links to %1 and %n other sites open in this app", "", details.domains.length - 1).arg(details.domains[0])
        automaticCheck: false
        checked: !!details.app.links
        onClicked: AndroidApps.setOpenLinks(details.pkg, !checked)
    }

    SectionHeader {
        visible: details.loaded
        text: qsTr("Battery")
    }
    ComboBox {
        id: batteryCombo

        readonly property var modes: [
            { value: "optimized", title: qsTr("Optimized"), description: qsTr("Android limits the app in the background") },
            { value: "unrestricted", title: qsTr("Unrestricted"), description: qsTr("The app runs in the background without limits") }
        ]

        objectName: "batteryCombo"
        visible: details.loaded
        width: parent.width
        label: qsTr("Battery use")
        description: currentIndex >= 0 ? modes[currentIndex].description : ""
        Binding on currentIndex {
            value: details.app.battery === "unrestricted" ? 1 : 0
        }
        menu: ContextMenu {
            Repeater {
                model: batteryCombo.modes

                MenuItem {
                    required property var modelData

                    text: modelData.title
                    onClicked: AndroidApps.setBattery(details.pkg, modelData.value)
                }
            }
        }
    }

    SectionHeader {
        visible: details.loaded
        text: qsTr("Storage")
    }
    DetailItem {
        objectName: "appSizeItem"
        visible: details.loaded
        label: qsTr("App")
        value: Logic.dataSize(details.app.appBytes)
    }
    DetailItem {
        objectName: "dataSizeItem"
        visible: details.loaded
        label: qsTr("Data")
        value: Logic.dataSize(Math.max(0, (details.app.dataBytes || 0) - (details.app.cacheBytes || 0)))
    }
    DetailItem {
        objectName: "cacheSizeItem"
        visible: details.loaded
        label: qsTr("Cache")
        value: Logic.dataSize(details.app.cacheBytes)
    }
    Row {
        id: storageButtons

        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        visible: details.loaded
        topPadding: Theme.paddingMedium
        bottomPadding: Theme.paddingLarge
        spacing: Theme.paddingMedium

        Button {
            objectName: "clearCacheButton"
            width: (storageButtons.width - storageButtons.spacing) / 2
            text: qsTr("Clear cache")
            enabled: (details.app.cacheBytes || 0) > 0
            onClicked: AndroidApps.clearCache(details.pkg)
        }
        Button {
            objectName: "clearDataButton"
            width: (storageButtons.width - storageButtons.spacing) / 2
            text: qsTr("Clear data")
            onClicked: details.remorse.execute(qsTr("Clearing %1's data").arg(details.app.label), () => AndroidApps.clearData(details.pkg))
        }
    }
}
