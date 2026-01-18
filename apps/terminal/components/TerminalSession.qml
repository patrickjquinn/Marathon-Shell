import MarathonApp.Terminal
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property alias title: terminalEngine.title
    property alias running: terminalEngine.running

    signal sessionFinished

    function start() {
        terminalEngine.start();
    }

    function terminate() {
        terminalEngine.terminate();
    }

    function sendKey(key, text, modifiers) {
        terminalEngine.sendKey(key, text, modifiers);
    }

    function forceFocus() {
        terminalRenderer.forceActiveFocus(Qt.ActiveWindowFocusReason);
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            forceFocus();
        });
    }

    TerminalEngine {
        id: terminalEngine

        onFinished: {
            root.sessionFinished();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Flickable {
            id: outputFlickable

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: terminalRenderer.width
            contentHeight: terminalRenderer.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            leftMargin: MSpacing.md
            rightMargin: MSpacing.md
            topMargin: MSpacing.md
            bottomMargin: MSpacing.md

            TerminalRenderer {
                id: terminalRenderer

                function updateTerminalSize() {
                    if (charWidth > 0 && charHeight > 0) {
                        var cols = Math.floor(width / charWidth);
                        var rows = Math.floor(height / charHeight);
                        if (cols > 0 && rows > 0)
                            terminalEngine.resize(cols, rows);
                    }
                }

                width: outputFlickable.width - (outputFlickable.leftMargin + outputFlickable.rightMargin)
                height: outputFlickable.height - (outputFlickable.topMargin + outputFlickable.bottomMargin)
                terminal: terminalEngine
                font.family: MTypography.fontFamilyMono
                font.pixelSize: 14
                textColor: MColors.text
                backgroundColor: "transparent"
                selectionColor: Qt.rgba(MColors.accent.r, MColors.accent.g, MColors.accent.b, 0.4)
                onCharSizeChanged: updateTerminalSize()
                onWidthChanged: updateTerminalSize()
                onHeightChanged: updateTerminalSize()
                Keys.onPressed: event => {
                    var text = event.text;
                    var key = event.key;
                    var modifiers = event.modifiers;
                    if (key === Qt.Key_Backspace) {
                        terminalEngine.sendKey(key, "", modifiers);
                        event.accepted = true;
                        return;
                    }
                    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                        terminalEngine.sendKey(key, "", modifiers);
                        event.accepted = true;
                        return;
                    }
                    if (key === Qt.Key_Up || key === Qt.Key_Down || key === Qt.Key_Left || key === Qt.Key_Right) {
                        terminalEngine.sendKey(key, "", modifiers);
                        event.accepted = true;
                        return;
                    }
                    if (key === Qt.Key_Tab) {
                        terminalEngine.sendKey(key, "", modifiers);
                        event.accepted = true;
                        return;
                    }
                    if (key === Qt.Key_Escape) {
                        terminalEngine.sendKey(key, "", modifiers);
                        event.accepted = true;
                        return;
                    }
                    if (modifiers & Qt.ControlModifier) {
                        if (key >= Qt.Key_A && key <= Qt.Key_Z) {
                            terminalEngine.sendKey(key, text, modifiers);
                            event.accepted = true;
                            return;
                        }
                    }
                    if (text.length > 0) {
                        terminalEngine.sendInput(text);
                        event.accepted = true;
                    }
                }

                MouseArea {
                    property point startPos
                    property bool selecting: false

                    anchors.fill: parent
                    preventStealing: true
                    onPressed: function (mouse) {
                        terminalRenderer.clearSelection();
                        startPos = Qt.point(mouse.x, mouse.y);
                        selecting = true;
                        terminalRenderer.forceActiveFocus();
                    }
                    onPositionChanged: function (mouse) {
                        if (selecting) {
                            var startGrid = terminalRenderer.positionToGrid(startPos.x, startPos.y);
                            var endGrid = terminalRenderer.positionToGrid(mouse.x, mouse.y);
                            terminalRenderer.select(startGrid.x, startGrid.y, endGrid.x, endGrid.y);
                        }
                    }
                    onReleased: function (mouse) {
                        selecting = false;
                        var text = terminalRenderer.selectedText();
                        if (text.length > 0)
                            console.log("Selected text:", text);
                    }
                    onPressAndHold: function (mouse) {}
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                active: outputFlickable.moving || outputFlickable.flicking
            }
        }
    }
}
