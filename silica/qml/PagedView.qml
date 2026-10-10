// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// PagedView (Silica public documentation, "PagedView QML Type"): a view that
// shows one item of a model at a time; dragging along its direction pulls
// the adjacent item in. Keel's clean-room implementation (Silica's is native
// and closed): members and enums from the documentation, plus the attached
// PagedView.isCurrentItem and PagedView.exposed that Silica's BSD TabView
// and TabItem read (native base: plugin/cpp/private/pagedview.h). Pages are
// the model's delegates made through a DelegateModel; the current one and
// cacheSize - 1 around it are kept (an adjacent one is made when a drag
// pulls it in), the others are released. The drag is a DragHandler, so
// children keep their presses and clicks until the drag threshold is
// passed. Alignment enum values are Qt's (Qt.AlignLeft and so on); the
// defaults of moveDragThreshold, moveDuration and the spacings are Keel's.
import QtQuick
import QtQml.Models
import Sailfish.Silica
import Sailfish.Silica.private 1.0 as SilicaPrivate

SilicaPrivate.PagedViewBase {
    id: view

    enum Direction { LeftToRight, RightToLeft, TopToBottom, BottomToTop }
    enum HorizontalAlignment { AlignLeft = 1, AlignRight = 2, AlignHCenter = 4 }
    enum VerticalAlignment { AlignTop = 32, AlignBottom = 64, AlignVCenter = 128 }
    enum WrapMode { NoWrap, WrapBegin, WrapEnd, Wrap }
    enum Transition { Animated, Immediate }

    readonly property bool __keel_silica_style: true
    property bool highlighted: palette._parentHighlighted
    /*override*/ readonly property SilicaPrivate.Palette palette: SilicaPrivate.Palette {}

    // A model and a delegate, or an ObjectModel of ready-made items (as
    // with Silica's PagedView: jolla-camera's switcher is a VisualItemModel).
    property var model
    property alias delegate: delegateModel.delegate
    // Kept by _updateCount(), not bound: laying pages out when the count
    // changes makes delegates, which can change the DelegateModel's count
    // again (a binding loop).
    readonly property int count: _count
    property int currentIndex
    readonly property Item currentItem: _currentItem
    property int cacheSize: 5
    readonly property Item contentItem: content
    property int direction: PagedView.LeftToRight
    property int dragThreshold: Theme.startDragDistance
    readonly property bool dragging: dragHandler.active || _chained
    property int horizontalAlignment: PagedView.AlignHCenter
    property real horizontalSpacing
    property bool interactive: true
    property real moveDragThreshold: Theme.itemSizeSmall
    property int moveDuration: 300
    readonly property bool moving: dragging || moveAnimation.running
    property int verticalAlignment: PagedView.AlignVCenter
    property real verticalSpacing
    property int wrapMode: PagedView.Wrap

    function moveTo(index, transition) {
        if (index < 0 || index >= count)
            return
        if (transition === PagedView.Immediate) {
            moveAnimation.stop()
            _transitionFrom = -1
            _offset = 0
            _setCurrent(index)
            _layout()
        } else if (index !== currentIndex) {
            _animateTo(index, index > currentIndex ? 1 : -1)
        }
    }

    // Internal.
    // An ObjectModel (QtQml.Models): it has get() and append() like a
    // ListModel, but no setProperty().
    readonly property var _objectModel: model && typeof model === "object" && model.get !== undefined
                                        && model.append !== undefined && model.setProperty === undefined
                                        && model.count !== undefined ? model : null
    _keelContentWidth: content.width
    _keelContentHeight: content.height

    readonly property bool _horizontal: direction === PagedView.LeftToRight || direction === PagedView.RightToLeft
    // +1 where greater indexes lie to the right or below.
    readonly property int _sign: direction === PagedView.LeftToRight || direction === PagedView.TopToBottom ? 1 : -1
    readonly property real _extent: _horizontal ? content.width + horizontalSpacing : content.height + verticalSpacing
    property real _offset
    property real _dragBase
    property Item _currentItem: null
    property int _shownIndex: -1
    property int _transitionFrom: -1
    property int _transitionR
    property bool _internal
    property bool _ready
    property int _count
    // A drag this view handed on (the enclosing PagedView it now moves), and
    // whether a nested view's drag moves this one.
    property var _dragChain: null
    property bool _chained

    function _updateCount() {
        var c = _objectModel ? _objectModel.count : delegateModel.count
        if (c !== _count)
            _count = c
    }
    property var _window: []

    // The items shown now, even in part (Silica's exposedItems), and the
    // item made for `index`, or null when it is not made (Silica's
    // itemAt): Silica's TabButton reads both to follow a drag between
    // tabs. exposedItems changes whenever the pages move, so bindings that
    // name it re-evaluate itemAt.
    readonly property var exposedItems: _exposedItems
    property var _exposedItems: []
    function itemAt(index) {
        for (var i = 0; i < _window.length; ++i) {
            if (_window[i].index === index)
                return _window[i].item
        }
        return null
    }

    function _prev(i) {
        if (i > 0)
            return i - 1
        return (wrapMode === PagedView.Wrap || wrapMode === PagedView.WrapBegin) && count > 1 ? count - 1 : -1
    }

    function _next(i) {
        if (i < count - 1)
            return i + 1
        return (wrapMode === PagedView.Wrap || wrapMode === PagedView.WrapEnd) && count > 1 ? 0 : -1
    }

    function _setCurrent(index) {
        _internal = true
        currentIndex = index
        _internal = false
        _shownIndex = index
    }

    function _axis(r) {
        return r * _sign * _extent + _offset
    }

    function _alignX(item) {
        if (horizontalAlignment === PagedView.AlignLeft)
            return 0
        if (horizontalAlignment === PagedView.AlignRight)
            return content.width - item.width
        return (content.width - item.width) / 2
    }

    function _alignY(item) {
        if (verticalAlignment === PagedView.AlignTop)
            return 0
        if (verticalAlignment === PagedView.AlignBottom)
            return content.height - item.height
        return (content.height - item.height) / 2
    }

    // The pages to keep: index -> position relative to the current one.
    function _wanted() {
        var wanted = {}
        if (count === 0 || currentIndex < 0 || currentIndex >= count)
            return wanted
        wanted[currentIndex] = 0
        var radius = Math.max(0, Math.floor((cacheSize - 1) / 2))
        var p = currentIndex, n = currentIndex
        for (var k = 1; k <= radius; ++k) {
            p = p >= 0 ? _prev(p) : -1
            n = n >= 0 ? _next(n) : -1
            if (n >= 0 && wanted[n] === undefined)
                wanted[n] = k
            if (p >= 0 && wanted[p] === undefined)
                wanted[p] = -k
        }
        // The neighbour a drag is pulling in.
        if (_offset * _sign > 0) {
            var before = _prev(currentIndex)
            if (before >= 0 && wanted[before] === undefined)
                wanted[before] = -1
        } else if (_offset * _sign < 0) {
            var after = _next(currentIndex)
            if (after >= 0 && wanted[after] === undefined)
                wanted[after] = 1
        }
        if (_transitionFrom >= 0 && _transitionFrom < count && _transitionFrom !== currentIndex)
            wanted[_transitionFrom] = _transitionR
        return wanted
    }

    function _bind(item, r) {
        item.parent = content
        item.x = Qt.binding(function() { return view._horizontal ? view._axis(r) + view._alignX(item) : view._alignX(item) })
        item.y = Qt.binding(function() { return view._horizontal ? view._alignY(item) : view._axis(r) + view._alignY(item) })
        // An ObjectModel's items are the app's: their own `visible` stays.
        if (!_objectModel)
            item.visible = Qt.binding(function() { return Math.abs(view._axis(r)) < view._extent })
    }

    // An ObjectModel's items all stay laid out (they are not made or
    // released): the wanted ones where _wanted() puts them, the others in
    // index order beyond them, out of view.
    function _layoutObjects(wanted) {
        var pages = []
        var current = null
        for (var idx = 0; idx < _objectModel.count; ++idx) {
            var item = _objectModel.get(idx)
            if (!item)
                continue
            var r = wanted[idx] !== undefined ? wanted[idx] : (idx - currentIndex) * 2 * Math.max(1, cacheSize)
            _bind(item, r)
            pages.push({ "item": item, "r": r, "index": idx })
            if (idx === currentIndex)
                current = item
        }
        _window = pages
        // The attached properties first: a currentItem handler reads
        // PagedView.isCurrentItem (jolla-camera's switcher does).
        _updateAttached()
        _currentItem = current
    }

    // Releases the pages _wanted() no longer keeps. Never from _layout()
    // itself: that runs from the model's own count change, while the
    // DelegateModel is still applying an insert or remove, and removeGroups()
    // then re-enters it and crashes Qt 6. And through `items`, not
    // `persistedItems`: after a row is removed, Qt 6.8 and 6.10 leave the
    // persisted group's count and positions stale, and releasing by them
    // crashed (deleting the photo on show in the camera's roll did).
    function _releasePages() {
        if (!_ready || _objectModel)
            return
        var wanted = _wanted()
        var items = delegateModel.items
        for (var i = items.count - 1; i >= 0; --i) {
            if (wanted[i] === undefined && items.get(i).inPersistedItems)
                items.removeGroups(i, 1, "persistedItems")
        }
    }

    // A page made later than asked for: create() makes it asynchronously
    // and returns null inside another incubation (a PagedView in a page
    // that loads in the background). The layout tries again shortly until
    // it is made; it used to give up, and the view had no current page at
    // all (the camera's roll, opened before a photo was taken, stayed
    // black). A delegate that cannot be made at all is tried for a few
    // seconds, not for ever.
    Timer {
        id: unmadeRetry

        property int tries

        interval: 32
        onTriggered: {
            if (++tries < 150)
                view._layout()
        }
    }

    function _layout() {
        if (!_ready)
            return
        var wanted = _wanted()
        if (_objectModel) {
            _layoutObjects(wanted)
            return
        }
        // The pages no longer wanted are released later, not now.
        Qt.callLater(_releasePages)
        var pages = []
        var current = null
        var unmade = false
        for (var key in wanted) {
            var idx = Number(key)
            var item = delegateModel.items.create(idx)
            if (!item) {
                unmade = true
                continue
            }
            _bind(item, wanted[key])
            pages.push({ "item": item, "r": wanted[key], "index": idx })
            if (idx === currentIndex)
                current = item
        }
        // A page that left the window stays made until _releasePages(), or,
        // for a removed row, until Qt lets it go: out of sight meanwhile.
        for (var w = 0; w < _window.length; ++w) {
            var old = _window[w].item
            var kept = false
            for (var q = 0; q < pages.length && !kept; ++q)
                kept = pages[q].item === old
            if (!kept && old)
                old.visible = false
        }
        _window = pages
        if (unmade) {
            unmadeRetry.restart()
        } else {
            unmadeRetry.stop()
            unmadeRetry.tries = 0
        }
        // The attached properties first: a currentItem handler reads
        // PagedView.isCurrentItem (jolla-camera's switcher does).
        _updateAttached()
        _currentItem = current
    }

    function _updateAttached() {
        var exposed = []
        for (var i = 0; i < _window.length; ++i) {
            var page = _window[i]
            var shown = Math.abs(_axis(page.r)) < _extent
            _keelUpdate(page.item, page.index === currentIndex, shown)
            if (shown)
                exposed.push(page.item)
        }
        var same = exposed.length === _exposedItems.length
        for (var j = 0; same && j < exposed.length; ++j)
            same = exposed[j] === _exposedItems[j]
        if (!same)
            _exposedItems = exposed
    }

    function _animateTo(index, dir) {
        moveAnimation.stop()
        var from = currentIndex
        _setCurrent(index)
        // The new page continues from where it was; the old one leaves.
        _offset += dir * _sign * _extent
        _transitionFrom = from
        _transitionR = -dir
        _layout()
        moveAnimation.restart()
    }

    function _finishTransition() {
        if (_transitionFrom < 0 && _offset === 0)
            return
        _transitionFrom = -1
        _layout()
    }

    function _drag(translation) {
        var offset = _dragBase + translation
        var revealing = offset * _sign > 0 ? _prev(currentIndex) : offset * _sign < 0 ? _next(currentIndex) : -1
        if (offset !== 0 && revealing < 0) {
            // No page there: resist, as far as a third of the view.
            offset = Math.max(-_extent / 3, Math.min(_extent / 3, offset / 3))
        }
        var before = _offset * _sign
        _offset = offset
        if ((before > 0) !== (offset * _sign > 0) || (before < 0) !== (offset * _sign < 0))
            _layout()
    }

    // Nested views (jolla-camera's camera roll inside its switcher): a drag
    // that starts with this view at rest and pulls in nothing here (the end
    // of a NoWrap model) moves the nearest enclosing PagedView along the same
    // axis that has a page there instead, as Silica's does; otherwise a
    // swipe past the last photo would only stretch the roll.
    function _revealing(offset) {
        return offset * _sign > 0 ? _prev(currentIndex) : offset * _sign < 0 ? _next(currentIndex) : -1
    }
    function _takesChain(offset) {
        return interactive && count > 0 && !dragHandler.active && _revealing(offset) >= 0
    }
    function _chainTarget(offset) {
        // Any item up the tree; a PagedView is the one with _takesChain.
        for (var p = parent; p; p = p.parent) {
            if (p !== view && p._takesChain !== undefined && p._horizontal === _horizontal
                    && p._takesChain(offset))
                return p
        }
        return null
    }
    function _beginChain() {
        moveAnimation.stop()
        _dragBase = _offset
        _chained = true
    }
    function _endChain(velocity) {
        _chained = false
        _release(velocity)
    }

    function _release(velocity) {
        var d = _offset * _sign
        var v = velocity * _sign
        var flick = 600
        if ((d > moveDragThreshold || (v > flick && d > 0)) && _prev(currentIndex) >= 0) {
            _animateTo(_prev(currentIndex), -1)
        } else if ((d < -moveDragThreshold || (v < -flick && d < 0)) && _next(currentIndex) >= 0) {
            _animateTo(_next(currentIndex), 1)
        } else {
            moveAnimation.restart()
        }
    }

    onCurrentIndexChanged: {
        if (_internal || !_ready)
            return
        if (currentIndex < 0 || currentIndex >= count || _shownIndex < 0 || _shownIndex >= count) {
            _shownIndex = currentIndex
            _layout()
            return
        }
        var target = currentIndex
        _internal = true
        currentIndex = _shownIndex
        _internal = false
        if (target !== currentIndex)
            _animateTo(target, target > currentIndex ? 1 : -1)
    }
    onCountChanged: {
        if (!_ready)
            return
        if (count > 0 && (currentIndex < 0 || currentIndex >= count))
            _setCurrent(Math.max(0, Math.min(currentIndex, count - 1)))
        _layout()
    }
    onCacheSizeChanged: _layout()
    on_ObjectModelChanged: {
        _updateCount()
        _layout()
    }
    onWrapModeChanged: _layout()
    onDirectionChanged: _layout()
    on_OffsetChanged: _updateAttached()

    Component.onCompleted: {
        _updateCount()
        _ready = true
        if (count > 0)
            _setCurrent(Math.max(0, Math.min(currentIndex, count - 1)))
        _layout()
    }

    Item {
        id: content
        width: view.width
        height: view.height
    }

    DelegateModel {
        id: delegateModel
        model: view._objectModel ? null : view.model
        onCountChanged: view._updateCount()
    }

    Connections {
        target: view._objectModel
        ignoreUnknownSignals: true
        function onCountChanged() { view._updateCount() }
    }

    DragHandler {
        id: dragHandler
        target: null
        enabled: view.interactive && view.count > 0
        xAxis.enabled: view._horizontal
        yAxis.enabled: !view._horizontal
        dragThreshold: view.dragThreshold
        onActiveChanged: {
            if (active) {
                moveAnimation.stop()
                view._dragBase = view._offset
            } else {
                var velocity = view._horizontal ? centroid.velocity.x : centroid.velocity.y
                if (view._dragChain) {
                    var chain = view._dragChain
                    view._dragChain = null
                    chain._endChain(velocity)
                } else {
                    view._release(velocity)
                }
            }
        }
        onTranslationChanged: {
            if (!active)
                return
            var t = view._horizontal ? translation.x : translation.y
            if (!view._dragChain && view._dragBase === 0 && view._offset === 0
                    && t !== 0 && view._revealing(t) < 0) {
                var outer = view._chainTarget(t)
                if (outer) {
                    view._dragChain = outer
                    outer._beginChain()
                }
            }
            if (view._dragChain)
                view._dragChain._drag(t)
            else
                view._drag(t)
        }
    }

    NumberAnimation {
        id: moveAnimation
        target: view
        property: "_offset"
        to: 0
        duration: view.moveDuration
        easing.type: Easing.InOutQuad
        onRunningChanged: {
            if (!running)
                view._finishTransition()
        }
    }
}
