pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

// Each permission, and from there every app that has it: Marathon's and Android's.
Page {
    id: page

    // Set by the "permissions/<name>" route: that permission's apps open over the list.
    property string focusAppId

    function show(name) {
        pageStack.push(Qt.resolvedUrl("PermissionAppsPage.qml"), {
            permission: name
        });
    }

    objectName: "permissionsPage"
    onStatusChanged: {
        if (status === PageStatus.Active && focusAppId !== "") {
            const name = focusAppId;
            focusAppId = "";
            if (Logic.permissionNames.indexOf(name) >= 0)
                show(name);
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("App permissions")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("What your apps may use, Android apps included. Turn a permission off for an app and it asks again the next time it needs it.")
            }
            Repeater {
                model: Logic.permissionNames.filter(n => !Permissions.describe(n).restricted)

                ListItem {
                    id: item

                    required property string modelData
                    readonly property string title: Permissions.describe(modelData).label

                    objectName: "permission-" + modelData
                    contentHeight: Theme.itemSizeMedium
                    Accessible.name: title
                    onClicked: page.show(modelData)

                    Column {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            width: parent.width
                            text: item.title
                            truncationMode: TruncationMode.Fade
                            color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            text: Permissions.describe(item.modelData).description
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
