import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../SettingsLogic.js" as Logic

Dialog {
    id: dialog

    property alias mmsc: mmscField.text
    property alias proxy: proxyField.text
    property alias apn: apnField.text
    readonly property string mmscError: Logic.mmscError(mmsc)
    readonly property string proxyError: Logic.mmsProxyError(proxy)
    readonly property string apnError: Logic.apnError(apn)

    objectName: "mmsDialog"
    canAccept: mmscError === "" && proxyError === "" && apnError === ""

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: qsTr("MMS carrier settings")
            }
            TextField {
                id: mmscField

                objectName: "mmscField"
                width: parent.width
                label: qsTr("MMSC")
                placeholderText: "http://mms.example.com/mms"
                description: text !== "" ? dialog.mmscError : qsTr("The address of your carrier's MMS server")
                errorHighlight: text !== "" && dialog.mmscError !== ""
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: proxyField.focus = true
            }
            TextField {
                id: proxyField

                objectName: "proxyField"
                width: parent.width
                label: qsTr("MMS proxy")
                placeholderText: qsTr("None")
                description: dialog.proxyError !== "" ? dialog.proxyError : qsTr("Leave empty if your carrier has none")
                errorHighlight: dialog.proxyError !== ""
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: apnField.focus = true
            }
            TextField {
                id: apnField

                objectName: "apnField"
                width: parent.width
                label: qsTr("MMS APN")
                placeholderText: "mms.example.com"
                description: text !== "" ? dialog.apnError : qsTr("Often the same as the internet APN")
                errorHighlight: text !== "" && dialog.apnError !== ""
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }

        VerticalScrollDecorator {}
    }
}
