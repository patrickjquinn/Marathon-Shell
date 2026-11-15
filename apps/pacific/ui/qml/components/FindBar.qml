// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Find in page: a field, the number of matches, previous, next, close.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Rectangle {
    id: bar

    property var view
    signal closed

    height: Theme.itemSizeMedium
    color: Theme.rgba(Theme.overlayBackgroundColor, 0.95)

    // Which match is selected, counted from the first one found, as Safari
    // and WebKit's own match index count (0: none yet).
    property int current: 0
    readonly property int matches: view ? view.findMatchCount : 0
    // WebKit stops counting at 1000 (the web view's limit) and says "more".
    readonly property bool manyMatches: matches < 0 || matches > 1000
    onMatchesChanged: {
        if (matches === 0)
            current = 0;
        else if (current === 0 || (!manyMatches && current > matches))
            current = 1;
    }

    function start(): void {
        field.text = "";
        current = 0;
        field.forceActiveFocus();
    }
    function step(forward: var): var {
        if (!view || matches === 0)
            return;
        if (forward) {
            view.findNext();
            current = !manyMatches && current >= matches ? 1 : current + 1;
        } else {
            view.findPrevious();
            current = current <= 1 ? (manyMatches ? 1 : matches) : current - 1;
        }
    }

    // Another page: its matches are not these, so find ends, as in Safari.
    Connections {
        target: bar.visible ? bar.view : null
        function onUrlChanged() {
            bar.view.stopFind();
            bar.closed();
        }
    }

    TextField {
        id: field
        objectName: "findField"
        anchors {
            left: parent.left
            right: count.left
            verticalCenter: parent.verticalCenter
        }
        label: qsTr("Find in page")
        placeholderText: qsTr("Find in page")
        labelVisible: false
        inputMethodHints: Qt.ImhNoPredictiveText
        onTextChanged: {
            // A longer search often has the same count, which then never
            // changes: start at the first match whenever there are some.
            bar.current = text !== "" && bar.matches !== 0 ? 1 : 0;
            if (bar.view)
                bar.view.findText(text, false);
        }
        EnterKey.iconSource: "image://theme/icon-m-enter-next"
        EnterKey.onClicked: bar.step(true)
    }
    Label {
        id: count
        anchors {
            right: previous.left
            rightMargin: Theme.paddingSmall
            verticalCenter: parent.verticalCenter
        }
        text: field.text === "" || !bar.view ? "" : bar.matches === 0 ? qsTr("No matches") : bar.manyMatches ? qsTr("%1 of 1000+").arg(bar.current) : qsTr("%1 of %2").arg(bar.current).arg(bar.matches)
        color: Theme.secondaryHighlightColor
        font.pixelSize: Theme.fontSizeSmall
    }
    IconButton {
        id: previous
        anchors {
            right: next.left
            verticalCenter: parent.verticalCenter
        }
        icon.source: "image://theme/icon-m-up"
        enabled: bar.matches !== 0
        onClicked: bar.step(false)
    }
    IconButton {
        id: next
        anchors {
            right: close.left
            verticalCenter: parent.verticalCenter
        }
        icon.source: "image://theme/icon-m-down"
        enabled: bar.matches !== 0
        onClicked: bar.step(true)
    }
    IconButton {
        id: close
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        icon.source: "image://theme/icon-m-clear"
        onClicked: {
            if (bar.view)
                bar.view.stopFind();
            bar.closed();
        }
    }
}
