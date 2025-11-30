import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import "../components"

SettingsPageTemplate {
    id: appManagerPage
    pageTitle: "App Manager"

    property string pageName: "appmanager"

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
                                source: model.icon || "qrc:/images/app-icon-placeholder.svg"
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true

                                onStatusChanged: {
                                    if (status === Image.Error) {
                                        source = "qrc:/images/app-icon-placeholder.svg";
                                    }
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
                                        text: model.name
                                        color: MColors.textPrimary
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: Font.DemiBold
                                    }

                                    Rectangle {
                                        visible: model.isProtected
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
                                    text: "v" + (model.version || "1.0.0")
                                    color: MColors.textSecondary
                                    font.pixelSize: MTypography.sizeSmall
                                    Layout.fillWidth: true
                                }
                            }

                            MButton {
                                Layout.preferredWidth: Constants.touchTargetLarge + MSpacing.lg
                                text: "Uninstall"
                                variant: "danger"
                                disabled: model.isProtected
                                onClicked: {
                                    uninstallDialog.appId = model.id;
                                    uninstallDialog.appName = model.name;
                                    uninstallDialog.open();
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

    Rectangle {
        id: uninstallDialog
        anchors.centerIn: parent
        width: Math.min(Constants.screenWidth * 0.85, parent.width - MSpacing.xl * 2)
        height: dialogContent.height + MSpacing.xl * 2
        color: MColors.surface
        radius: Constants.borderRadiusLarge
        visible: false
        z: 1000

        property string appId: ""
        property string appName: ""

        function open() {
            visible = true;
        }

        function close() {
            visible = false;
        }

        ColumnLayout {
            id: dialogContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: MSpacing.xl
            spacing: MSpacing.lg

            Text {
                Layout.fillWidth: true
                text: "Uninstall " + uninstallDialog.appName + "?"
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: "This app will be permanently removed from your device."
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: MSpacing.md

                MButton {
                    Layout.fillWidth: true
                    text: "Cancel"
                    variant: "secondary"
                    onClicked: {
                        uninstallDialog.close();
                    }
                }

                MButton {
                    Layout.fillWidth: true
                    text: "Uninstall"
                    variant: "danger"
                    onClicked: {
                        Logger.info("AppManagerPage", "Uninstalling: " + uninstallDialog.appId);
                        MarathonAppInstaller.uninstallApp(uninstallDialog.appId);
                        uninstallDialog.close();
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: uninstallDialog.visible
        z: 999

        MouseArea {
            anchors.fill: parent
            onClicked: {
                uninstallDialog.close();
            }
        }
    }
}
