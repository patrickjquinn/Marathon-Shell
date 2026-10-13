// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Cover. API from the Silica public documentation (allowResize,
// coverActionArea, size, status, transparent; Cover.Active etc.).
// Clean-room. Under keel-shell, status follows the shell's CoverStatus
// (keel/shell/PROTOCOL.md: 1 = cover window exposed), through Activating and
// Deactivating. In direct mode Lipstick draws the cover actions itself and
// calls back when one is tapped (Shell.setCoverActions, coveractions.h): taps
// on them never reach the cover window. Under keel-shell they are drawn in
// coverActionArea and triggered by taps, which keel-shell forwards to the
// cover window (PROTOCOL.md section 3).
import QtQuick
import Keel 1.0

Item {
    id: cover

    enum Status { Inactive, Activating, Active, Deactivating }
    enum Size { Large, Small }

    property bool transparent: false
    property bool allowResize: false
    // Keel: the size of the cover window the compositor gives (Lipstick sizes
    // the cover surface): Small when it is nearer coverSizeSmall's height.
    readonly property int size: Window.height > 0
                                && Window.height < (Theme.coverSizeLarge.height + Theme.coverSizeSmall.height) / 2
                                ? Cover.Small : Cover.Large
    // Keel: the shell reports only exposed or not; the cover passes through
    // Activating and Deactivating on the way, for one turn of the event loop,
    // so handlers that prepare or pause content on those statuses run.
    readonly property int status: _status
    property int _status: Cover.Inactive
    readonly property bool _shown: (Shell.connected || Shell.direct) && Shell.coverStatus === Shell.CoverActive
    on_ShownChanged: {
        _status = _shown ? Cover.Activating : Cover.Deactivating
        _statusSettle.restart()
    }
    property Timer _statusSettle: Timer {
        interval: 0
        onTriggered: cover._status = cover._shown ? Cover.Active : Cover.Inactive
    }
    readonly property Item coverActionArea: actionArea
    property bool highlighted: false

    // The enabled CoverActionList among the cover's non-visual children.
    property var _actionLists: []
    readonly property var _actionList: {
        for (var i = 0; i < _actionLists.length; ++i)
            if (_actionLists[i].enabled)
                return _actionLists[i]
        return null
    }
    readonly property var _actions: _actionList ? _actionList._actionObjects : []

    // Direct mode: the actions go to Lipstick, which draws them over the
    // cover (with its own background when iconBackground is set).
    readonly property bool _lipstickDraws: Shell.direct
    readonly property var _actionIcons: {
        var icons = []
        for (var i = 0; i < _actions.length; ++i)
            icons.push(String(_actions[i].iconSource))
        return icons
    }
    readonly property bool _actionBackground: _actionList !== null && _actionList.iconBackground
    readonly property var _coverWindow: Window.window
    function _publishActions() {
        if (_lipstickDraws && _coverWindow)
            Shell.setCoverActions(_coverWindow, _actionIcons, _actionBackground)
    }
    on_ActionIconsChanged: _publishActions()
    on_ActionBackgroundChanged: _publishActions()
    on_CoverWindowChanged: _publishActions()
    Connections {
        target: Shell
        enabled: cover._lipstickDraws
        function onCoverActionTriggered(index) {
            if (index >= 0 && index < cover._actions.length)
                cover._actions[index].trigger()
        }
    }

    function _collectActionLists() {
        var found = []
        var r = cover.resources
        for (var i = 0; i < r.length; ++i)
            if (r[i] && r[i].hasOwnProperty("__keel_coveractionlist"))
                found.push(r[i])
        _actionLists = found
    }
    Component.onCompleted: {
        _status = _shown ? Cover.Active : Cover.Inactive
        _collectActionLists()
        _publishActions()
    }

    implicitWidth: Theme.coverSizeLarge.width
    implicitHeight: Theme.coverSizeLarge.height

    Rectangle {
        z: -1
        anchors.fill: parent
        visible: !cover.transparent
        radius: Theme.paddingMedium
        color: Theme.rgba(Theme.highlightDimmerColor, 0.9)
    }

    Item {
        id: actionArea
        z: 1000
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.round(Theme.itemSizeSmall * 1.2)
        Rectangle {
            anchors.fill: parent
            visible: !cover._lipstickDraws && cover._actionList !== null && cover._actionList.iconBackground
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightDimmerColor, 0.8) }
            }
        }
        Row {
            anchors.fill: parent
            visible: !cover._lipstickDraws
            Repeater {
                model: cover._actions.length
                MouseArea {
                    id: actionButton
                    required property int index
                    width: actionArea.width / Math.max(1, cover._actions.length)
                    height: actionArea.height
                    onClicked: cover._actions[index].trigger()
                    Image {
                        anchors.centerIn: parent
                        source: cover._actions[actionButton.index].iconSource
                        sourceSize.width: Theme.iconSizeSmall
                        sourceSize.height: Theme.iconSizeSmall
                        opacity: parent.pressed ? Theme.opacityHigh : 1.0
                    }
                }
            }
        }
    }
}
