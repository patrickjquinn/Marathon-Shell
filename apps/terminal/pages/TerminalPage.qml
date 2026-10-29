pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

Page {
    id: page

    property var app
    readonly property var currentView: views.count > app.currentIndex ? views.itemAt(app.currentIndex) : null

    function focusTerminal() {
        if (currentView)
            currentView.forceFocus();
    }

    function setFontSize(size) {
        app.fontSize.value = Math.max(app.minFontSize, Math.min(app.maxFontSize, size));
    }

    // Deferred to land after Silica's own focus moves (page activation,
    // pulley close).
    onStatusChanged: {
        if (status === PageStatus.Active)
            Qt.callLater(focusTerminal);
    }
    onCurrentViewChanged: {
        flick.toLive();
        Qt.callLater(focusTerminal);
    }

    // History scrolls like the rows above a Silica list, pulley at its top;
    // the terminal stays in view and draws the rows the position asks for.
    SilicaFlickable {
        id: flick

        readonly property real history: page.currentView ? page.currentView.historyLines * page.currentView.lineHeight : 0
        property bool following: true

        function toLive() {
            following = true;
            if (!pulley.active)
                contentY = contentHeight - height;
        }

        objectName: "terminalFlick"
        anchors.fill: parent
        contentHeight: height + history
        onContentHeightChanged: {
            if (following && !pulley.active)
                contentY = contentHeight - height;
        }
        onMovementEnded: following = contentY >= contentHeight - height - 1

        PullDownMenu {
            id: pulley

            objectName: "pulley"

            onActiveChanged: {
                if (active)
                    return;
                if (flick.following)
                    flick.toLive();
                Qt.callLater(page.focusTerminal);
            }

            MenuItem {
                objectName: "settingsItem"
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), {
                    app: page.app
                })
            }
            MenuItem {
                objectName: "sessionsItem"
                visible: page.app.sessions.length > 1
                text: qsTr("Sessions (%1)").arg(page.app.sessions.length)
                onClicked: pageStack.push(Qt.resolvedUrl("SessionsPage.qml"), {
                    app: page.app
                })
            }
            MenuItem {
                objectName: "newSessionItem"
                text: qsTr("New session")
                onClicked: page.app.newSession()
            }
            MenuItem {
                objectName: "pasteItem"
                text: qsTr("Paste")
                enabled: Clipboard.hasText
                onClicked: {
                    flick.toLive();
                    page.app.currentSession.sendInput(Clipboard.text);
                }
            }
            MenuItem {
                objectName: "copyItem"
                visible: !!page.currentView && page.currentView.selection !== ""
                text: qsTr("Copy")
                onClicked: page.currentView.copySelection()
            }
            MenuItem {
                objectName: "restartItem"
                visible: !!page.app.currentSession && !page.app.currentSession.running
                text: qsTr("Restart session")
                onClicked: page.app.currentSession.start()
            }
        }

        Item {
            id: viewport

            y: Math.max(0, Math.min(flick.contentY, flick.history))
            width: flick.width
            height: flick.height

            // Pinch to resize the text; single touches reach the terminal below.
            PinchArea {
                property int startSize

                objectName: "pinchArea"
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    bottom: keyRow.visible ? keyRow.top : parent.bottom
                }
                onPinchStarted: startSize = page.app.fontSize.value
                onPinchUpdated: pinch => page.setFontSize(Math.round(startSize * pinch.scale))

                Repeater {
                    id: views

                    model: page.app.sessions

                    TerminalView {
                        required property var modelData
                        required property int index

                        anchors.fill: parent
                        visible: index === page.app.currentIndex
                        session: modelData
                        scrollOffset: visible ? flick.history - viewport.y : 0
                        fontSize: page.app.fontSize.value
                        colorScheme: page.app.colorScheme.value
                        extraModifiers: keyRow.visible ? keyRow.modifiers : 0
                        onModifiersUsed: keyRow.consumeArmed()
                        onTyped: flick.toLive()
                    }
                }
            }

            Label {
                objectName: "exitedHint"
                anchors {
                    bottom: keyRow.visible ? keyRow.top : parent.bottom
                    bottomMargin: Theme.paddingLarge
                    horizontalCenter: parent.horizontalCenter
                }
                visible: !!page.app.currentSession && !page.app.currentSession.running && !page.app.currentSession.failed
                text: qsTr("Process exited. Tap to restart")
                color: Theme.secondaryHighlightColor
            }

            VirtualKeyRow {
                id: keyRow

                objectName: "keyRow"
                anchors.bottom: parent.bottom
                width: parent.width
                visible: page.app.extraKeys.value
                onKeyTriggered: (key, text, modifiers) => {
                    flick.toLive();
                    if (key === 0)
                        page.app.currentSession.sendInput(text);
                    else
                        page.app.currentSession.sendKey(key, text, modifiers & ~Qt.ControlModifier);
                }
            }
        }
    }
}
