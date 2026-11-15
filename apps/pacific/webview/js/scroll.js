// SPDX-FileCopyrightText: 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-browser apps/wpe/WPEUserScripts.h)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
//
// Scroll and pinch bridges, from Atlantic's kScrollBridge and kPinchBridge
// (atlantic-browser c150119). Isolated script world.
//   pacificScroll {scrollY, scrollHeight, innerHeight}, at most every 100 ms:
//                 drives the collapse-on-scroll toolbar.
//   pacificPinch  {consumed}: whether the page itself handles two-finger
//                 gestures (maps), so the UI can leave pinch to the page.
//   pacificPull   {pullable} / {consumed}: pull to refresh's say for each
//                 touch (see below).
//   pacificSwipe  {back, forward} / {consumed}: the same for swiping back
//                 and forward.
//   pacificPrefetch {host}: a finger came down on a link to another site,
//                 whose name the browser then resolves ahead of the tap
//                 (each host once a page).
(function() {
    if (window.__pacificScrollInstalled) return;
    window.__pacificScrollInstalled = true;

    var pending = false;
    function report() {
        pending = false;
        try {
            window.webkit.messageHandlers.pacificScroll.postMessage({
                scrollY: window.scrollY,
                scrollHeight: document.documentElement.scrollHeight,
                innerHeight: window.innerHeight
            });
        } catch (e) {}
    }
    window.addEventListener('scroll', function() {
        if (!pending) {
            pending = true;
            setTimeout(report, 100);
        }
    }, { passive: true, capture: true });

    // Pull to refresh (pacificPull): for each one-finger touch, whether the
    // page is at its top under the finger (no box scrolled down there) and
    // lets the browser have an overscroll (overscroll-behavior-y auto, as
    // Chrome requires; Safari ignores it); and, once, if the page then takes
    // the drag itself (preventDefault on touchmove).
    function overscrollAllowed(el) {
        try {
            var v = getComputedStyle(el).overscrollBehaviorY;
            return !v || v === 'auto';
        } catch (e) { return true; }
    }
    var pullTouch = false;
    window.addEventListener('touchstart', function(e) {
        pullTouch = e.touches.length === 1;
        if (!pullTouch) return;
        var pullable = window.scrollY <= 0 && overscrollAllowed(document.documentElement)
            && (!document.body || overscrollAllowed(document.body));
        for (var el = e.target; pullable && el && el.nodeType === 1 && el !== document.body; el = el.parentElement) {
            if (el.scrollTop > 0) pullable = false;
            else if (el.scrollHeight > el.clientHeight && !overscrollAllowed(el)) pullable = false;
        }
        try { window.webkit.messageHandlers.pacificPull.postMessage({ pullable: pullable }); } catch (err) {}
    }, { passive: true, capture: true });
    // Bubbling, after the page's own listeners.
    window.addEventListener('touchmove', function(e) {
        if (!pullTouch || !e.defaultPrevented) return;
        pullTouch = false;
        try { window.webkit.messageHandlers.pacificPull.postMessage({ consumed: true }); } catch (err) {}
    }, { passive: true });

    // Swipe back and forward (pacificSwipe): for each one-finger touch,
    // whether the page under the finger can go no further left (back) or
    // right (forward): the page is scrolled to that side, no box under the
    // finger can scroll that way, nothing there takes sideways drags itself
    // (touch-action without pan-x: carousels and maps that use pointer
    // events) and overscroll-behavior-x lets the browser have the overscroll,
    // as Chrome's rules are. And, once, if the page then takes the drag
    // (preventDefault on touchmove).
    function overscrollXAllowed(el) {
        try {
            var v = getComputedStyle(el).overscrollBehaviorX;
            return !v || v === 'auto';
        } catch (e) { return true; }
    }
    function ownsSideways(el) {
        try {
            var ta = getComputedStyle(el).touchAction;
            return !!ta && ta !== 'auto' && ta !== 'manipulation' && ta.indexOf('pan-x') === -1
                && ta.indexOf('pan-left') === -1 && ta.indexOf('pan-right') === -1;
        } catch (e) { return false; }
    }
    var swipeTouch = false;
    window.addEventListener('touchstart', function(e) {
        swipeTouch = e.touches.length === 1;
        if (!swipeTouch) return;
        var root = document.scrollingElement || document.documentElement;
        var maxX = root.scrollWidth - window.innerWidth;
        var ok = overscrollXAllowed(document.documentElement) && (!document.body || overscrollXAllowed(document.body));
        var back = ok && window.scrollX <= 0;
        var forward = ok && window.scrollX >= maxX - 1;
        for (var el = e.target; (back || forward) && el && el.nodeType === 1; el = el.parentElement) {
            if (ownsSideways(el)) { back = forward = false; break; }
            if (el === document.body || el === document.documentElement) continue;
            if (el.scrollWidth > el.clientWidth + 1) {
                var ox = getComputedStyle(el).overflowX;
                if (ox === 'auto' || ox === 'scroll') {
                    if (!overscrollXAllowed(el)) { back = forward = false; break; }
                    if (Math.abs(el.scrollLeft) > 0) back = false;
                    if (Math.abs(el.scrollLeft) + el.clientWidth < el.scrollWidth - 1) forward = false;
                }
            }
        }
        try { window.webkit.messageHandlers.pacificSwipe.postMessage({ back: back, forward: forward }); } catch (err) {}
    }, { passive: true, capture: true });
    window.addEventListener('touchmove', function(e) {
        if (!swipeTouch || !e.defaultPrevented) return;
        swipeTouch = false;
        try { window.webkit.messageHandlers.pacificSwipe.postMessage({ consumed: true }); } catch (err) {}
    }, { passive: true });

    var prefetched = {};
    window.addEventListener('touchstart', function(e) {
        if (e.touches.length !== 1) return;
        var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        if (!a) return;
        var host = a.hostname;
        if (!host || host === location.hostname || prefetched[host]) return;
        if (a.protocol !== 'https:' && a.protocol !== 'http:') return;
        prefetched[host] = true;
        try {
            window.webkit.messageHandlers.pacificPrefetch.postMessage({ host: host });
        } catch (err) {}
    }, { passive: true, capture: true });

    // A page consumes pinches when it preventDefault()s two-finger touches or
    // declares a touch-action without pinch-zoom (Google Maps: none on body).
    // The "not consumed" verdict waits for the first two-finger touchmove:
    // pages often leave touchstart alone and consume the move.
    var verdictSent = false;
    function post(consumed) {
        if (verdictSent) return;
        verdictSent = true;
        try { window.webkit.messageHandlers.pacificPinch.postMessage({ consumed: consumed }); } catch (err) {}
    }
    function blocksPinch(el) {
        try {
            for (var n = el; n && n.nodeType === 1; n = n.parentElement) {
                var ta = getComputedStyle(n).touchAction;
                if (!ta || ta === 'auto' || ta === 'manipulation') continue;
                if (ta.indexOf('pinch-zoom') === -1) return true;
            }
        } catch (err) {}
        return false;
    }
    function check(e) {
        if (!e.touches || e.touches.length < 2 || verdictSent) return;
        if (blocksPinch(e.target)) { post(true); return; }
        var isMove = e.type === 'touchmove';
        setTimeout(function() {
            if (verdictSent) return;
            if (e.defaultPrevented) post(true);
            else if (isMove) post(false);
        }, 0);
    }
    function reset(e) {
        if (!e.touches || e.touches.length < 2) verdictSent = false;
    }
    window.addEventListener('touchstart', check, { passive: true, capture: true });
    window.addEventListener('touchmove', check, { passive: true, capture: true });
    window.addEventListener('touchend', reset, { passive: true, capture: true });
    window.addEventListener('touchcancel', reset, { passive: true, capture: true });
})();
