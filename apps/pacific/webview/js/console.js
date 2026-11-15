// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Console capture for WebView.consoleMessage, installed only when
// WebView.captureConsole is on (developer tools, tests). WPE's GLib API has no
// console signal, so this wraps console.* in the page's own world (where the
// page's console calls happen); a page can unwrap it, which only loses logs.
(function() {
    if (window.__pacificConsoleInstalled) return;
    window.__pacificConsoleInstalled = true;
    var post = function(level, args) {
        try {
            var parts = [];
            for (var i = 0; i < args.length; i++) {
                var a = args[i];
                if (typeof a === 'string') parts.push(a);
                else { try { parts.push(JSON.stringify(a)); } catch (e) { parts.push(String(a)); } }
            }
            var stack = (new Error()).stack || '';
            var where = stack.split('\n')[2] || '';
            window.webkit.messageHandlers.pacificConsole.postMessage({ level: level, message: parts.join(' ').slice(0, 4000), source: where.trim() });
        } catch (e) {}
    };
    ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
        var original = console[level];
        console[level] = function() {
            post(level, arguments);
            return original.apply(console, arguments);
        };
    });
    window.addEventListener('error', function(e) {
        post('error', [String(e.message) + ' (' + e.filename + ':' + e.lineno + ')']);
    });
    window.addEventListener('unhandledrejection', function(e) {
        post('error', ['Unhandled rejection: ' + String(e.reason)]);
    });
})();
