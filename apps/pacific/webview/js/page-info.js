// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Page metadata for the chrome, from Pacific's isolated script world:
//   pacificPageInfo {icons: [{href, sizes, rel}], themeColor, manifest,
//                    viewportWidth, viewWidth, viewportFitCover}
// viewportWidth is the layout width the page asks for: its meta viewport's
// width in CSS px, 980 without a viewport tag (the phone-browser default),
// 0 for width=device-width. viewWidth is the window's width in CSS px at the
// current zoom.
// sent at DOMContentLoaded and when the <head> changes (SPAs swap icons).
// Also pacificPainted {} once the document has painted (below).
(function() {
    if (window.__pacificPageInfoInstalled || window !== window.top) return;
    window.__pacificPageInfoInstalled = true;

    var last = '';
    function viewportWidth() {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) return 980;
        var m = /(?:^|[,;\s])width\s*=\s*([^,;\s]+)/i.exec(meta.getAttribute('content') || '');
        if (!m) return 0;
        var w = parseFloat(m[1]);
        return isFinite(w) && w > 0 ? Math.min(w, 10000) : 0;
    }
    function collect() {
        var icons = [];
        var links = document.querySelectorAll('link[rel]');
        for (var i = 0; i < links.length && icons.length < 16; i++) {
            var rel = (links[i].getAttribute('rel') || '').toLowerCase();
            if (rel.indexOf('icon') === -1) continue;
            icons.push({ href: links[i].href, sizes: links[i].getAttribute('sizes') || '', rel: rel });
        }
        if (!icons.length)
            icons.push({ href: location.origin + '/favicon.ico', sizes: '', rel: 'implicit' });
        var theme = document.querySelector('meta[name="theme-color"]');
        var manifest = document.querySelector('link[rel="manifest"]');
        var meta = document.querySelector('meta[name="viewport"]');
        var info = {
            // The page lays itself out around the notch (env(safe-area-inset-*)).
            viewportFitCover: !!meta && /(?:^|[,;\s])viewport-fit\s*=\s*cover/i.test(meta.getAttribute('content') || ''),
            icons: icons,
            themeColor: theme ? theme.getAttribute('content') || '' : '',
            manifest: manifest ? manifest.href : '',
            viewportWidth: viewportWidth(),
            viewWidth: window.innerWidth
        };
        var json = JSON.stringify(info);
        if (json === last) return;
        last = json;
        try { window.webkit.messageHandlers.pacificPageInfo.postMessage(info); } catch (e) {}
    }
    var timer = null;
    function schedule() {
        if (timer) return;
        timer = setTimeout(function() { timer = null; collect(); }, 200);
    }
    if (document.readyState === 'loading')
        document.addEventListener('DOMContentLoaded', collect, { once: true });
    else
        collect();
    window.addEventListener('load', schedule, { once: true });

    // pacificPainted {}: the document has painted (its first paint, a frame
    // later), or is back from the back-forward cache. The view shows the page being left until then: frames that
    // arrive after the commit can still be the old document's.
    var painted = false;
    function paintedNow() {
        if (painted) return;
        painted = true;
        requestAnimationFrame(function() {
            requestAnimationFrame(function() {
                try { window.webkit.messageHandlers.pacificPainted.postMessage({}); } catch (e) {}
            });
        });
    }
    try {
        new PerformanceObserver(function(list) {
            // first-paint or first-contentful-paint, whichever WebKit
            // reports first.
            if (list.getEntries().length) paintedNow();
        }).observe({ type: 'paint', buffered: true });
    } catch (e) {}
    // A page with nothing contentful to paint (blank, all canvas) or no
    // paint timing: shortly after it is parsed.
    document.addEventListener('DOMContentLoaded', function() { setTimeout(paintedNow, 300); }, { once: true });
    window.addEventListener('pageshow', function(e) {
        if (e.persisted) { painted = false; paintedNow(); }
    });
    if (document.head)
        new MutationObserver(schedule).observe(document.head, { childList: true, subtree: true, attributes: true, attributeFilter: ['href', 'content'] });
})();
