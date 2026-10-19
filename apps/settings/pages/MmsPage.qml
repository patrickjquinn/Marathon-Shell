pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic

Page {
    id: page

    function edit() {
        const dialog = pageStack.push(Qt.resolvedUrl("MmsDialog.qml"), {
            mmsc: Logic.mmsValue(MmsSettings.mmsc),
            proxy: Logic.mmsValue(MmsSettings.proxy),
            apn: Logic.mmsValue(MmsSettings.apn)
        });
        dialog.accepted.connect(() => MmsSettings.save(dialog.mmsc.trim(), dialog.apn.trim(), dialog.proxy.trim()));
    }

    // A long address reads better whole, above its name, as in the edit dialog.
    component ValueRow: Column {
        id: row

        property string label
        property string value

        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        bottomPadding: Theme.paddingMedium

        Label {
            width: parent.width
            text: row.value
            wrapMode: Text.WrapAnywhere
            color: Theme.highlightColor
        }
        Label {
            width: parent.width
            text: row.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
        }
    }

    objectName: "mmsPage"
    Component.onCompleted: MmsSettings.refresh()

    Connections {
        target: MmsSettings

        function onSaved() {
            Notices.show(qsTr("MMS settings saved"));
        }
        function onFailed(error) {
            Notices.show(qsTr("Couldn't save the MMS settings: %1").arg(error));
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: MmsSettings.available

            MenuItem {
                objectName: "editItem"
                visible: MmsSettings.available
                text: qsTr("Edit carrier settings")
                onClicked: page.edit()
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("MMS")
            }
            TextSwitch {
                objectName: "autoDownloadSwitch"
                visible: MmsSettings.available
                text: qsTr("Download automatically")
                description: qsTr("Picture and group messages download as they arrive. Off, they wait on the phone until you turn this back on.")
                automaticCheck: false
                checked: MmsSettings.autoDownload
                onClicked: MmsSettings.setAutoDownload(!checked)
            }

            SectionHeader {
                visible: MmsSettings.available
                text: qsTr("Carrier settings")
            }
            ValueRow {
                objectName: "mmscItem"
                visible: MmsSettings.available
                label: qsTr("MMSC")
                value: Logic.mmsValue(MmsSettings.mmsc) || qsTr("Not set")
            }
            ValueRow {
                objectName: "proxyItem"
                visible: MmsSettings.available
                label: qsTr("MMS proxy")
                value: Logic.mmsValue(MmsSettings.proxy) || qsTr("None")
            }
            ValueRow {
                objectName: "apnItem"
                visible: MmsSettings.available
                label: qsTr("MMS APN")
                value: Logic.mmsValue(MmsSettings.apn) || qsTr("Not set")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: MmsSettings.available
                topPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("These are usually set for your carrier automatically. Change them only if picture messages don't send or arrive; pull down to edit.")
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: !MmsSettings.available
            text: qsTr("MMS isn't available")
            hintText: !Modem.available ? qsTr("This device has no mobile modem, so it can't send or receive picture messages") : qsTr("The MMS service isn't installed or isn't running")
        }

        VerticalScrollDecorator {}
    }
}
