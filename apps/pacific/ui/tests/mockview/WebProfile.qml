// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Mock of the web view's WebProfile.
import QtQuick

QtObject {
    id: profile
    enum CookiePolicy { AcceptAll, AcceptNone, NoThirdParty }
    enum DataType { Cookies = 1, Cache = 2, LocalStorage = 4, IndexedDb = 8, ServiceWorkers = 16, AllData = 65535 }
    property bool ephemeral: false
    property string dataDirectory
    property string cacheDirectory
    property string downloadDirectory
    property bool trackingPrevention: true
    property int cookiePolicy: WebProfile.NoThirdParty
    property bool ignoreTlsErrors: false
    property bool globalPrivacyControl: true
    property bool spellChecking: true
    property var spellCheckingLanguages: ["en_GB"]
    property bool created: true
    property var contentFilters: []
    // Calls made, for tests.
    property var calls: []
    signal downloadStarted(var download)
    signal contentFilterAdded(string identifier)
    signal contentFilterRemoved(string identifier)

    function _record(name, args) { var c = calls.slice(); c.push({ name: name, args: args }); calls = c }
    function clearData(types, sinceSeconds, callback) { _record("clearData", [types, sinceSeconds]); if (callback) callback(true) }
    function prefetchDns(host) { _record("prefetchDns", [host]) }
    function download(url) { _record("download", [url]) }
    function allowCertificate(host, pem) { _record("allowCertificate", [host]) }
    // The engine's filter store (kept across runs on the phone; a test can
    // empty it to act out a run killed before a compile finished).
    property var store: []
    function compileContentFilter(id, json, callback) {
        _record("compileContentFilter", [id, json.length])
        if (store.indexOf(id) < 0) { var st = store.slice(); st.push(id); store = st }
        if (contentFilters.indexOf(id) < 0) { var f = contentFilters.slice(); f.push(id); contentFilters = f }
        contentFilterAdded(id)
        if (callback) callback(true, "")
    }
    function loadContentFilter(id, callback) {
        _record("loadContentFilter", [id])
        if (store.indexOf(id) < 0) {
            if (callback) callback(false, "no filter " + id + " in the store")
            return
        }
        if (contentFilters.indexOf(id) < 0) { var f = contentFilters.slice(); f.push(id); contentFilters = f }
        contentFilterAdded(id)
        if (callback) callback(true, "")
    }
    // As the engine: enable applies a filter from the store (false when
    // the store lacks it); disable stops applying it and keeps it stored.
    function enableContentFilter(id, callback) {
        _record("enableContentFilter", [id])
        loadContentFilter(id, callback)
    }
    function disableContentFilter(id) {
        _record("disableContentFilter", [id])
        contentFilters = contentFilters.filter(function(x) { return x !== id })
        contentFilterRemoved(id)
    }
    // Unloads and deletes from the store.
    function removeContentFilter(id) {
        _record("removeContentFilter", [id])
        contentFilters = contentFilters.filter(function(x) { return x !== id })
        store = store.filter(function(x) { return x !== id })
        contentFilterRemoved(id)
    }
}
