import QtQuick

LegalPage {
    title: qsTr("Privacy policy")
    sections: [
        { title: qsTr("Data on device"), text: qsTr("Marathon OS stores settings and app data locally on your device. We do not collect personal data by default.") },
        { title: qsTr("Permissions"), text: qsTr("Apps ask before they first use features such as the network, storage or location. Settings > Installed apps shows what each app uses.") },
        { title: qsTr("Diagnostics"), text: qsTr("Diagnostic logs are stored locally and can be shared by you for support or debugging.") }
    ]
}
