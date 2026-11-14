pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0

// The mobile data APN. Automatic: the carrier's attach APN, which the modem
// takes for the SIM from the device's APN database. Otherwise one of the
// carrier's other APNs, or one typed in.
Page {
    id: page

    readonly property bool automatic: Modem.customApn === ""

    function use(apn, user, password) {
        Modem.setApn(apn, user, password);
        Notices.show(apn === "" ? qsTr("Using the automatic APN") : qsTr("Using %1").arg(apn));
    }

    onStatusChanged: if (status === PageStatus.Active)
        Modem.loadApn()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Access point (APN)")
            }
            DetailItem {
                objectName: "liveApn"
                label: qsTr("In use")
                value: Modem.apn !== "" ? Modem.apn : qsTr("Not connected")
            }
            TextSwitch {
                objectName: "automaticSwitch"
                text: qsTr("Automatic")
                description: qsTr("Use your carrier's APN for this SIM")
                checked: page.automatic
                automaticCheck: false
                onClicked: if (!page.automatic)
                    page.use("", "", "")
            }

            SectionHeader {
                visible: Modem.carrierApns.length > 0
                text: qsTr("Your carrier's APNs")
            }
            Repeater {
                model: Modem.carrierApns

                ListItem {
                    id: carrierApn

                    required property var modelData
                    readonly property bool current: !page.automatic && Modem.customApn === modelData.apn

                    contentHeight: Theme.itemSizeMedium
                    onClicked: page.use(modelData.apn, modelData.user, modelData.password)

                    Column {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            width: parent.width
                            text: carrierApn.modelData.apn
                            truncationMode: TruncationMode.Fade
                            color: carrierApn.current || carrierApn.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            text: carrierApn.modelData.name
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Your own APN")
            }
            TextField {
                id: apnField

                objectName: "apnField"
                width: parent.width
                label: qsTr("APN")
                placeholderText: qsTr("e.g. internet")
                text: page.automatic ? "" : Modem.customApn
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                EnterKey.onClicked: userField.focus = true
            }
            TextField {
                id: userField

                width: parent.width
                label: qsTr("Username (optional)")
                placeholderText: label
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.onClicked: passwordField.focus = true
            }
            PasswordField {
                id: passwordField

                width: parent.width
                label: qsTr("Password (optional)")
                placeholderText: label
            }
            Button {
                objectName: "useApn"
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Use this APN")
                enabled: apnField.text.trim() !== ""
                onClicked: page.use(apnField.text.trim(), userField.text, passwordField.text)
            }
        }
    }
}
