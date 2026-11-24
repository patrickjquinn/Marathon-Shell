// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import Sailfish.Silica 1.0

// Theme.pagedScrolling (an e-paper panel, which redraws on every move of a
// list that follows the finger): the flickable stays put under the finger,
// and a swipe past a tenth of it, or a flick, moves it a page, its height
// less a row, in one jump.
//
// DragHandler takes its start threshold along xAxis/yAxis in scene
// coordinates, and the scene may be turned (a panel mounted sideways): each
// press enables the scene axis that lies along the flickable's y.
DragHandler {
    id: root

    property Flickable flickable
    readonly property bool scrollable: flickable && flickable.contentHeight + flickable.topMargin + flickable.bottomMargin > flickable.height
    property bool _turned
    property real _velocity

    function _along(scenePoint) {
        return parent.mapFromItem(null, scenePoint.x, scenePoint.y).y
    }

    function _turn(step) {
        _turned = true
        var f = flickable
        var top = f.originY - f.topMargin
        var bottom = Math.max(top, f.originY + f.contentHeight + f.bottomMargin - f.height)
        f.contentY = Math.max(top, Math.min(bottom, f.contentY + step * (f.height - Theme.itemSizeSmall)))
    }

    function _measure() {
        var v = centroid.velocity
        _velocity = _along(Qt.point(v.x, v.y)) - _along(Qt.point(0, 0))
        var moved = _along(centroid.scenePosition) - _along(centroid.scenePressPosition)
        if (!_turned && Math.abs(moved) >= flickable.height * 0.1)
            _turn(moved < 0 ? 1 : -1)
    }

    target: null
    enabled: Theme.pagedScrolling && scrollable
    onCentroidChanged: {
        if (active) {
            _measure()
        } else {
            var o = parent.mapToItem(null, 0, 0)
            var x = parent.mapToItem(null, 1, 0)
            var sideways = Math.abs(x.y - o.y) > Math.abs(x.x - o.x)
            xAxis.enabled = sideways
            yAxis.enabled = !sideways
        }
    }
    onActiveChanged: {
        if (active) {
            _turned = false
            _measure()
        } else if (!_turned && Math.abs(_velocity) > 600) {
            _turn(_velocity < 0 ? 1 : -1)
        }
    }
}
