pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings

Page {
    id: page

    property string handler
    property string title
    readonly property string current: SettingsController.defaultAppName(handler, SettingsController.defaultAppsRevision)

    SilicaListView {
        id: view

        objectName: "appList"
        anchors.fill: parent
        model: SettingsController.appsForHandler(page.handler, SettingsController.appSourceRevision)
        header: PageHeader {
            title: page.title
            description: qsTr("Default app")
        }

        delegate: ListItem {
            id: item

            required property var modelData
            readonly property bool selected: modelData.name === page.current

            objectName: "pick-" + modelData.id
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.name
            Accessible.checked: selected
            onClicked: {
                SettingsController.setDefaultApp(page.handler, modelData.id);
                pageStack.pop();
            }

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: check.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }
                text: item.modelData.name
                truncationMode: TruncationMode.Fade
                color: item.selected || item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Icon {
                id: check

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                visible: item.selected
                source: "image://theme/icon-s-accept"
                color: Theme.highlightColor
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: view.count === 0
            text: qsTr("No apps")
            hintText: qsTr("None of the installed apps can be the default here")
        }

        VerticalScrollDecorator {}
    }
}
