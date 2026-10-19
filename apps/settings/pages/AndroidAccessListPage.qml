pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    // Set by the "androidaccess/<kind>[/<package>]" route: that kind's page
    // opens over the list, for that one app when an app asked.
    property string focusAppId

    function show(kind, pkg) {
        pageStack.push(Qt.resolvedUrl("AndroidAccessPage.qml"), { kind: kind, focusPkg: pkg || "" });
    }

    objectName: "androidAccessListPage"
    onStatusChanged: {
        if (status === PageStatus.Active && focusAppId !== "") {
            const parts = focusAppId.split("/");
            focusAppId = "";
            if (Logic.androidAccess.some(a => a.kind === parts[0]))
                show(parts[0], parts[1]);
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Special access")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("What Android apps may do beyond their permissions. Only apps that ask for it are listed.")
            }
            Repeater {
                objectName: "accessList"
                model: Logic.androidAccess

                ListItem {
                    id: item

                    required property var modelData

                    objectName: "access-" + modelData.kind
                    contentHeight: Theme.itemSizeMedium
                    Accessible.name: modelData.title
                    onClicked: page.show(modelData.kind)

                    Column {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            width: parent.width
                            text: item.modelData.title
                            truncationMode: TruncationMode.Fade
                            color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            text: item.modelData.description
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
