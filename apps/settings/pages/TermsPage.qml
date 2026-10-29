import QtQuick

LegalPage {
    title: qsTr("Terms of service")
    sections: [
        {
            title: qsTr("Agreement"),
            text: qsTr("By using Marathon OS, you agree to use the system responsibly and lawfully. You are responsible for the content you create or access on this device.")
        },
        {
            title: qsTr("Warranty"),
            text: qsTr("Marathon OS is provided \"as is\" without warranties of any kind. We do not guarantee uninterrupted operation or compatibility with all hardware.")
        },
        {
            title: qsTr("Updates"),
            text: qsTr("System updates may change features or behavior. You may choose whether to install optional updates.")
        }
    ]
}
