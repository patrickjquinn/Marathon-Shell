import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Item {
    id: root

    property Component sourceComponent: null
    property var appInstance: loader.item
    property string appId: ""
    property bool isActive: true

    signal loadError(string message)
    signal loadSuccess

    Rectangle {
        id: errorContainer
        anchors.fill: parent
        color: MColors.background
        visible: false
        z: 100

        Column {
            anchors.centerIn: parent
            spacing: Constants.spacingLarge
            width: parent.width * 0.8

            Icon {
                name: "alert-triangle"
                size: Constants.iconSizeXLarge
                color: MColors.error
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "App Crashed"
                font.pixelSize: Constants.fontSizeXLarge
                font.weight: Font.DemiBold
                color: MColors.textPrimary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "The app encountered an error and stopped working."
                font.pixelSize: Constants.fontSizeMedium
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            MButton {
                text: "Restart App"
                variant: "primary"
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: root.restart()
            }
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: root.isActive
        asynchronous: true
        sourceComponent: root.sourceComponent

        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("SafeAppLoader: Failed to load app", root.appId);
                console.error("  Error string:", loader.sourceComponent);
                errorContainer.visible = true;
                root.loadError("Failed to load component");

                if (root.appId) {
                    StateManager.saveAppState(root.appId, "crashed");
                }
            } else if (status === Loader.Ready) {
                errorContainer.visible = false;
                root.loadSuccess();
            } else if (status === Loader.Loading) {
                errorContainer.visible = false;
            }
        }

        onLoaded: {
            if (item) {
                console.log("SafeAppLoader: Successfully loaded app", root.appId);

                // Connect to app's registration signals
                if (item.requestRegister) {
                    item.requestRegister.connect(function (appId, appInstance) {
                        console.log("SafeAppLoader: App requested registration:", appId);
                        if (typeof AppLifecycleManager !== 'undefined') {
                            AppLifecycleManager.registerApp(appId, appInstance);
                        } else {
                            console.error("SafeAppLoader: AppLifecycleManager not available!");
                        }
                    });
                }

                if (item.requestUnregister) {
                    item.requestUnregister.connect(function (appId) {
                        console.log("SafeAppLoader: App requested unregistration:", appId);
                        if (typeof AppLifecycleManager !== 'undefined') {
                            AppLifecycleManager.unregisterApp(appId);
                        }
                    });
                }
            }
        }
    }

    function restart() {
        console.log("SafeAppLoader: Restarting app", root.appId);
        errorContainer.visible = false;

        loader.active = false;

        Qt.callLater(() => {
            loader.active = true;
        });
    }

    function unload() {
        loader.active = false;
    }

    function reload() {
        restart();
    }
}
