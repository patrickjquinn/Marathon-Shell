import QtQuick
import QtQuick.Controls
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
        contentHeight: contentColumn.height + Constants.navBarHeight + Constants.spacingXLarge * 3
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        
        Column {
            id: contentColumn
            width: parent.width
            spacing: 0
            
            Item { height: Constants.spacingMedium; width: 1 }
            
            Text {
                width: parent.width
                leftPadding: Constants.spacingLarge
                rightPadding: Constants.spacingLarge
                text: "Installed Apps (" + MarathonAppRegistry.count + ")"
                color: Colors.textSecondary
                font.pixelSize: Constants.fontSizeSmall
            }
            
            Item { height: Constants.spacingSmall; width: 1 }
            
            Repeater {
                model: MarathonAppRegistry
                
                delegate: Item {
                    width: contentColumn.width
                    height: Constants.touchTargetLarge + Constants.spacingLarge
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: Constants.spacingLarge
                        anchors.rightMargin: Constants.spacingLarge
                        color: "transparent"
                        
                        RowLayout {
                            anchors.fill: parent
                            spacing: Constants.spacingMedium
                            
                            Image {
                                Layout.preferredWidth: Constants.iconSizeLarge + Constants.spacingSmall
                                Layout.preferredHeight: Constants.iconSizeLarge + Constants.spacingSmall
                                Layout.alignment: Qt.AlignVCenter
                                source: model.icon || "qrc:/images/app-icon-placeholder.svg"
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                
                                onStatusChanged: {
                                    if (status === Image.Error) {
                                        source = "qrc:/images/app-icon-placeholder.svg"
                                    }
                                }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: Constants.spacingXSmall
                                
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Constants.spacingSmall
                                    
                                    Text {
                                        text: model.name
                                        color: Colors.text
                                        font.pixelSize: Constants.fontSizeMedium
                                        font.weight: Font.DemiBold
                                    }
                                    
                                    Rectangle {
                                        visible: model.isProtected
                                        Layout.preferredWidth: systemBadgeText.width + Constants.spacingMedium
                                        Layout.preferredHeight: Constants.spacingLarge
                                        radius: Constants.borderRadiusSmall
                                        color: "transparent"
                                        border.width: Constants.borderWidthThin
                                        border.color: Colors.accent
                                        
                                        Text {
                                            id: systemBadgeText
                                            anchors.centerIn: parent
                                            text: "System"
                                            color: Colors.accent
                                            font.pixelSize: Constants.fontSizeSmall
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                                
                                Text {
                                    text: "v" + (model.version || "1.0.0")
                                    color: Colors.textSecondary
                                    font.pixelSize: Constants.fontSizeSmall
                                    Layout.fillWidth: true
                                }
                            }
                            
                            MButton {
                                Layout.preferredWidth: Constants.touchTargetLarge + Constants.spacingLarge
                                text: "Uninstall"
                                variant: "danger"
                                disabled: model.isProtected
                                onClicked: {
                                    uninstallDialog.appId = model.id
                                    uninstallDialog.appName = model.name
                                    uninstallDialog.open()
                                }
                            }
                        }
                        
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Constants.borderWidthThin
                            color: Colors.border
                        }
                    }
                }
            }
            
            Item { height: Constants.spacingLarge; width: 1 }
        }
    }
    
    Rectangle {
        id: uninstallDialog
        anchors.centerIn: parent
        width: Math.min(Constants.screenWidth * 0.85, parent.width - Constants.spacingXLarge * 2)
        height: dialogContent.height + Constants.spacingXLarge * 2
        color: Colors.surface
        radius: Constants.borderRadiusLarge
        visible: false
        z: 1000
        
        property string appId: ""
        property string appName: ""
        
        function open() {
            visible = true
        }
        
        function close() {
            visible = false
        }
        
        ColumnLayout {
            id: dialogContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Constants.spacingXLarge
            spacing: Constants.spacingLarge
            
            Text {
                Layout.fillWidth: true
                text: "Uninstall " + uninstallDialog.appName + "?"
                color: Colors.text
                font.pixelSize: Constants.fontSizeLarge
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            
            Text {
                Layout.fillWidth: true
                text: "This app will be permanently removed from your device."
                color: Colors.textSecondary
                font.pixelSize: Constants.fontSizeMedium
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            
            RowLayout {
                Layout.fillWidth: true
                spacing: Constants.spacingMedium
                
                MButton {
                    Layout.fillWidth: true
                    text: "Cancel"
                    variant: "secondary"
                    onClicked: {
                        uninstallDialog.close()
                    }
                }
                
                MButton {
                    Layout.fillWidth: true
                    text: "Uninstall"
                    variant: "danger"
                    onClicked: {
                        Logger.info("AppManagerPage", "Uninstalling: " + uninstallDialog.appId)
                        MarathonAppInstaller.uninstallApp(uninstallDialog.appId)
                        uninstallDialog.close()
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
                uninstallDialog.close()
            }
        }
    }
}
