pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic

Page {
    id: page

    property var app
    property string query: ""
    readonly property var results: present(Logic.search(query))
    readonly property bool searching: query.trim() !== ""
    // Only present once the app runner shares the shell's wallpaper list.
    readonly property var wallpapers: typeof Wallpapers !== "undefined" ? Wallpapers : null

    // No mobile network entry on devices without a modem.
    function present(entries) {
        return entries.filter(e => e.page !== "cellular" || Modem.available);
    }

    function summary(name) {
        switch (name) {
        case "wifi":
            return Logic.wifiSummary(Network.wifiEnabled, Network.wifiConnected, Network.wifiSsid);
        case "bluetooth":
            return Logic.bluetoothSummary(Bluetooth.enabled, Bluetooth.pairedDevices);
        case "cellular":
            return !Modem.available ? "" : !Modem.simPresent ? qsTr("No SIM card") : Modem.registered && Modem.operatorName !== "" ? Modem.operatorName : qsTr("No service");
        case "display":
            return qsTr("Brightness %1%").arg(Logic.percent(Display.brightness));
        case "ambience": {
            const current = page.wallpapers ? page.wallpapers.wallpapers.find(w => w.path === page.wallpapers.currentWallpaper) : undefined;
            return current ? current.name : "";
        }
        case "sound":
            return Audio.muted ? qsTr("Muted") : qsTr("Volume %1%").arg(Logic.percent(Audio.volume));
        case "datetime":
            return Logic.zoneCity(Settings.timeZone);
        case "battery":
            return Logic.batterySummary(Power.batteryLevel, Power.isCharging);
        case "storage":
            return storage.totalSpace > 0 ? qsTr("%1 free").arg(storage.availableSpaceString) : "";
        case "security":
            return (Security.hasQuickPIN ? qsTr("PIN set") : qsTr("No PIN")) + (Security.fingerprintAvailable ? " · " + qsTr("Fingerprint") : "");
        case "hiddenapps":
            return Settings.hiddenApps.length > 0 ? qsTr("%n hidden", "", Settings.hiddenApps.length) : "";
        case "appsort":
            return Settings.appGridColumns > 0 ? qsTr("%n columns", "", Settings.appGridColumns) : qsTr("Automatic");
        case "updates":
            return Updates.updateAvailable ? qsTr("Update available") : "";
        }
        return "";
    }

    function open(entry) {
        if (entry.app)
            Navigation.launchApp(entry.app);
        else
            page.app.openPage(entry.page);
    }

    function setDoNotDisturb(on) {
        Settings.dndEnabled = on;
        Audio.setDoNotDisturb(on);
    }

    StorageInfo {
        id: storage
    }

    component EntryItem: ListItem {
        id: item

        required property var modelData
        readonly property string value: page.summary(modelData.page)

        objectName: "entry-" + (modelData.page || modelData.app)
        contentHeight: Theme.itemSizeMedium
        Accessible.name: value !== "" ? modelData.title + ", " + value : modelData.title
        onClicked: page.open(modelData)

        Icon {
            id: icon

            x: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            source: item.modelData.icon
            color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
        Column {
            anchors {
                left: icon.right
                leftMargin: Theme.paddingLarge
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }

            Label {
                width: parent.width
                text: item.modelData.title
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                width: parent.width
                visible: text !== ""
                text: item.modelData.section !== undefined ? item.modelData.section : item.value
                font.pixelSize: Theme.fontSizeExtraSmall
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
        }
    }

    SilicaFlickable {
        id: flickable

        objectName: "mainFlickable"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Settings")
            }
            SearchField {
                id: searchField

                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search settings")
                onTextChanged: page.query = text
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    if (page.results.length > 0)
                        page.open(page.results[0]);
                    focus = false;
                }
            }

            Repeater {
                objectName: "results"
                model: page.results

                EntryItem {}
            }

            Column {
                width: parent.width
                visible: !page.searching

                TextSwitch {
                    objectName: "airplaneSwitch"
                    text: qsTr("Airplane mode")
                    description: Modem.available ? qsTr("Turns off Wi-Fi, Bluetooth and mobile network") : qsTr("Turns off Wi-Fi and Bluetooth")
                    automaticCheck: false
                    checked: Network.airplaneModeEnabled
                    onClicked: Network.setAirplaneMode(!checked)
                }
                TextSwitch {
                    objectName: "dndSwitch"
                    text: qsTr("Do not disturb")
                    description: qsTr("Silences notifications and calls")
                    automaticCheck: false
                    checked: Settings.dndEnabled
                    onClicked: page.setDoNotDisturb(!checked)
                }

                Repeater {
                    model: Logic.sections

                    Column {
                        id: section

                        required property var modelData

                        width: parent.width

                        SectionHeader {
                            text: section.modelData.title
                        }
                        Repeater {
                            model: page.present(section.modelData.entries)

                            EntryItem {}
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            objectName: "noResults"
            // Under the search field: centring in the window put it over the
            // field once the keyboard shrank the page.
            y: searchField.y + searchField.height + Theme.paddingLarge * 2
            enabled: page.searching && page.results.length === 0
            text: qsTr("No matching settings")
            hintText: qsTr("Try another word, like Wi-Fi, volume or PIN")
        }

        VerticalScrollDecorator {}
    }
}
