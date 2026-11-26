pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

// The fingers that unlock the phone: add one, or remove one after the PIN.
Page {
    id: page

    // The finger being removed while the shell checks the PIN.
    property string removing: ""

    function openRemoveDialog(finger) {
        const dialog = pageStack.push(Qt.resolvedUrl("RemotePinDialog.qml"), {
            title: Logic.fingerName(finger),
            message: qsTr("Enter your quick PIN to remove this fingerprint."),
            acceptText: qsTr("Remove")
        });
        dialog.accepted.connect(() => {
            page.removing = finger;
            Security.deleteFingerprint(finger, dialog.pin);
        });
    }

    Connections {
        target: Security

        function onFingerprintDeleted(finger) {
            if (finger !== page.removing)
                return;
            page.removing = "";
            Notices.show(qsTr("Fingerprint removed"));
        }
        function onFingerprintFailed(reason) {
            if (page.removing === "")
                return;
            page.removing = "";
            Notices.show(reason);
        }
    }

    component FingerRow: ListItem {
        id: row

        property alias text: label.text
        property alias icon: glyph.source

        contentHeight: Theme.itemSizeSmall

        Icon {
            id: glyph

            x: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            id: label

            anchors {
                left: glyph.right
                leftMargin: Theme.paddingLarge
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }
            color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
            truncationMode: TruncationMode.Fade
        }
    }

    SilicaListView {
        id: list

        anchors.fill: parent
        model: Security.enrolledFingers
        header: Column {
            width: list.width

            PageHeader {
                title: qsTr("Fingerprint")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                text: qsTr("Touch the sensor on the lock screen to unlock. Your quick PIN is still asked for after a restart, and after 5 fingers the sensor doesn't recognize. Fingerprints never leave this phone.")
            }
            SectionHeader {
                text: qsTr("Fingers")
                visible: list.count > 0
            }
        }
        delegate: FingerRow {
            id: finger

            required property string modelData

            objectName: "finger-" + modelData
            enabled: page.removing === ""
            icon: "image://theme/icon-m-fingerprint"
            text: page.removing === modelData ? qsTr("Removing…") : Logic.fingerName(modelData)
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Remove")
                    onClicked: page.openRemoveDialog(finger.modelData)
                }
            }
            onClicked: openMenu()
        }
        footer: FingerRow {
            objectName: "addFinger"
            width: list.width
            visible: Logic.fingersLeft(Security.enrolledFingers).length > 0
            enabled: page.removing === ""
            icon: "image://theme/icon-m-add"
            text: qsTr("Add fingerprint")
            onClicked: pageStack.push(Qt.resolvedUrl("AddFingerprintDialog.qml"))
        }

        VerticalScrollDecorator {}
    }
}
