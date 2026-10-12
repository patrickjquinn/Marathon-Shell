pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic

Page {
    id: page

    function rename() {
        const dialog = pageStack.push(Qt.resolvedUrl("DeviceNameDialog.qml"), { name: Settings.deviceName });
        dialog.accepted.connect(() => Settings.deviceName = dialog.name.trim());
    }

    StorageInfo {
        id: storage
    }

    component LinkItem: ListItem {
        id: link

        property alias text: label.text
        property string file

        onClicked: pageStack.push(Qt.resolvedUrl(file))

        Label {
            id: label

            anchors {
                left: parent.left
                leftMargin: Theme.horizontalPageMargin
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }
            color: link.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("About device")
            }
            ValueButton {
                objectName: "nameButton"
                label: qsTr("Device name")
                value: Settings.deviceName
                onClicked: page.rename()
            }
            DetailItem {
                label: qsTr("Model")
                value: SettingsController.deviceModel
            }
            DetailItem {
                objectName: "versionItem"
                label: qsTr("Marathon OS version")
                value: Updates.currentVersion || qsTr("Unknown")
            }
            DetailItem {
                objectName: "baseItem"
                label: qsTr("OS base")
                value: SettingsController.osVersion
            }
            DetailItem {
                label: qsTr("Kernel")
                value: SettingsController.kernelVersion
            }

            SectionHeader {
                text: qsTr("Hardware")
            }
            DetailItem {
                objectName: "storageItem"
                label: qsTr("Storage")
                value: storage.totalSpaceString
            }
            DetailItem {
                label: qsTr("Display")
                value: SettingsController.displayResolution
            }
            DetailItem {
                label: qsTr("Refresh rate")
                value: SettingsController.displayRefreshRate
            }
            DetailItem {
                label: qsTr("Pixel density")
                value: SettingsController.displayDpi
            }
            DetailItem {
                label: qsTr("Scale")
                value: SettingsController.displayScale
            }
            DetailItem {
                objectName: "batteryItem"
                label: qsTr("Battery")
                value: Logic.batterySummary(Power.batteryLevel, Power.isCharging) || qsTr("No battery")
            }

            SectionHeader {
                text: qsTr("Legal")
            }
            LinkItem {
                objectName: "licensesItem"
                text: qsTr("Open source licenses")
                file: "LicensesPage.qml"
            }
            LinkItem {
                objectName: "termsItem"
                text: qsTr("Terms of service")
                file: "TermsPage.qml"
            }
            LinkItem {
                objectName: "privacyItem"
                text: qsTr("Privacy policy")
                file: "PrivacyPage.qml"
            }
        }

        VerticalScrollDecorator {}
    }
}
