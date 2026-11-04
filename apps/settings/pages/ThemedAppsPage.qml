pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    readonly property var apps: AppInstaller.flatpakApps().sort((a, b) => a.name.localeCompare(b.name))

    SilicaListView {
        id: view

        objectName: "appList"
        anchors.fill: parent
        model: page.apps
        header: Column {
            width: view.width

            PageHeader {
                title: qsTr("Themed apps")
                description: qsTr("Light and dark always follow the ambience")
            }
            TextSwitch {
                objectName: "gtkSwitch"
                text: qsTr("GNOME and GTK apps")
                description: qsTr("Use the ambience's accent and colours")
                automaticCheck: false
                checked: Settings.gtkTheming
                onClicked: Settings.gtkTheming = !checked
            }
            TextSwitch {
                objectName: "kdeSwitch"
                text: qsTr("KDE and Qt apps")
                description: qsTr("Use the ambience's accent and colours")
                automaticCheck: false
                checked: Settings.kdeTheming
                onClicked: Settings.kdeTheming = !checked
            }
            TextSwitch {
                objectName: "androidSwitch"
                visible: AndroidApps.available
                text: qsTr("Android apps")
                description: qsTr("Use the ambience's colours instead of Android's own")
                automaticCheck: false
                checked: Settings.androidTheming
                onClicked: Settings.androidTheming = !checked
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Apps that are already open may keep their colours until they restart.")
            }
            SectionHeader {
                visible: view.count > 0
                text: qsTr("Flatpak apps")
            }
        }

        delegate: TextSwitch {
            required property var modelData

            objectName: "theme-" + modelData.id
            text: modelData.name
            automaticCheck: false
            enabled: Settings.gtkTheming || Settings.kdeTheming
            checked: Settings.unthemedApps.indexOf(modelData.id) < 0
            onClicked: Settings.unthemedApps = Logic.setMember(Settings.unthemedApps, modelData.id, checked)
        }

        VerticalScrollDecorator {}
    }
}
