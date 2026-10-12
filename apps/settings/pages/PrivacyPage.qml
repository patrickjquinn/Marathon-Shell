import QtQuick

LegalPage {
    title: qsTr("Privacy policy")
    sections: [
        { title: qsTr("Data on device"), text: qsTr("Marathon OS stores settings and app data locally on your device. We do not collect personal data by default.") },
        { title: qsTr("Permissions"), text: qsTr("Apps request permissions for access to features such as network, storage, or location. You can change permissions per app in Settings.") },
        { title: qsTr("Diagnostics"), text: qsTr("Diagnostic logs are stored locally and can be shared by you for support or debugging.") }
    ]
}
