pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Terminal

Item {
    id: root

    property var session
    property int fontSize: Theme.fontSizeTiny
    property string colorScheme: "ambience"
    // Modifiers latched on the extra-keys row, applied to the next key.
    property int extraModifiers: 0
    property string selection: ""
    // Pixels scrolled back into history; 0 shows the live screen.
    property real scrollOffset: 0
    readonly property int historyLines: renderer.historyLines
    readonly property real lineHeight: renderer.charHeight

    signal modifiersUsed
    signal typed

    function forceFocus() {
        renderer.forceActiveFocus(Qt.ActiveWindowFocusReason);
    }

    function clearSelection() {
        renderer.clearSelection();
        selection = "";
    }

    function copySelection() {
        Clipboard.text = selection;
        clearSelection();
        Notices.show(qsTr("Copied to clipboard"));
    }

    function sendKey(key, text, modifiers) {
        session.sendKey(key, text, modifiers);
    }

    function _letterKey(text) {
        const c = text.toUpperCase();
        return c.length === 1 && c >= "A" && c <= "Z" ? Qt.Key_A + c.charCodeAt(0) - 65 : 0;
    }

    // Accepts every key the shell can use, Escape and Ctrl+M included, so
    // none of them reach the page's back and menu handling.
    function handleKey(event) {
        const mods = event.modifiers | extraModifiers;
        let key = event.key;
        switch (key) {
        case Qt.Key_Backspace:
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Up:
        case Qt.Key_Down:
        case Qt.Key_Left:
        case Qt.Key_Right:
        case Qt.Key_Tab:
        case Qt.Key_Escape:
        case Qt.Key_Home:
        case Qt.Key_End:
        case Qt.Key_PageUp:
        case Qt.Key_PageDown:
            session.sendKey(key, "", mods & ~Qt.ControlModifier);
            break;
        case Qt.Key_Backtab:
            session.sendInput("\x1b[Z");
            break;
        default:
            if (mods & Qt.ControlModifier) {
                if (key < Qt.Key_A || key > Qt.Key_Z)
                    key = _letterKey(event.text) || key;
                if ((key >= Qt.Key_A && key <= Qt.Key_Z) || key === Qt.Key_BracketLeft
                        || key === Qt.Key_Backslash || key === Qt.Key_BracketRight) {
                    session.sendKey(key, event.text, mods);
                    break;
                }
            }
            if (event.text.length === 0)
                return;
            if (mods & Qt.AltModifier)
                session.sendKey(key, event.text, Qt.AltModifier);
            else
                session.sendInput(event.text);
        }
        event.accepted = true;
        typed();
        if (extraModifiers !== 0)
            modifiersUsed();
    }

    Rectangle {
        anchors.fill: parent
        color: renderer.backgroundColor
    }

    TerminalRenderer {
        id: renderer

        objectName: "renderer"

        function updateTerminalSize() {
            if (charWidth > 0 && charHeight > 0 && root.session) {
                const cols = Math.floor(width / charWidth);
                const rows = Math.floor(height / charHeight);
                if (cols > 0 && rows > 0)
                    root.session.resize(cols, rows);
            }
        }

        anchors {
            fill: parent
            margins: Theme.paddingMedium
        }
        terminal: root.session
        scrollOffset: root.scrollOffset
        font.pixelSize: root.fontSize
        textColor: root.colorScheme === "light" ? "black" : root.colorScheme === "dark" ? "white" : Theme.primaryColor
        backgroundColor: root.colorScheme === "light" ? "white" : root.colorScheme === "dark" ? "black" : "transparent"
        selectionColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
        activeFocusOnTab: true
        Accessible.role: Accessible.Terminal
        Accessible.name: root.session ? root.session.title : ""
        onCharSizeChanged: updateTerminalSize()
        onWidthChanged: updateTerminalSize()
        onHeightChanged: updateTerminalSize()
        onTerminalChanged: updateTerminalSize()
        Keys.onPressed: event => root.handleKey(event)

        // A tap focuses, a long press starts a selection; plain drags stay
        // with the page so the pulley menu opens.
        MouseArea {
            property point start
            property bool selecting

            objectName: "touchArea"
            anchors.fill: parent
            preventStealing: selecting
            onClicked: {
                root.clearSelection();
                root.forceFocus();
                Qt.inputMethod.show();
            }
            onPressAndHold: mouse => {
                selecting = true;
                start = Qt.point(mouse.x, mouse.y);
                const p = renderer.positionToGrid(mouse.x, mouse.y);
                renderer.select(p.x, p.y, p.x, p.y);
                root.forceFocus();
            }
            onPositionChanged: mouse => {
                if (!selecting)
                    return;
                const a = renderer.positionToGrid(start.x, start.y);
                const b = renderer.positionToGrid(mouse.x, mouse.y);
                renderer.select(a.x, a.y, b.x, b.y);
            }
            onReleased: mouse => {
                if (!selecting)
                    return;
                selecting = false;
                copyButton.anchor = mapToItem(root, mouse.x, mouse.y);
                root.selection = renderer.selectedText();
            }
            onCanceled: selecting = false
        }
    }

    // Just above where the selecting finger lifted.
    Button {
        id: copyButton

        property point anchor

        objectName: "copyButton"
        x: Math.max(0, Math.min(root.width - width, anchor.x - width / 2))
        y: Math.max(0, anchor.y - height - Theme.itemSizeSmall)
        preferredWidth: Theme.buttonWidthTiny
        visible: root.selection !== ""
        text: qsTr("Copy")
        onClicked: {
            root.copySelection();
            root.forceFocus();
        }
    }
}
