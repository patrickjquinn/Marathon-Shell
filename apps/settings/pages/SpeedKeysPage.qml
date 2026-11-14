pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

// Hold a letter on the home screen to open an app (Settings.speedKeys,
// letter to app id).
Page {
    id: page

    readonly property var apps: (Apps.getAllAppIds() || []).map(id => Apps.getApp(id)).filter(a => a && a.name).sort((a, b) => a.name.localeCompare(b.name))

    // An app this list doesn't have (a Shipwright or desktop app): its id's
    // last part, "shipwright-pacific" as "Pacific".
    function nameOf(appId) {
        const last = appId.split(/[-.]/).pop();
        return last.charAt(0).toUpperCase() + last.slice(1);
    }

    function assign(letter, appId) {
        const keys = Object.assign({}, Settings.speedKeys);
        if (appId === "")
            delete keys[letter];
        else
            keys[letter] = appId;
        Settings.speedKeys = keys;
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Speed keys")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("On the home screen, hold a letter on the keyboard to open its app. A tap still starts a search.")
            }
            Repeater {
                model: "abcdefghijklmnopqrstuvwxyz".split("")

                ComboBox {
                    id: combo

                    required property string modelData
                    readonly property string appId: Settings.speedKeys[modelData] || ""

                    objectName: "speedKey-" + modelData
                    width: column.width
                    label: modelData.toUpperCase()
                    currentIndex: {
                        const at = page.apps.findIndex(a => a.id === combo.appId);
                        return combo.appId === "" ? 0 : at < 0 ? -1 : at + 1;
                    }
                    value: currentItem ? currentItem.text : page.nameOf(combo.appId)
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("None")
                            onClicked: page.assign(combo.modelData, "")
                        }
                        Repeater {
                            model: page.apps

                            MenuItem {
                                required property var modelData

                                text: modelData.name
                                onClicked: page.assign(combo.modelData, modelData.id)
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
