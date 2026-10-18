import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Page {
    id: page

    // Between the PIN and the restart, or the shell saying why not.
    property bool erasing: false

    function erase(secret) {
        erasing = true;
        Security.eraseAllContent(secret);
    }

    // After a refusal the dialog comes back saying why.
    function openDialog(error) {
        const dialog = pageStack.push(Qt.resolvedUrl("EraseDialog.qml"), {
            error: error || ""
        });
        dialog.accepted.connect(() => page.erase(dialog.secret));
    }

    Connections {
        target: Security

        function onEraseFailed(reason) {
            if (!page.erasing)
                return;
            page.erasing = false;
            page.openDialog(reason);
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Erase all content")
            }
            Label {
                objectName: "explanation"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: qsTr("Erasing deletes everything on this phone: apps' data, accounts, Wi-Fi networks, settings and your files. It restarts, erases itself and starts setup again, as when it was new.")
            }
            Label {
                objectName: "versionNote"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: (Updates.osVersion !== "" ? qsTr("Marathon OS stays at version %1.").arg(Updates.osVersion) : qsTr("Marathon OS itself stays as it is.")) + " " + qsTr("This can't be undone, so copy anything you want to keep first.")
            }
            Label {
                objectName: "unsupportedLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !Security.canEraseAllContent
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: qsTr("This device can't erase itself yet. Flash a fresh image to start over.")
            }
            Button {
                objectName: "eraseButton"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Security.canEraseAllContent && !page.erasing
                text: qsTr("Erase all content")
                onClicked: page.openDialog("")
            }
            Row {
                objectName: "erasingRow"
                x: Theme.horizontalPageMargin
                height: Theme.itemSizeSmall
                spacing: Theme.paddingMedium
                visible: page.erasing

                BusyIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    size: BusyIndicatorSize.ExtraSmall
                    running: parent.visible
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Restarting to erase…")
                    color: Theme.highlightColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
