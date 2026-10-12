pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts

SettingsPageTemplate {
    id: appManagerPage

    property string pageName: "appmanager"

    pageTitle: "App Manager"

    overlayOpen: uninstallDialog.showing
    onCloseOverlayRequested: uninstallDialog.showing = false

    MConfirmDialog {
        id: uninstallDialog

        property string appId: ""
        property string appName: ""

        title: "Uninstall " + uninstallDialog.appName + "?"
        message: "This app and its data will be permanently removed from your device."
        confirmText: "Uninstall"
        destructive: true
        onConfirmed: {
            Logger.info("AppManagerPage", "Uninstalling: " + uninstallDialog.appId);
            MarathonAppInstaller.uninstallApp(uninstallDialog.appId);
            uninstallDialog.showing = false;
        }
        onCancelled: uninstallDialog.showing = false
    }

    MSnackbar {
        id: snackbar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.md
        anchors.bottomMargin: Constants.navBarHeight + MSpacing.md
    }

    Connections {
        target: MarathonAppInstaller

        function onUninstallComplete(appId) {
            snackbar.show(uninstallDialog.appName + " uninstalled");
        }

        function onUninstallFailed(appId, error) {
            snackbar.show("Couldn't uninstall " + uninstallDialog.appName + ": " + error);
        }
    }

    content: Flickable {
        contentHeight: contentColumn.height + Constants.navBarHeight + MSpacing.xl * 3
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: contentColumn

            width: parent.width
            spacing: 0

            Item {
                height: MSpacing.md
                width: 1
            }

            Text {
                width: parent.width
                leftPadding: MSpacing.lg
                rightPadding: MSpacing.lg
                text: "Installed Apps (" + MarathonAppRegistry.count + ")"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
            }

            Item {
                height: MSpacing.sm
                width: 1
            }

            Repeater {
                model: MarathonAppRegistry

                delegate: Item {
                    id: appDelegate

                    required property var model

                    width: contentColumn.width
                    height: Constants.touchTargetLarge + MSpacing.lg

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: MSpacing.lg
                        anchors.rightMargin: MSpacing.lg
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            spacing: MSpacing.md

                            Image {
                                Layout.preferredWidth: Constants.iconSizeLarge + MSpacing.sm
                                Layout.preferredHeight: Constants.iconSizeLarge + MSpacing.sm
                                Layout.alignment: Qt.AlignVCenter
                                source: appDelegate.model.icon || "qrc:/images/app-icon-placeholder.svg"
                                sourceSize.width: Constants.iconSizeLarge + MSpacing.sm
                                sourceSize.height: Constants.iconSizeLarge + MSpacing.sm
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                onStatusChanged: {
                                    if (status === Image.Error)
                                        source = "qrc:/images/app-icon-placeholder.svg";
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: MSpacing.xs

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: MSpacing.sm

                                    Text {
                                        text: appDelegate.model.name
                                        color: MColors.textPrimary
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: Font.DemiBold
                                    }

                                    Rectangle {
                                        visible: appDelegate.model.isProtected
                                        Layout.preferredWidth: systemBadgeText.width + MSpacing.md
                                        Layout.preferredHeight: MSpacing.lg
                                        radius: Constants.borderRadiusSmall
                                        color: "transparent"
                                        border.width: Constants.borderWidthThin
                                        border.color: MColors.marathonTeal

                                        Text {
                                            id: systemBadgeText

                                            anchors.centerIn: parent
                                            text: "System"
                                            color: MColors.marathonTeal
                                            font.pixelSize: MTypography.sizeSmall
                                            font.weight: Font.Medium
                                        }
                                    }
                                }

                                Text {
                                    text: "v" + (appDelegate.model.version || "1.0.0")
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeSmall
                                    Layout.fillWidth: true
                                }
                            }

                            MButton {
                                Layout.preferredWidth: Constants.touchTargetLarge + MSpacing.lg
                                text: "Uninstall"
                                variant: "danger"
                                disabled: appDelegate.model.isProtected
                                onClicked: {
                                    uninstallDialog.appId = appDelegate.model.id;
                                    uninstallDialog.appName = appDelegate.model.name;
                                    uninstallDialog.showing = true;
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Constants.borderWidthThin
                            color: MColors.border
                        }
                    }
                }
            }

            Item {
                height: MSpacing.lg
                width: 1
            }
        }
    }
}
