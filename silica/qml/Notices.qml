// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Notices singleton: Notices.show(text, duration, anchor, horizontalOffset,
// verticalOffset) queues a Notice (Silica public documentation);
// implementation clean-room. Notices are shown one at a time, in order, each
// for its duration, as Silica's private NoticeItem (BSD, qml/private) in the
// application window's indicator layer; a tap on it dismisses it
// (NoticeItem calls Notices._dismissCurrent()). The ApplicationWindow
// registers itself as `_window`; without one (no window yet) the text goes
// to the log.
//
// Notice and NoticeItem are created by URL, not by type: the module's other
// types (ApplicationWindow, Notice) use this singleton, and a type reference
// back would make the module's types depend on each other in a cycle.
pragma Singleton
import QtQuick

QtObject {
    id: notices

    property Item _window: null
    property var _current: null
    property Item _currentItem: null
    property var _queue: []

    property Component _noticeComponent: Qt.createComponent(Qt.resolvedUrl("Notice.qml"))
    property Component _itemComponent: Qt.createComponent(Qt.resolvedUrl("private/NoticeItem.qml"))
    property Timer _timer: Timer {
        onTriggered: notices._dismissCurrent()
    }

    function show(text, duration, anchor, horizontalOffset, verticalOffset) {
        var properties = { "text": text === undefined || text === null ? "" : String(text) }
        if (duration !== undefined)
            properties.duration = duration
        if (anchor !== undefined)
            properties.anchor = anchor
        if (horizontalOffset !== undefined)
            properties.horizontalOffset = horizontalOffset
        if (verticalOffset !== undefined)
            properties.verticalOffset = verticalOffset
        // Owned by this singleton; destroyed once shown.
        var notice = _noticeComponent.createObject(notices, properties)
        notice._transient = true
        _show(notice)
        return notice
    }

    function _show(notice) {
        if (!notice || notice === _current || _queue.indexOf(notice) >= 0)
            return
        _queue = _queue.concat([notice])
        if (!_current)
            _showNext()
    }

    function _dismiss(notice) {
        if (notice === _current) {
            _dismissCurrent()
            return
        }
        var i = _queue.indexOf(notice)
        if (i >= 0) {
            var queue = _queue.slice()
            queue.splice(i, 1)
            _queue = queue
        }
    }

    function _dismissCurrent() {
        _timer.stop()
        var done = _current
        if (_currentItem) {
            // Hidden at once; destroyed later.
            _currentItem.visible = false
            _currentItem.destroy()
        }
        _currentItem = null
        _current = null
        if (done && done._transient)
            done.destroy()
        _showNext()
    }

    function _showNext() {
        while (_queue.length > 0 && !_current) {
            var notice = _queue[0]
            _queue = _queue.slice(1)
            var parentItem = _window ? _window.indicatorParentItem : null
            if (!parentItem) {
                console.info("Notice: " + notice.text)
                if (notice._transient)
                    notice.destroy()
                continue
            }
            _current = notice
            _currentItem = _itemComponent.createObject(parentItem, {
                "notice": notice,
                "applicationWindow": _window
            })
            _timer.interval = notice.duration > 0 ? notice.duration : 5000
            _timer.restart()
        }
    }
}
