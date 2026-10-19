pragma ComponentBehavior: Bound
import QtCore as Core
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

// The App Store's settings. "Only show apps made for phones" is the shell's
// filterMobileFriendlyApps, the same switch as App grid's "Hide desktop
// apps". The rest belong to the Store's handler, which keeps them and
// writes the copy read here (crates/marathon-store-handler/src/settings.rs).
Page {
    id: page

    property string stateDir: String(Core.StandardPaths.writableLocation(Core.StandardPaths.RuntimeLocation)).replace("file://", "") + "/marathon-store-state"
    property var openExternally: url => Qt.openUrlExternally(url)
    readonly property var defaults: ({
            "flathub": true,
            "fdroid": true,
            "antiFeatures": true,
            "autoUpdate": true,
            "updateOnMetered": false
        })
    property var values: defaults

    function load() {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + stateDir + "/settings.json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.responseText.length === 0)
                return;
            try {
                page.values = Object.assign({}, page.defaults, JSON.parse(xhr.responseText));
            } catch (e) {
                console.warn("Settings: unreadable Store settings:", e);
            }
        };
        xhr.send(null);
    }

    function set(key, on) {
        const next = Object.assign({}, values);
        next[key] = on;
        values = next;
        page.openExternally.call(page, "marathon-store://settings/set?" + key + "=" + (on ? 1 : 0));
        reload.restart();
    }

    Component.onCompleted: {
        load();
        page.openExternally.call(page, "marathon-store://settings/get");
        reload.restart();
    }

    // The handler answers by rewriting the copy.
    Timer {
        id: reload
        interval: 1500
        onTriggered: page.load()
    }

    SilicaFlickable {
        objectName: "storeSettingsView"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("App Store")
            }
            TextSwitch {
                objectName: "phoneSwitch"
                text: qsTr("Only show apps made for phones")
                description: qsTr("Apps that may not fit the screen stay a tap away in search. The home screen hides desktop apps too.")
                automaticCheck: false
                checked: Settings.filterMobileFriendlyApps
                onClicked: Settings.filterMobileFriendlyApps = !checked
            }

            SectionHeader {
                text: qsTr("Sources")
            }
            TextSwitch {
                objectName: "flathubSwitch"
                text: qsTr("Flathub")
                description: qsTr("Linux apps")
                automaticCheck: false
                checked: page.values.flathub
                onClicked: page.set("flathub", !checked)
            }
            TextSwitch {
                objectName: "fdroidSwitch"
                text: qsTr("F-Droid")
                description: qsTr("Free and open-source Android apps")
                automaticCheck: false
                checked: page.values.fdroid
                onClicked: page.set("fdroid", !checked)
            }
            TextSwitch {
                objectName: "antiFeaturesSwitch"
                text: qsTr("Show apps with anti-features")
                description: qsTr("F-Droid apps that track you, show ads or rely on services that aren't free, each with a warning")
                enabled: page.values.fdroid
                automaticCheck: false
                checked: page.values.antiFeatures
                onClicked: page.set("antiFeatures", !checked)
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Turning a source off hides its apps in the Store. Apps you installed stay.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            SectionHeader {
                text: qsTr("Updates")
            }
            TextSwitch {
                objectName: "autoUpdateSwitch"
                text: qsTr("Automatic updates")
                description: qsTr("Updates apps once a day, when the battery isn't low")
                automaticCheck: false
                checked: page.values.autoUpdate
                onClicked: page.set("autoUpdate", !checked)
            }
            TextSwitch {
                objectName: "meteredSwitch"
                text: qsTr("Update on metered networks")
                description: qsTr("Also on mobile data and other connections that may cost money")
                enabled: page.values.autoUpdate
                automaticCheck: false
                checked: page.values.updateOnMetered
                onClicked: page.set("updateOnMetered", !checked)
            }
        }

        VerticalScrollDecorator {}
    }
}
