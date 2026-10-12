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
                objectName: "restartItem"
                visible: !!page.app.currentSession && page.app.currentSession.failed
                text: qsTr("Restart session")
                onClicked: page.app.currentSession.start()
            }
            MenuItem {
                objectName: "settingsItem"
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { app: page.app })
            }
            MenuItem {
                objectName: "smallerItem"
                text: qsTr("Smaller text")
                enabled: page.app.fontSize.value > page.app.minFontSize
                onClicked: page.setFontSize(page.app.fontSize.value - 2)
            }
            MenuItem {
                objectName: "largerItem"
                text: qsTr("Larger text")
                enabled: page.app.fontSize.value < page.app.maxFontSize
                onClicked: page.setFontSize(page.app.fontSize.value + 2)
            }
            MenuItem {
                objectName: "sessionsItem"
                visible: page.app.sessions.length > 1
                text: qsTr("Sessions (%1)").arg(page.app.sessions.length)
                onClicked: pageStack.push(Qt.resolvedUrl("SessionsPage.qml"), { app: page.app })
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
                onClicked: {
                    Clipboard.text = page.currentView.selection;
                    page.currentView.clearSelection();
                    Notices.show(qsTr("Copied to clipboard"));
                }
            }
        }

        Item {
            id: viewport

            y: Math.max(0, Math.min(flick.contentY, flick.history))
            width: flick.width
            height: flick.height

            Item {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    bottom: keyRow.visible ? keyRow.top : parent.bottom
                }

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
