import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

Dialog {
    id: dialog

    readonly property bool secured: SettingsController.wifiDialogSecured
    property alias password: passwordField.text

    Component.onCompleted: password = SettingsController.wifiDialogPassword
    canAccept: !secured || password.length >= 8
    onAccepted: SettingsController.submitWifiPassword(password)
    onRejected: SettingsController.dismissWifiDialog()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                acceptText: qsTr("Connect")
                title: SettingsController.wifiDialogSsid
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: (dialog.secured ? SettingsController.wifiDialogSecurity : qsTr("Open")) + " · " + qsTr("%1 signal").arg(Logic.signalQuality(SettingsController.wifiDialogStrength))
                color: Theme.secondaryHighlightColor
            }
            Label {
                objectName: "errorLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: text !== ""
                text: SettingsController.wifiDialogError
                wrapMode: Text.Wrap
                color: Theme.errorColor
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
                focus: dialog.secured
                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !dialog.secured
                text: qsTr("This network is not secured. Others nearby may see what you send.")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }
        }
    }
}
