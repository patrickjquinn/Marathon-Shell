pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Nemo.Configuration 1.0
import "Phone.js" as Phone
import "pages"
import "cover"

ApplicationWindow {
    id: root

    // "/emergency" comes from the lock screen's Emergency affordance: dialer only.
    property string route: typeof MARATHON_APP_ROUTE !== "undefined" ? MARATHON_APP_ROUTE : ""
    readonly property bool emergencyOnly: route === "/emergency"
    property string routeParams: typeof MARATHON_APP_ROUTE_PARAMS !== "undefined" ? MARATHON_APP_ROUTE_PARAMS : ""

    property bool hasContactsPermission: false
    readonly property var contacts: hasContactsPermission ? Contacts.contacts : []
    readonly property var callHistory: CallHistory.history

    property string dialedNumber: ""
    property string callNumber: ""
    property string callName: ""
    property real callStartedAt: 0
    readonly property string callState: Telephony.callState
    readonly property bool inCall: callState !== "idle" && callState !== "terminated"

    property var callLogSeen: ConfigurationValue {
        key: "/apps/phone/callLogSeen"
        defaultValue: 0
    }
    readonly property int missedCount: Phone.missedSince(callHistory, Number(callLogSeen.value) || 0)

    property Item callPage: null
    property Item incomingPage: null

    property Component mainPage: Component {
        MainPage {
            phone: root
        }
    }
    property Component emergencyPage: Component {
        EmergencyPage {
            phone: root
        }
    }

    function contactName(number) {
        const match = contacts.find(c => Phone.sameNumber(c.phone, number));
        return match ? match.name : "";
    }

    // "/call" fills the dialer; another app never places the call itself.
    function handleRoute(name, params) {
        if (name !== "/call" || inCall)
            return;
        const number = String((params && params.number) || "").trim();
        if (number.length === 0)
            return;
        dialedNumber = number;
        const page = pageStack.currentPage as MainPage;
        if (page && page.tabs)
            page.tabs.moveTo(0);
    }

    function call(number) {
        number = String(number || "").trim();
        if (number.length === 0)
            return;
        const emergency = emergencyOnly || Phone.isEmergency(number);
        // dialEmergency leaves an audit record before dialling.
        if (emergency)
            Telephony.dialEmergency(number);
        else
            Telephony.dial(number);
        callNumber = number;
        callName = emergency ? qsTr("Emergency call") : contactName(number);
        callStartedAt = 0;
        showCallPage();
    }

    function showCallPage() {
        if (callPage)
            return;
        if (incomingPage && pageStack.currentPage === incomingPage) {
            callPage = pageStack.replace(Qt.resolvedUrl("pages/ActiveCallPage.qml"), {
                phone: root
            });
            incomingPage = null;
        } else {
            callPage = pageStack.push(Qt.resolvedUrl("pages/ActiveCallPage.qml"), {
                phone: root
            });
        }
    }

    function showIncoming(number) {
        if (endedTimer.running) {
            endedTimer.stop();
            closeCallPages();
        }
        callNumber = number;
        callName = contactName(number);
        callStartedAt = 0;
        if (!incomingPage && !callPage)
            incomingPage = pageStack.push(Qt.resolvedUrl("pages/IncomingCallPage.qml"), {
                phone: root
            });
    }

    function finishCall() {
        callNumber = "";
        callName = "";
        closeCallPages();
    }

    function closeCallPages() {
        const lowest = incomingPage || callPage;
        callPage = null;
        incomingPage = null;
        if (lowest)
            pageStack.pop(pageStack.previousPage(lowest));
    }

    function requestContacts() {
        if (emergencyOnly || hasContactsPermission)
            return;
        if (Permissions.hasPermission(appId, "contacts"))
            hasContactsPermission = true;
        else
            Permissions.requestPermission(appId, "contacts");
    }

    function markCallLogSeen() {
        callLogSeen.value = Date.now();
    }

    function sendMessage(number) {
        Navigation.launchAppWithRoute("messages", "conversation", JSON.stringify({
            number: number,
            name: contactName(number)
        }));
    }

    appId: "phone"

    cover: Component {
        PhoneCover {
            phone: root
            onHangupRequested: Telephony.hangup()
        }
    }

    initialPage: emergencyOnly ? emergencyPage : mainPage

    PhoneActions {
        phone: root
    }

    Timer {
        id: endedTimer

        interval: 1500
        onTriggered: root.finishCall()
    }

    Connections {
        target: Telephony

        function onIncomingCall(number) {
            root.showIncoming(number);
        }
        function onCallStateChanged() {
            const state = Telephony.callState;
            if (state === "idle" || state === "terminated") {
                root.dialedNumber = "";
                // The other side hung up: leave "Call ended" and the length on screen briefly.
                if (root.callPage && root.callStartedAt > 0) {
                    if (!endedTimer.running) {
                        root.callPage.endedAt = Date.now();
                        endedTimer.start();
                    }
                } else {
                    root.finishCall();
                }
            } else if (state === "active") {
                if (root.callStartedAt === 0)
                    root.callStartedAt = Date.now();
                if (root.callNumber === "" && Telephony.activeNumber !== "") {
                    root.callNumber = Telephony.activeNumber;
                    root.callName = root.contactName(root.callNumber);
                }
                root.showCallPage();
            }
        }
        function onCallFailed(reason) {
            root.closeCallPages();
            Notices.show(reason === "No modem available" ? qsTr("Calls aren't available: no SIM or modem was found.") : qsTr("The call couldn't be connected. Check your signal and try again."));
        }
    }

    Connections {
        target: typeof NavigationRouter !== "undefined" ? NavigationRouter : null
        ignoreUnknownSignals: true

        function onDeepLinkRequested(appId, name, params) {
            if (appId === root.appId) {
                root.activate();
                root.handleRoute(name, params);
            }
        }
    }

    Connections {
        target: Permissions

        function onPermissionGranted(appId, permission) {
            if (appId === root.appId && permission === "contacts")
                root.hasContactsPermission = true;
        }
        function onPermissionDenied(appId, permission) {
            if (appId === root.appId && permission === "contacts")
                root.hasContactsPermission = false;
        }
    }

    Component.onCompleted: {
        if (!emergencyOnly && Permissions.hasPermission(appId, "contacts"))
            hasContactsPermission = true;
        if (Telephony.callState === "active") {
            callNumber = Telephony.activeNumber;
            callName = contactName(callNumber);
            callStartedAt = Date.now();
            showCallPage();
        }
        if (route === "/call") {
            let params = {};
            try {
                params = JSON.parse(routeParams || "{}");
            } catch (e) {}
            Qt.callLater(handleRoute, route, params);
        }
    }
}
