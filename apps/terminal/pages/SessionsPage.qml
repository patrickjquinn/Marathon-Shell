pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var app

    SilicaListView {
        objectName: "sessionList"
        anchors.fill: parent
        model: page.app.sessions

        header: PageHeader {
            title: qsTr("Sessions")
        }

        PullDownMenu {
            MenuItem {
                objectName: "newSessionItem"
                text: qsTr("New session")
                onClicked: {
                    page.app.newSession();
                    pageStack.pop();
                }
            }
        }

        delegate: ListItem {
            id: item

            required property var modelData
            required property int index

            highlighted: down || index === page.app.currentIndex
            menu: page.app.sessions.length > 1 ? closeMenu : null
            Accessible.name: label.text

            onClicked: {
                page.app.currentIndex = index;
                pageStack.pop();
            }

            Component {
                id: closeMenu

                ContextMenu {
                    MenuItem {
                        objectName: "closeItem"
                        text: qsTr("Close")
                        onClicked: {
                            const app = page.app;
                            const session = item.modelData;
                            item.remorseAction(qsTr("Closing"), () => app.closeSession(app.sessions.indexOf(session)));
                        }
                    }
                }
            }

            Label {
                id: label

                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: item.modelData.title !== "Terminal" ? item.modelData.title : qsTr("Session %1").arg(item.index + 1)
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
