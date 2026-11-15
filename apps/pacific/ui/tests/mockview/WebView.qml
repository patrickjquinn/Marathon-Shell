// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Mock of Shipwright.Pacific.WebView's WebView (shoal/pacific/webview,
// README "QML API"): the same properties, methods and signals, with pages
// drawn from a small set of fixtures instead of loaded. Loads take 600 ms
// and report progress; history, find, thumbnails, discard, session state
// and the agent API behave plausibly. For the UI's tests, qmllint and the
// screenshots.

import QtQuick

MockWebViewBase {
    id: view
    // Its page stands in for web content (tools/screenshots audits only
    // Pacific's own UI around it).
    objectName: "mockWebView"

    enum InputMode { NativeInput, ScriptInput }
    enum InputPurpose { FreeForm, Digits, Number, Phone, Url, Email, Password, Search }
    enum TerminationReason { Crashed, ExceededMemoryLimit, TerminatedByApi }
    enum InjectionTime { DocumentStart, DocumentEnd }
    enum EditingCommand { Cut, Copy, Paste, PasteAsPlainText, SelectAll, Undo, Redo }

    // The real view's read-only state, driven by the mock's own.
    title: _page.title || ""
    icon: _page.icon || ""
    themeColor: _page.theme || ""
    loadProgress: _progress
    loading: _loading
    canGoBack: _index > 0
    canGoForward: _index < _history.length - 1
    historyKey: _index >= 0 ? "h" + _index : ""
    swipeNavigation: true
    // The real view's swipeFrame: what swipes are measured in.
    property Item swipeFrame: null
    secure: String(url).indexOf("https:") === 0
    audioPlaying: _page.audio === true && webProcessRunning
    webProcessRunning: _running
    selectedText: _selection
    findMatchCount: _findCount
    profile: WebEngine.defaultProfile

    // Mock state and a record of calls, for tests.
    property var calls: []
    property var userScripts: []
    property var userStyleSheets: []
    property var _history: []
    property int _index: -1
    property int _progress: 0
    property bool _loading: false
    property bool _running: true
    property int _findCount: 0
    property string _selection: ""
    property var _page: ({})
    property var _settings: ({})


    function _record(name, args) {
        var c = calls.slice()
        c.push({ name: name, args: args })
        calls = c
    }

    // ---- Fixtures ---------------------------------------------------------

    readonly property var _fixtures: ({
        "en.wikipedia.org": { title: "Sailfish OS - Wikipedia", theme: "#ffffff", icon: "https://en.wikipedia.org/static/apple-touch/wikipedia.png",
            heading: "Sailfish OS", lines: 14, links: ["Jolla", "Linux", "Qt", "Mer"] },
        "news.example": { title: "The harbour reopens after the storm | Example News", theme: "#0b3d63", icon: "https://news.example/apple-touch-icon.png",
            heading: "The harbour reopens after the storm", lines: 18, links: ["World", "Local", "Weather"], ad: true },
        "shop.example": { title: "Checkout - Example Shop", heading: "Checkout", lines: 6, links: ["Basket"], form: true },
        "radio.example": { title: "Harbour Radio - live", heading: "Live now", lines: 4, links: [], audio: true },
        "duckduckgo.com": { title: "DuckDuckGo", icon: "https://duckduckgo.com/assets/icons/meta/DDG-iOS-icon_152x152.png", heading: "Search results", lines: 10, links: ["Sailfish OS", "Jolla", "Pacific"] }
    })

    function _host(u) {
        var m = /^[a-z][a-z0-9+.-]*:\/\/([^/:?#]+)/i.exec(String(u))
        return m ? m[1].toLowerCase().replace(/^www\./, "") : ""
    }

    function _pageFor(u) {
        var s = String(u)
        if (s.indexOf("file://") === 0 && s.indexOf("/reader/") > 0)
            return { title: "The harbour reopens after the storm", heading: "The harbour reopens after the storm", lines: 16, links: [], reader: true }
        var h = _host(s)
        var f = _fixtures[h]
        if (f)
            return f
        if (!h)
            return { title: s === "about:blank" ? "" : s, heading: "", lines: 0, links: [] }
        return { title: h, heading: h, lines: 10, links: ["About", "Contact"] }
    }

    // ---- Navigation -------------------------------------------------------

    function _start(u, keepHistory) {
        _record("load", [String(u)])
        if (!keepHistory) {
            var h = _history.slice(0, _index + 1)
            h.push(String(u))
            _history = h
            _index = h.length - 1
        }
        url = u
        _page = _pageFor(u)
        blockedRequestCount = 0
        _running = true
        _progress = 10
        _loading = true
        loadingChanged(_req.createObject(view, { url: u, status: LoadRequest.Started }))
        _timer.restart()
    }

    // Tests and screenshots: a load stops making progress here (-1: never).
    property int holdAt: -1

    property bool _settingUrl: false
    onUrlChanged: {
        if (!_settingUrl && String(url) !== (_index >= 0 ? _history[_index] : "") && String(url) !== "")
            _start(url, false)
    }

    function load(u) {
        _settingUrl = true
        _start(u, false)
        _settingUrl = false
    }
    function loadHtml(html, baseUrl) { _record("loadHtml", [String(baseUrl)]); load(baseUrl || "about:blank") }
    function goBack() { if (canGoBack) { _index--; _settingUrl = true; _start(_history[_index], true); _settingUrl = false } }
    // The real view's historyItemAt(): {key, url, title} `offset` entries away.
    function historyItemAt(offset) {
        var i = _index + offset
        return i >= 0 && i < _history.length && offset !== 0 ? { key: "h" + i, url: _history[i], title: "" } : ({})
    }
    // The real view keeps a picture per history entry; the mock records the call.
    function captureHistoryPicture() { _record("captureHistoryPicture", [historyKey]) }
    function hasHistoryPicture(key) { return false }
    function goForward() { if (canGoForward) { _index++; _settingUrl = true; _start(_history[_index], true); _settingUrl = false } }
    function reload() { _record("reload", []); if (_index >= 0) { _settingUrl = true; _start(_history[_index], true); _settingUrl = false } }
    function reloadBypassCache() { reload() }
    function stop() {
        _timer.stop()
        if (_loading) {
            _loading = false
            loadingChanged(_req.createObject(view, { url: url, status: LoadRequest.Stopped }))
        }
    }

    Component { id: _req; LoadRequest {} }

    Timer {
        id: _timer
        interval: 60
        repeat: true
        onTriggered: {
            if (view.holdAt >= 0 && view._progress >= view.holdAt)
                return // held mid-load for a screenshot
            view._progress = Math.min(100, view._progress + 30)
            // Ad and tracker requests the content filters stop.
            if (view._page.ad === true && view._progress <= 70 && view.profile && view.profile.contentFilters.length > 0) {
                view.blockedRequestCount++
                view.blockedRequest("https://ads.tracker.example/slot" + view._progress + ".js")
            }
            if (view._progress === 40)
                view.loadingChanged(_req.createObject(view, { url: view.url, status: LoadRequest.Committed }))
            if (view._progress >= 100) {
                stop()
                view._loading = false
                view.loadingChanged(_req.createObject(view, { url: view.url, status: LoadRequest.Succeeded }))
                view.scrollChanged(0, page.height, view.height)
            }
        }
    }

    // ---- Scripts ----------------------------------------------------------

    function _answer(script) {
        var s = String(script)
        if (s.indexOf("outerHTML") >= 0)
            return _html()
        if (s.indexOf("input[type=password]") >= 0)
            return JSON.stringify({ login: _page.form === true, username: _page.form === true })
        if (s.indexOf("querySelectorAll('p')") >= 0)
            return (_page.lines || 0) > 8 ? 3000 : 200
        if (s.indexOf("getSelection") >= 0)
            return _selection
        return null
    }
    function runJavaScript(script, callback) { _record("runJavaScript", [String(script).slice(0, 80)]); if (callback) callback(_answer(script), null) }
    function runJavaScriptInWorld(script, world, callback) { _record("runJavaScriptInWorld", [String(script).slice(0, 80), world]); if (callback) callback(_answer(script), null) }

    function _html() {
        var p = "<p>The fishing boats returned to the inner harbour on Saturday morning, three days after the storm closed the port and pushed a line of broken ice against the breakwater. Ferries will run on a reduced timetable until Monday.</p>"
        var body = ""
        for (var i = 0; i < 12; ++i)
            body += p
        return "<html lang=\"en\"><head><title>" + title + "</title><meta name=\"author\" content=\"Aino Virtanen\"></head><body><nav>Home World</nav><article><h1>" + (_page.heading || title) + "</h1>" + body + "</article><footer>Example</footer></body></html>"
    }

    // ---- Find -------------------------------------------------------------

    function findText(text, caseSensitive) {
        _record("findText", [text])
        _findCount = text.length > 0 ? 3 : 0
        findResult(_findCount)
    }
    function findNext() { _record("findNext", []) }
    function findPrevious() { _record("findPrevious", []) }
    function stopFind() { _findCount = 0; _record("stopFind", []) }

    // ---- Editing and pickers ----------------------------------------------

    function executeEditingCommand(command) { _record("executeEditingCommand", [command]) }
    function insertText(text) { _record("insertText", [text]) }
    function copySelection() { _record("copySelection", []) }
    function clearSelection() { _selection = "" }
    function selectMenuOption(index) { _record("selectMenuOption", [index]) }
    function closeSelectMenu() { _record("closeSelectMenu", []) }
    function resolveInputPicker(value) { _record("resolveInputPicker", [value]) }
    function cancelInputPicker() { _record("cancelInputPicker", []) }
    function applySpellingSuggestion(index) { _record("applySpellingSuggestion", [index]) }
    function learnSpelling() { _record("learnSpelling", []) }
    function ignoreSpelling() { _record("ignoreSpelling", []); return true }

    // ---- Tab lifecycle ----------------------------------------------------

    // As the real view: letting the web process go loses the page (the
    // address and title go blank); sessionState() taken before brings it
    // back.
    function discard() {
        _record("discard", [])
        _running = false
        _timer.stop()
        _loading = false
        webProcessTerminated(WebView.TerminatedByApi)
        _history = []
        _index = -1
        _settingUrl = true
        url = ""
        _page = _pageFor("")
        _settingUrl = false
    }
    function sessionState() { return encodeURIComponent(JSON.stringify({ history: _history, index: _index })) }
    function restoreSessionState(b64) {
        try {
            var s = JSON.parse(decodeURIComponent(b64))
            _history = s.history
            _index = s.index
            _settingUrl = true
            url = _history[_index]
            _page = _pageFor(url)
            _settingUrl = false
            return true
        } catch (e) {
            return false
        }
    }
    function saveThumbnail(path, maxWidth, maxHeight, callback) {
        _record("saveThumbnail", [path])
        var ok = page.grabToImage(function(result) {
            var saved = result.saveToFile(path)
            if (callback)
                callback(saved, path)
        }, Qt.size(Math.min(maxWidth, Math.max(1, page.width)), Math.min(maxHeight, Math.max(1, view.height))))
        if (!ok && callback)
            callback(false, path)
    }

    // ---- Settings and user content ----------------------------------------

    function setSetting(name, value) { var s = _settings; s[name] = value; _settings = s }
    function setting(name) { return _settings[name] }
    function setFeatureEnabled(identifier, on) { setSetting(identifier, on); return true }
    property int _nextUserScript: 1
    function addUserScript(source, world, time, allFrames, skipHosts) {
        var handle = _nextUserScript++
        var u = userScripts.slice()
        u.push({ handle: handle, length: String(source).length, world: world || "", time: time, skipHosts: skipHosts || [] })
        userScripts = u
        return handle
    }
    function removeUserScript(handle) { userScripts = userScripts.filter(function(s) { return s.handle !== handle }) }
    function addUserStyleSheet(css, allFrames) { var u = userStyleSheets.slice(); u.push(String(css)); userStyleSheets = u }
    function removeUserContent() { userScripts = []; userStyleSheets = [] }
    function registerScriptMessageHandler(name, world) { _record("registerScriptMessageHandler", [name, world || ""]); return true }

    // ---- Agent ------------------------------------------------------------

    function agentSnapshot(options, callback) {
        _record("agentSnapshot", [])
        var els = [{ id: "e1", tag: "a", role: "link", label: "Home", visible: true, inViewport: true, box: [16, 40, 60, 20], href: "https://" + _host(url) + "/" }]
        var links = _page.links || []
        for (var i = 0; i < links.length; ++i)
            els.push({ id: "e" + (i + 2), tag: "a", role: "link", label: links[i], visible: true, inViewport: true, box: [16, 80 + i * 30, 120, 20], href: "https://" + _host(url) + "/" + links[i].toLowerCase() })
        var forms = []
        if (_page.form) {
            els.push({ id: "e20", tag: "input", role: "textbox", label: "Email", visible: true, inViewport: true, type: "email", name: "email", value: "", form: "e30" })
            els.push({ id: "e21", tag: "input", role: "textbox", label: "Card number", visible: true, inViewport: true, type: "text", name: "cardnumber", autocomplete: "cc-number", value: "", form: "e30" })
            els.push({ id: "e22", tag: "button", role: "button", label: "Pay now", visible: true, inViewport: true, form: "e30" })
            forms.push({ id: "e30", action: "https://shop.example/pay", method: "post", name: "", label: "" })
        }
        var r = { url: String(url), title: title, lang: "en",
                  viewport: { width: width, height: height, scrollX: 0, scrollY: 0, scrollHeight: page.height },
                  elements: els, forms: forms, frames: [], total: els.length, truncated: false }
        if (options && options.text)
            r.text = _text(4000)
        callback(r, null)
    }
    function agentClick(id, callback) { _record("agentClick", [id]); if (callback) callback({ ok: true, method: "tap", covered: false }) }
    function agentFocus(id, callback) { _record("agentFocus", [id]); if (callback) callback({ ok: true, focused: true }) }
    function agentSetValue(id, value, callback) { _record("agentSetValue", [id, value]); if (callback) callback({ ok: true, value: value }) }
    function agentType(id, text, callback) { _record("agentType", [id, text]); if (callback) callback({ ok: true }) }
    function agentSubmit(id, callback) { _record("agentSubmit", [id]); if (callback) callback({ ok: true, form: "e30" }) }
    function agentScroll(dx, dy, callback) { flick.contentY = Math.max(0, flick.contentY + dy); if (callback) callback({ ok: true, scrollX: 0, scrollY: flick.contentY }) }
    function _text(max) {
        var t = (_page.heading || title) + "\n\nThe fishing boats returned to the inner harbour on Saturday morning."
        return t.slice(0, max)
    }
    function pageText(maxChars, callback) { callback(_text(maxChars), null) }
    function pageHtml(maxChars, callback) { callback(_html().slice(0, maxChars), null) }
    function readerContent(callback) {
        callback({ url: String(url), title: title, byline: "Aino Virtanen", siteName: _host(url), excerpt: "", lang: "en", html: _html(), text: _text(4000) }, null)
    }

    // Test helpers: what the real view's engine would do.
    function mockConsole(message) { consoleMessage("log", message, String(url)) }
    function mockCrash() { _running = false; webProcessTerminated(WebView.Crashed) }
    function mockSelect(text) { _selection = text }

    // ---- Drawing ----------------------------------------------------------

    clip: true

    Flickable {
        id: flick
        anchors.fill: parent
        visible: !view.headless && view.webProcessRunning
        contentWidth: width
        contentHeight: page.height
        onContentYChanged: view.scrollChanged(contentY, contentHeight, height)

        Rectangle {
            id: page
            width: flick.width
            height: Math.max(flick.height, column.height + 64 * view.zoomFactor)
            color: view._page.reader ? "#f4ecd8" : "#ffffff"

            Column {
                id: column
                x: 24 * view.zoomFactor
                y: 24 * view.zoomFactor
                width: page.width - 2 * x
                spacing: 12 * view.zoomFactor

                Rectangle {
                    visible: !view._page.reader && String(view.url) !== "about:blank"
                    width: parent.width
                    height: 44 * view.zoomFactor
                    color: view._page.theme || "#eeeeee"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        text: view._host(view.url)
                        color: view._page.theme && view._page.theme !== "#ffffff" ? "#ffffff" : "#333333"
                        font.pixelSize: 18 * view.zoomFactor
                        font.bold: true
                    }
                }
                Text {
                    width: parent.width
                    text: view._page.heading || ""
                    wrapMode: Text.Wrap
                    color: "#1b1b1b"
                    font.pixelSize: 30 * view.zoomFactor
                    font.bold: true
                    visible: text.length > 0
                }
                Text {
                    width: parent.width
                    visible: view._page.reader === true
                    text: "Aino Virtanen · Example News · 4 min read"
                    color: "#6b5b45"
                    font.pixelSize: 16 * view.zoomFactor
                }
                Rectangle {
                    visible: view._page.ad === true
                    width: parent.width
                    height: 90 * view.zoomFactor
                    color: "#f2c94c"
                    Text { anchors.centerIn: parent; text: "ADVERTISEMENT"; color: "#7a5c00"; font.pixelSize: 16 }
                }
                Repeater {
                    model: view._page.lines || 0
                    Rectangle {
                        width: column.width * (index % 4 === 3 ? 0.6 : 1.0)
                        height: 14 * view.zoomFactor
                        radius: 3
                        color: view._page.reader ? "#c8b996" : "#d6d6d6"
                    }
                }
                Repeater {
                    model: view._page.links || []
                    Text {
                        text: modelData
                        color: "#0b57d0"
                        font.underline: true
                        font.pixelSize: 18 * view.zoomFactor
                    }
                }
                Column {
                    visible: view._page.form === true
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: ["Email", "Card number"]
                        Rectangle {
                            width: column.width
                            height: 48
                            border.color: "#999999"
                            color: "#ffffff"
                            Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: "#777777"; font.pixelSize: 16 }
                        }
                    }
                    Rectangle {
                        width: 160
                        height: 48
                        radius: 6
                        color: "#1a7f37"
                        Text { anchors.centerIn: parent; text: "Pay now"; color: "#ffffff"; font.pixelSize: 18 }
                    }
                }
            }
        }
    }
}
