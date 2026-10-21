pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Settings 1.0

Dialog {
    id: dialog

    readonly property var securities: [
        { value: "wpa-psk", title: qsTr("WPA/WPA2 Personal") },
        { value: "sae", title: qsTr("WPA3 Personal") },
        { value: "none", title: qsTr("None") }
    ]
    property alias ssid: ssidField.text
    property alias password: passwordField.text
    property string security: "wpa-psk"
    readonly property bool secured: security !== "none"

    canAccept: ssid.trim() !== "" && (!secured || password.length >= 8)
    onAccepted: SettingsController.connectHiddenNetwork(ssid.trim(), security, secured ? password : "")
    onRejected: SettingsController.dismissWifiDialog()
    Component.onCompleted: {
        ssid = SettingsController.wifiDialogSsid;
        security = SettingsController.wifiDialogSecurity || "wpa-psk";
        password = SettingsController.wifiDialogPassword;
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            DialogHeader {
                acceptText: qsTr("Connect")
                title: qsTr("Add network")
            }
            Label {
                objectName: "errorLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                visible: text !== ""
                text: SettingsController.wifiDialogError
                wrapMode: Text.Wrap
                color: Theme.errorColor
            }
            TextField {
                id: ssidField

                objectName: "ssidField"
                width: parent.width
                label: qsTr("Network name (SSID)")
                placeholderText: qsTr("Network name (SSID)")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                focus: true
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: dialog.secured ? passwordField.focus = true : dialog.accept()
            }
            ComboBox {
                objectName: "securityCombo"
                width: parent.width
                label: qsTr("Security")
                Binding on currentIndex {
                    value: dialog.securities.findIndex(s => s.value === dialog.security)
                }
                menu: ContextMenu {
                    Repeater {
                        model: dialog.securities

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: dialog.security = modelData.value
                        }
                    }
                }
            }
            PasswordField {
                id: passwordField

                objectName: "passwordField"
                width: parent.width
                visible: dialog.secured
                label: qsTr("Password")
                description: text.length > 0 && text.length < 8 ? qsTr("At least 8 characters (%n more)", "", 8 - text.length) : qsTr("At least 8 characters")
                errorHighlight: SettingsController.wifiDialogError !== ""
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
    }
}
