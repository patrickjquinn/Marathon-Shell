pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Notifications 1.0
import "../components"

Page {
    id: page

    property var app
    property Component notification: Component {
        Notification {}
    }

    function post(appName, summary, body, options) {
        const o = options || {};
        const n = notification.createObject(page.app, {
            appName: appName,
            summary: summary,
            body: body,
            appIcon: o.icon || "",
            category: o.category || "",
            urgency: o.urgent ? Notification.Critical : Notification.Normal,
            expireTimeout: o.persistent ? 0 : 5000,
            remoteActions: (o.actions || []).map(a => ({ name: a, displayName: a }))
        });
        // Tests swap in a stub component, so n is not always a Notification.
        n.publish(); // qmllint disable missing-property
        page.app.notifications = page.app.notifications.concat([n]);
    }

    function closeAll() {
        page.app.notifications.forEach(n => n.close());
        page.app.notifications = [];
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Notifications")
                description: page.app.summary
            }

            SectionHeader {
                text: qsTr("Basic notifications")
            }
            Actions {
                TestItem {
                    objectName: "simple"
                    text: qsTr("Simple")
                    onClicked: page.app.run("Simple notification", () => page.post("test", "Test Notification", "This is a simple test notification"))
                }
                TestItem {
                    objectName: "withIcon"
                    text: qsTr("With icon")
                    onClicked: page.app.run("Notification with icon", () => page.post("test", "Marathon Test", "Notification with custom icon", { icon: "star", category: "test" }))
                }
                TestItem {
                    objectName: "highPriority"
                    text: qsTr("High priority")
                    onClicked: page.app.run("High priority notification", () => page.post("test", "Important", "This is a high priority notification", { urgent: true, persistent: true, icon: "alert-triangle" }))
                }
                TestItem {
                    objectName: "withActions"
                    text: qsTr("With actions")
                    onClicked: page.app.run("Notification with actions", () => page.post("test", "Interactive", "Tap an action below", { actions: ["reply", "dismiss", "snooze"], category: "message", icon: "message-circle" }))
                }
            }

            SectionHeader {
                text: qsTr("Categories")
            }
            Actions {
                TestItem {
                    objectName: "message"
                    text: qsTr("Message")
                    onClicked: page.app.run("Message notification", () => page.post("messages", "John Doe", "Hey, how are you doing?", { category: "message", icon: "message-circle" }))
                }
                TestItem {
                    objectName: "email"
                    text: qsTr("Email")
                    onClicked: page.app.run("Email notification", () => page.post("mail", "New Email", "You have 3 new emails", { category: "email", icon: "mail" }))
                }
                TestItem {
                    objectName: "social"
                    text: qsTr("Social")
                    onClicked: page.app.run("Social notification", () => page.post("social", "Friend Request", "Jane wants to connect with you", { category: "social", icon: "users" }))
                }
                TestItem {
                    objectName: "system"
                    text: qsTr("System")
                    onClicked: page.app.run("System notification", () => page.post("system", "System Update", "A new system update is available", { category: "system", icon: "download" }))
                }
            }

            SectionHeader {
                text: qsTr("Stress")
            }
            Actions {
                TestItem {
                    objectName: "burst"
                    text: qsTr("Burst (10)")
                    onClicked: page.app.run("10 burst notifications", () => {
                        for (let i = 0; i < 10; i++)
                            page.post("test", "Burst Test " + (i + 1), "Testing notification system under load", { icon: "lightning" });
                    })
                }
                TestItem {
                    objectName: "clearAll"
                    text: qsTr("Clear all")
                    onClicked: page.app.run("Clear notifications", () => page.closeAll())
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
