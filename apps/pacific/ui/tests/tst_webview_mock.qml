// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The mock web view keeps the real module's contract (webview/README.md):
// loadingChanged(LoadRequest) with its statuses, the `loading` property
// with loadingStateChanged, history, session state, discard and the agent
// API's shapes. The UI's tests and screenshots rely on it.

import QtQuick
import QtTest
import Shipwright.Pacific.WebView 1.0

TestCase {
    id: tc
    name: "webview-mock"
    when: windowShown
    width: 400
    height: 600

    Component {
        id: viewComponent
        WebView {
            width: 400
            height: 600
        }
    }

    function test_load_reports_statuses() {
        var v = createTemporaryObject(viewComponent, tc);
        var statuses = [];
        v.loadingChanged.connect(function (r) {
            statuses.push(r.status);
        });
        var states = 0;
        v.loadingStateChanged.connect(function () {
            states++;
        });
        v.load("https://news.example/a");
        verify(v.loading);
        tryVerify(function () {
            return !v.loading;
        }, 3000);
        compare(statuses, [LoadRequest.Started, LoadRequest.Committed, LoadRequest.Succeeded]);
        verify(states >= 2);
        compare(v.loadProgress, 100);
        compare(v.title, "The harbour reopens after the storm | Example News");
        verify(v.secure);
    }

    function test_history_and_session_state() {
        var v = createTemporaryObject(viewComponent, tc);
        v.load("https://en.wikipedia.org/wiki/A");
        tryVerify(function () {
            return !v.loading;
        });
        v.load("https://news.example/b");
        tryVerify(function () {
            return !v.loading;
        });
        verify(v.canGoBack);
        v.goBack();
        tryVerify(function () {
            return !v.loading;
        });
        compare(String(v.url), "https://en.wikipedia.org/wiki/A");
        verify(v.canGoForward);
        var state = v.sessionState();
        var w = createTemporaryObject(viewComponent, tc);
        verify(w.restoreSessionState(state));
        compare(String(w.url), "https://en.wikipedia.org/wiki/A");
    }

    function test_discard_and_agent() {
        var v = createTemporaryObject(viewComponent, tc);
        v.load("https://shop.example/checkout");
        tryVerify(function () {
            return !v.loading;
        });
        var snap = null;
        v.agentSnapshot({}, function (r) {
            snap = r;
        });
        verify(snap.elements.length > 3);
        compare(snap.forms[0].id, "e30");
        var clicked = null;
        v.agentClick("e2", function (r) {
            clicked = r;
        });
        verify(clicked.ok);
        var terminated = -1;
        v.webProcessTerminated.connect(function (reason) {
            terminated = reason;
        });
        v.load("https://news.example/2026/10/04/harbour");
        tryVerify(function () {
            return !v.loading;
        });
        var saved = v.sessionState();
        v.discard();
        verify(!v.webProcessRunning);
        compare(terminated, WebView.TerminatedByApi);
        // As the real view: the page is gone with the process.
        compare(String(v.url), "");
        compare(v.title, "");
        // Woken from the saved state: the page and its history are back.
        verify(v.restoreSessionState(saved));
        v.reload();
        verify(v.webProcessRunning);
        tryVerify(function () {
            return !v.loading;
        });
        compare(String(v.url), "https://news.example/2026/10/04/harbour");
        verify(v.title.indexOf("harbour") >= 0);
        verify(v.canGoBack);
        v.goBack();
        tryVerify(function () {
            return !v.loading;
        });
        compare(String(v.url), "https://shop.example/checkout");
    }

    Component {
        id: profileComponent
        WebProfile {}
    }

    // The filter store as the engine keeps it: a compiled filter loads in a
    // later run; one the store lost (a run killed mid-compile) fails to
    // load; requests are blocked only with a filter in force.
    function test_filters_and_blocking() {
        var p = createTemporaryObject(profileComponent, tc);
        var loaded = null;
        p.loadContentFilter("pacific-easylist-1", function (ok) {
            loaded = ok;
        });
        compare(loaded, false, "never compiled: the load fails");
        var compiled = null;
        p.compileContentFilter("pacific-easylist-1", "[]", function (ok) {
            compiled = ok;
        });
        verify(compiled);
        compare(p.contentFilters, ["pacific-easylist-1"]);
        var v = createTemporaryObject(viewComponent, tc, {
            profile: p
        });
        v.load("https://news.example/2026/10/04/harbour");
        tryVerify(function () {
            return !v.loading;
        });
        verify(v.blockedRequestCount > 0);
        // Blocking off: nothing is blocked, and the filter stays stored.
        p.disableContentFilter("pacific-easylist-1");
        compare(p.contentFilters, []);
        v.reload();
        tryVerify(function () {
            return !v.loading;
        });
        compare(v.blockedRequestCount, 0);
        p.enableContentFilter("pacific-easylist-1", function (ok) {
            loaded = ok;
        });
        compare(loaded, true, "enabled again from the store");
        // Removing deletes it from the store (as a lost store does).
        p.removeContentFilter("pacific-easylist-1");
        p.enableContentFilter("pacific-easylist-1", function (ok) {
            loaded = ok;
        });
        compare(loaded, false);
    }

    function test_find() {
        var v = createTemporaryObject(viewComponent, tc);
        v.load("https://news.example/a");
        tryVerify(function () {
            return !v.loading;
        });
        var count = -1;
        v.findResult.connect(function (n) {
            count = n;
        });
        v.findText("harbour", false);
        compare(count, 3);
        compare(v.findMatchCount, 3);
        v.stopFind();
        compare(v.findMatchCount, 0);
    }
}
