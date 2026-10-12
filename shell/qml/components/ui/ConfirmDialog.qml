import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// A full-screen Silica dialog on the ambience: Cancel top-left, the
// caller's verb top-right, then what will happen.
Item {
    id: confirmDialog

    property string title: ""
    property string message: ""
    property string confirmText: ""
    property var onConfirm: null
    property var onCancel: null
    property bool shown: false

    signal confirmed
    signal cancelled

    function show(titleText, messageText, confirmCallback, verb) {
        title = titleText;
        message = messageText;
        onConfirm = confirmCallback;
        confirmText = verb || qsTr("Accept");
        shown = true;
    }

    function hide() {
        shown = false;
    }

    function cancel() {
        cancelled();
        if (onCancel)
            onCancel();
        hide();
    }

    function accept() {
        confirmed();
        if (onConfirm)
            onConfirm();
        hide();
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: shown ? 1 : 0
    z: 2500

    KeelAmbienceBackground {
        anchors.fill: parent
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
    }

    // Taps outside the header actions do nothing.
    MouseArea {
        anchors.fill: parent
    }

    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight
        height: Silica.Theme.itemSizeLarge

        Silica.BackgroundItem {
            objectName: "cancelButton"
            anchors.left: parent.left
            width: parent.width / 2
            height: parent.height
            onClicked: confirmDialog.cancel()

            Silica.Label {
                anchors.left: parent.left
                anchors.leftMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Cancel")
                font.pixelSize: Silica.Theme.fontSizeLarge
                color: parent.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            }
        }

        Silica.BackgroundItem {
            objectName: "confirmButton"
            anchors.right: parent.right
            width: parent.width / 2
            height: parent.height
            onClicked: confirmDialog.accept()

            Silica.Label {
                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: confirmDialog.confirmText
                font.pixelSize: Silica.Theme.fontSizeLarge
                color: Silica.Theme.highlightColor
                truncationMode: Silica.TruncationMode.Fade
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.margins: Silica.Theme.horizontalPageMargin
        anchors.topMargin: Silica.Theme.paddingLarge
        spacing: Silica.Theme.paddingMedium

        Silica.Label {
            width: parent.width
            text: confirmDialog.title
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeExtraLarge
            font.family: Silica.Theme.fontFamilyHeading
            wrapMode: Text.Wrap
        }

        Silica.Label {
            width: parent.width
            text: confirmDialog.message
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
            wrapMode: Text.Wrap
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
    }
}
