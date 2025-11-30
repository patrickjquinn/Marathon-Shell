import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonApp.Terminal

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

    TerminalEngine {
        id: terminalEngine

        onFinished: {
            root.sessionFinished();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Output display
        Flickable {
            id: outputFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: terminalRenderer.width
            contentHeight: terminalRenderer.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // Padding
            leftMargin: MSpacing.md
            rightMargin: MSpacing.md
            topMargin: MSpacing.md
            bottomMargin: MSpacing.md

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                active: outputFlickable.moving || outputFlickable.flicking
            }

            TerminalRenderer {
                id: terminalRenderer
                width: outputFlickable.width - (outputFlickable.leftMargin + outputFlickable.rightMargin)
                height: outputFlickable.height - (outputFlickable.topMargin + outputFlickable.bottomMargin)
                terminal: terminalEngine

                font.family: MTypography.fontFamilyMono
                font.pixelSize: 14

                textColor: MColors.text
                backgroundColor: "transparent"
                selectionColor: Qt.rgba(MColors.accent.r, MColors.accent.g, MColors.accent.b, 0.4)

                focus: true // Capture keyboard input

                onCharSizeChanged: updateTerminalSize()
                onWidthChanged: updateTerminalSize()
                onHeightChanged: updateTerminalSize()

                function updateTerminalSize() {
                    if (charWidth > 0 && charHeight > 0) {
                        var cols = Math.floor(width / charWidth);
                        var rows = Math.floor(height / charHeight);
                        if (cols > 0 && rows > 0) {
                            terminalEngine.resize(cols, rows);
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true

                    property point startPos
                    property bool selecting: false

                    onPressed: function (mouse) {
                        terminalRenderer.clearSelection();
                        startPos = Qt.point(mouse.x, mouse.y);
                        selecting = true;

                        // Focus the hidden input to ensure keyboard works
                        terminalRenderer.forceActiveFocus(); // Assuming terminalRenderer is the input field
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
                        if (text.length > 0) {
                            // Auto-copy to clipboard on selection end (Linux terminal style)
                            // Or show a menu? For now, let's just log it or keep it selected.
                            // Ideally we'd have a context menu.
                            console.log("Selected text:", text);
                        }
                    }

                    onPressAndHold: function (mouse) {
                    // TODO: Show context menu (Copy/Paste)
                    // HapticService.light() // HapticService is not defined in this context
                    }
                }

                // Handle keyboard input
                Keys.onPressed: event => {
                    var text = event.text;
                    var key = event.key;
                    var modifiers = event.modifiers;

                    // Handle special keys
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

                    // Ctrl+C, etc.
                    if (modifiers & Qt.ControlModifier) {
                        if (key >= Qt.Key_A && key <= Qt.Key_Z) {
                            terminalEngine.sendKey(key, text, modifiers);
                            event.accepted = true;
                            return;
                        }
                    }

                    // Normal text input
                    if (text.length > 0) {
                        terminalEngine.sendInput(text);
                        event.accepted = true;
                    }
                }

                // Ensure focus is kept
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        terminalRenderer.forceActiveFocus();
                        Qt.inputMethod.show(); // Show virtual keyboard on touch
                    }
                }
            }
        }
    }
}
