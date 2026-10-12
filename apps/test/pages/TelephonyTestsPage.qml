pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../components"

Page {
    id: page

    property var app
    readonly property var telephony: typeof Telephony !== "undefined" ? Telephony : null
    readonly property var sms: typeof Sms !== "undefined" ? Sms : null
    readonly property var contacts: typeof Contacts !== "undefined" ? Contacts : null

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Telephony & SMS")
                description: page.app.summary
            }

            SectionHeader {
                text: qsTr("Incoming call")
            }
            HintLabel {
                text: qsTr("Simulates an incoming phone call")
            }
            Actions {
                TestItem {
                    objectName: "callUnknown"
                    text: qsTr("Unknown number")
                    onClicked: page.app.run("Incoming call", () => page.telephony.simulateIncomingCall("+1234567890"))
                }
                TestItem {
                    objectName: "callContact"
                    text: qsTr("Known contact")
                    onClicked: page.app.run("Incoming call from contact", () => {
                        if (page.contacts)
                            page.contacts.addContact("John Doe", "+1555123456", "john@example.com");
                        page.telephony.simulateIncomingCall("+1555123456");
                    })
                }
            }

            SectionHeader {
                text: qsTr("SMS")
            }
            HintLabel {
                text: qsTr("Simulates receiving text messages")
            }
            Actions {
                TestItem {
                    objectName: "smsSingle"
                    text: qsTr("Single SMS")
                    onClicked: page.app.run("Incoming SMS", () => page.sms.simulateIncomingSMS("+1234567890", "Hey! This is a test message from the Marathon Test Suite."))
                }
                TestItem {
                    objectName: "smsMultiple"
                    text: qsTr("Multiple SMS")
                    onClicked: page.app.run("3 incoming SMS", () => {
                        for (let i = 0; i < 3; i++)
                            page.sms.simulateIncomingSMS("+1555987654" + i, "Message " + (i + 1) + " from test suite");
                    })
                }
            }

            SectionHeader {
                text: qsTr("Call state")
            }
            HintLabel {
                text: qsTr("Test different call states and transitions")
            }
            Actions {
                TestItem {
                    objectName: "stateActive"
                    text: qsTr("Active call")
                    onClicked: page.app.run("Call state: active", () => page.telephony.simulateCallStateChange("active"))
                }
                TestItem {
                    objectName: "stateRinging"
                    text: qsTr("Ringing")
                    onClicked: page.app.run("Call state: ringing", () => page.telephony.simulateCallStateChange("ringing"))
                }
                TestItem {
                    objectName: "stateIdle"
                    text: qsTr("End call")
                    onClicked: page.app.run("Call state: idle", () => page.telephony.simulateCallStateChange("idle"))
                }
                TestItem {
                    objectName: "missedCall"
                    text: qsTr("Missed call")
                    onClicked: page.app.run("Missed call", () => {
                        const telephony = page.telephony;
                        telephony.simulateIncomingCall("+1555111222");
                        Qt.callLater(() => telephony.simulateCallStateChange("terminated"));
                    })
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
