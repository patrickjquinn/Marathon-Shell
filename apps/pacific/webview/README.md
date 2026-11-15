<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: LGPL-2.1-or-later
-->

# Shipwright.Pacific.WebView

`import Shipwright.Pacific.WebView 1.0` puts WPE WebKit pages into a Qt 6 Quick scene. It is a Qt 6 port of [Atlantic](https://github.com/SpecSierra/atlantic-engine)'s `qt5-plugin`, which itself derives from Igalia's WPE Qt API, plus what a full browser and Pilot need.

This module is the engine half of Pacific. The browser UI (`../ui`) and the Rust core (`../core`, `../app`) are built on top of it. The engine packages are in `../engine`.

## How frames get to the screen

The view uses the legacy libwpe + WPEBackend-fdo path (WebKit's `ENABLE_WPE_LEGACY_API`). WebKit's own Qt 6 API needs WPEPlatform, which can't work on libhybris yet; the validation report explains why.

1. The WebProcess renders into a `wl_egl_window` on WPEBackend-fdo's private Wayland server, which is hosted in the app.
2. Each finished frame arrives as an EGLImage:
   - On the phone it comes through `EGL_WL_bind_wayland_display`, which libhybris maps to an Android native buffer.
   - On a desktop it comes through linux-dmabuf. Mesa no longer has the bind extension.
3. `glEGLImageTargetTexture2DOES` makes the image the storage of a GL texture in Qt's scene-graph context. `QNativeInterface::QSGOpenGLTexture::fromNative` wraps that texture in a node.

There is no CPU copy. There are two GPU composites: Qt's, then Lipstick's.

When the WebProcess renders with software GL (Mesa's llvmpipe, or a phone whose GPU path fails), it commits `wl_shm` buffers instead. The view copies each one out of the buffer, hands the buffer back, and lets Qt upload the copy as a texture. This is slower but correct, and it is what keeps the CPU fallback working. Before this, WPEBackend-fdo's shm callback was left null and the app crashed inside the Wayland dispatch.

**Qt Quick must use the OpenGL (ES) RHI.** Call this before the first window exists:

```cpp
QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
```

Alternatively, `pacific-env.sh` sets `QSG_RHI_BACKEND=opengl`. The view warns if it finds another backend.

## QML API

### WebView

Properties:

| Property | Type | Notes |
|---|---|---|
| `url` | url | Read and write. Assigning the shown URL again reloads nothing; assigning one that was navigated away from loads it. |
| `title` | string | Read-only. |
| `icon` | url | Read-only. The best favicon the page declares: apple-touch-icon and sized icons first, `/favicon.ico` as a fallback. |
| `themeColor` | string | Read-only. The page's `meta theme-color`. |
| `loadProgress` | int | Read-only, 0 to 100. |
| `loading` | bool | Read-only. |
| `canGoBack`, `canGoForward` | bool | Read-only. Also updated on `pushState` navigations. |
| `historyKey` | string | Read-only. The session history entry on screen, as a key that stays the same for that entry while it is in the list. `historyItemAt()` gives the others' keys. |
| `swipeNavigation` | bool | Read and write, default true. Swipe back and forward (`swipeNavMoved`, below). |
| `secure` | bool | Read-only. https with a valid certificate and no mixed content. |
| `audioPlaying` | bool | Read-only. |
| `muted` | bool | Read and write. |
| `webProcessRunning` | bool | Read-only. False after a crash or `discard()`. `reload()` restarts the process. |
| `created` | bool | Read-only. The WebKit view exists: it is created at `componentComplete`, so it can be off-screen. |
| `profile` | WebProfile | Read and write. Set it **before** creation. The default is `WebEngine.defaultProfile`. For private tabs use `WebEngine.privateProfile` or an ephemeral `WebProfile`. |
| `userAgent` | string | Read and write. Empty means Pacific's mobile UA (Chrome on Android), or the desktop UA (Chrome's desktop-site UA) when `desktopMode` is on. |
| `desktopMode` | bool | Read and write. Switches to the desktop UA. Call `reload()` afterwards. |
| `zoomFactor` | real | Read and write. User zoom (page zoom), 0.25 to 5. |
| `contentScale` | real | Read and write. CSS px to device px. It is WebKit's real device scale factor, which keeps text sharp. By default: on Sailfish OS (Qt at pixel ratio 1) it comes from the screen's DPI (dpi/160, in quarter steps); with Qt's high-DPI scaling (desktops) it is the device pixel ratio, so the page is as wide in CSS px as the item is in Qt px. `PACIFIC_SCALE_MODE=zoom` falls back to page zoom. |
| `active` | bool | Read and write. Whether this is the foreground tab: bind it to "this tab is current" and nothing else. False makes the page `visibilityState=hidden`: requestAnimationFrame stops and timers are throttled. The view itself takes care of the rest (see "Page visibility" below). |
| `pageVisible` | bool | Read-only. What the page is told: `document.visibilityState` is `"visible"` exactly when this is true. |
| `headless` | bool | Read and write. No rendering into Qt. Frames are acknowledged and dropped at 10 fps. For Pilot's background tabs. |
| `inputMode` | enum | Read and write. `WebView.NativeInput` (the default) is WebKit's input-method context. `WebView.ScriptInput` is Atlantic's script text entry, for the day-1 comparison. |
| `scriptSelectMenus` | bool | Read and write. Use the script `<select>` bridge instead of WebKit's native option menu. This is a fallback. |
| `captureConsole` | bool | Read and write. Turns on `consoleMessage`, for developer tools and tests. Off by default: the page's console is then its own (not wrapped) and nothing is forwarded. Turning it off takes the capture out from the next page. For a page script's own reports, use `registerScriptMessageHandler` with the page's world (`""`). |
| `javascriptEnabled`, `loadImages`, `mediaNeedsUserGesture` | bool | Read and write. |
| `editableFocused` | bool | Read-only. An editable field has focus. |
| `cursorRectangle` | rect | Read-only. The caret, in item coordinates. |
| `inputPurpose` | enum | Read-only. `FreeForm`, `Digits`, `Number`, `Phone`, `Url`, `Email`, `Password` or `Search`. |
| `selectedText` | string | Read-only. |
| `findMatchCount` | int | Read-only. |
| `blockedRequestCount` | int | Read-only. Requests the profile's content filters blocked on the current page; reset to 0 when a new page starts loading. |

Methods:

- **Navigation:** `load(url)`, `loadHtml(html, baseUrl)`, `goBack()`, `goForward()`, `reload()`, `reloadBypassCache()`, `stop()`.
  - `goBack()` and `goForward()` step through history strictly, one entry at a time. `PACIFIC_STRICT_HISTORY_NAV=0` restores WebKit's skipping.
  - `historyItemAt(offset)`: the entry `offset` steps from the one on screen (-1 back, 1 forward) as `{key, url, title}`, or `{}`.
  - `captureHistoryPicture()`: WebKit's snapshot of the page as it is on screen, at half resolution, kept in memory under `historyKey` (the 16 most recently used, shared by every view in the process). QML shows it as `image://pacifichistory/<key>`; `hasHistoryPicture(key)` says whether there is one, and `historyPictureReady(key)` comes when a capture is done. The UI takes one as each page is left and when scrolling stops, for the swipe back and forward to show.
- **Scripts:**
  - `runJavaScript(script, function(result, error))`: page world.
  - `runJavaScriptInWorld(script, world, callback)`: isolated world. The page cannot see or tamper with it. Pacific's own world is `"pacific"`.
  - Results are converted through JSON: objects, arrays, strings, numbers, bools and null.
- **Find:** `findText(text, caseSensitive)`, `findNext()`, `findPrevious()`, `stopFind()`.
- **Editing:**
  - `executeEditingCommand(WebView.Cut | Copy | Paste | PasteAsPlainText | SelectAll | Undo | Redo)`. Paste inserts the system clipboard as typed text.
  - `insertText(text)`: trusted editing at the caret.
  - `copySelection()`, `clearSelection()`.
- **Pickers:** `selectMenuOption(index)`, `closeSelectMenu()`, `resolveInputPicker(value)`, `cancelInputPicker()`.
- **Spelling:** see "Spell checking" below. `contextMenuAt(cssX, cssY)` opens WebKit's context menu at a point, as a long press does; `applySpellingSuggestion(index)`, `learnSpelling()`, `ignoreSpelling()` answer it.
- **Tab lifecycle:**
  - `discard()`: ends the WebProcess to free its memory. The URL and history stay, and `reload()` brings the page back.
  - `sessionState()`: returns base64 of WebKit's session state (back/forward list).
  - `restoreSessionState(base64)`.
  - `saveThumbnail(path, maxWidth, maxHeight, function(ok, path))`: WebKit's own snapshot of the visible area. It works for off-screen and headless views.
- **Settings:**
  - `setSetting(name, value)` and `setting(name)`: any `WebKitSettings` property, by its GObject name, e.g. `"enable-javascript"`.
  - `setFeatureEnabled(identifier, on)`: WebKit runtime features, e.g. `"HiddenPageDOMTimerThrottling"`.
- **User content:**
  - `addUserScript(source, world, WebView.DocumentStart | DocumentEnd, allFrames, skipHosts)`: returns a handle; `skipHosts` lists sites (with their subdomains) the script stays out of.
  - `removeUserScript(handle)`.
  - `addUserStyleSheet(css, allFrames)`.
  - `removeUserContent()`: Pacific's bridges stay.
  - `registerScriptMessageHandler(name, world)`: `window.webkit.messageHandlers.<name>.postMessage(x)` then arrives as `scriptMessage(name, x)`. The name cannot start with `pacific`. `world` `""` is the page's own world, where the page can post too; the handler is there in every frame.
- **Agent:** see below.

Signals. Request objects must be answered; an unanswered permission request leaves the page waiting.

- **Loading:**
  - `loadingChanged(LoadRequest request)`. `request.status` is `LoadRequest.Started`, `Redirected`, `Committed`, `Succeeded`, `Failed` or `Stopped`. The request also carries `url`, `errorString`, `errorCode` and `errorDomain`.
  - `urlChanged`, `titleChanged`, `iconChanged`, `loadProgressChanged`, `loadingStateChanged`, `backForwardChanged`, `securityChanged`.
- `certificateError(url, host, errors, certificatePem)`: the load stops. To go ahead, call `profile.allowCertificate(host, certificatePem)` and then `reload()`.
- `newWindowRequested(NewWindowRequest request)`: `window.open` or `target=_blank`.
  - The request carries `url`, `userInitiated` and `frameName`.
  - To open the page, create a `WebView` **inside the handler** and call `request.openIn(view)`. The new view shares the process and session, so `window.opener` works.
  - Not answering blocks the popup. You can still `load(request.url)` in a new tab.
- `navigationRequested(NavigationRequest request)`: synchronous, for every navigation action, subframes included (WPE's API cannot tell them apart).
  - The request carries `url`, `navigationType`, `userInitiated` and `redirect`.
  - Answer with `accept()` (the default), `ignore()` or `download()`.
- `closeRequested()`: the page called `window.close()`.
- `permissionRequested(PermissionRequest request)`. Device enumeration is allowed automatically.
  - `request.kind` is one of: `PermissionRequest.Geolocation`, `Camera`, `Microphone`, `CameraAndMicrophone`, `ScreenCapture`, `Notifications`, `DeviceInfo`, `WebsiteDataAccess`, `PointerLock`, `MediaKeySystem`, `ClipboardRead` or `Other`.
  - The request also carries `origin`. Answer with `allow()` or `deny()`.
- `downloadRequested(Download download)`: a download from this view. It also arrives as `WebProfile.downloadStarted`.
- `scriptDialogRequested(ScriptDialog dialog)`: alert, confirm, prompt or beforeunload.
  - The dialog has `type`, `message` and `defaultText`. Answer with `accept(text)` or `reject()`.
  - Without a handler, WebKit's default applies.
- `fileChooserRequested(FileChooserRequest request)`: `<input type=file>`. The request has `mimeTypes`, `multiple` and `selectedFiles`. Answer with `select([paths or file URLs])` or `cancel()`.
- `authenticationRequested(AuthenticationRequest request)`: HTTP authentication. The request has `host`, `port`, `realm`, `proxy` and `retry`. Answer with `authenticate(user, password, remember)` or `cancel()`.
- `notificationRequested(title, body, tag, origin)`: post it with Nemo Notifications.
- `fullscreenRequested(bool)`: the page entered or left DOM fullscreen. Switch the window state.
- `webProcessTerminated(reason)`: `WebView.Crashed`, `ExceededMemoryLimit` or `TerminatedByApi`. Show a sad-tab page and offer `reload()`.
- `webProcessUnresponsive(bool)`.
- `inputMethodStateChanged()`: see "Keyboard" below.
- **Selection and context menu:**
  - `selectionChanged()`.
  - `selectionHandlesChanged(point start, point end)`: item coordinates.
  - `contextMenuRequested(info)`: a long press. `info` has `linkUrl`, `imageUrl`, `mediaUrl`, `selectionText`, `editable`, `pageUrl` and `x`, `y`. On a misspelt word it also has `misspelled: true` and `spellingSuggestions: [...]`.
- **Pickers:**
  - `selectMenuRequested(options, selectedIndex, rect)`. Each option is `{label, enabled, groupLabel, groupChild}`. Answer with `selectMenuOption(i)` or `closeSelectMenu()`.
  - `inputPickerRequested(type, value, min, max, step, rect)`: date, time, month, week, datetime-local or color. Answer with `resolveInputPicker(value)` or `cancelInputPicker()`.
- `scrollChanged(scrollY, contentHeight, viewportHeight)`: item px, at most every 100 ms. Drives the collapsing toolbar.
- `swipeNavMoved(dx)`, `swipeNavEnded(dx, velocity)`: swipe back and forward, as Chrome on Android does it (the screen's edges are Sailfish's own gestures). One finger dragging sideways, past 12 dp and at least twice as far sideways as down, where the page under the finger cannot scroll that way any further (`scroll.js` asks at touch-down: the page and every scrollable box under the finger are at that edge, nothing there claims sideways drags with `touch-action`, `overscroll-behavior-x` is `auto`, and the page does not `preventDefault()` the move) and there is history that way. From then the touch is the browser's: the page gets its end, and `dx` (item px from where the swipe began, positive right, which is back) follows the finger. `swipeNavEnded` comes once, with the finger's speed (item px per ms) as it lifted. The UI animates and calls `goBack()` or `goForward()`.
- `pinchConsumedByPage(bool)`: the page handles two-finger gestures (maps), so leave pinch to it.
- `findResult(count)`.
- `blockedRequest(url)`: a request the profile's content filters blocked (once per request; `blockedRequestCount` goes up with it). For the shield counter and per-site statistics.
- `consoleMessage(level, message, source)`: only while `captureConsole` is on.
- `scriptMessage(name, message)`.

### Page visibility

A page is visible (`pageVisible`, `document.visibilityState === "visible"`, full-rate requestAnimationFrame) when all of these hold:
- `active` is true;
- `headless` is false;
- the item is effectively visible, so not on a hidden tab delegate or a Silica page covered by another page;
- its window is shown and exposed;
- the application is on screen.

The view watches all of these itself: item visibility, reparenting, window visibility, exposure and activation, and the application state. **Do not fold `Qt.application.state` into `active`.**
- On Sailfish OS, `ApplicationInactive` means the app is minimised to its cover, and the page is hidden.
- Elsewhere (desktop, test compositors), Inactive only means unfocused and the page stays visible. A perf run on an unfocused window would otherwise see every page hidden.
- `PACIFIC_INACTIVE_HIDES=0|1` overrides this.

The newest frame is kept while a view is hidden or headless, and acknowledged on a slow clock so a hidden page cannot spin. A view created behind the front tab, or promoted from headless, draws its page the moment it is shown, even a static page that never repaints. Before this, those frames were dropped and such tabs stayed blank.

Hiding waits 200 ms, so a page transition that hides and shows the item does not stop and restart the page. Showing is immediate.

`PACIFIC_DEBUG_ACTIVITY=1` logs every decision with its inputs.

`tests/visibility.qml` checks visibility and rAF rate for:
- a tab created hidden with a static page, then shown: it must draw at once (a pixel of the window), at its own size (`innerWidth`/`innerHeight`);
- tabs created inactive in a Repeater and then switched;
- tabs discarded and woken, in front and behind;
- a headless view promoted into the window;
- a view created without a window and then parented.

`tests/visibility-silica.qml` does the same in a Keel/Silica application, including a page pushed over the browser.

### Keyboard (input method)

WebKit's `WebKitInputMethodContext` is subclassed and wired to Qt's input method. When a field gains focus, the view takes Qt focus and shows Maliit. Qt then queries the view for:

- the caret rectangle;
- the surrounding text and cursor;
- hints from the field type (email, URL, number, phone, password);
- the Enter key type (Search, Go).

Keyboard text reaches WebKit as preedit, commit and delete-surrounding, which WebKit applies as real editing, with `beforeinput`/`input` events and undo. A committed bare newline from Maliit becomes a native Enter key, which gives trusted keydown and form submission (Atlantic's finding).

**The UI must shrink the view while the keyboard is open.** For example:

```qml
height: page.height - (Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0)
```

When the view gets shorter with a field focused, it scrolls that field back into view (keyboard reflow).

### Spell checking

Spell checking is on by default. Misspelt words in text fields and editable content get WebKit's red underline. The checker is WebKit's enchant/hunspell one: enchant 2.3.3, built by `shipwright-pacific-engine` for `/opt/pacific`, with Pacific's dictionaries in `/opt/pacific/share/hunspell`. Nothing is installed in system paths.

- `WebEngine.spellChecking` (bool) and `WebEngine.spellCheckingLanguages` (a list of dictionary names such as `"en_GB"`, `"de_DE"`).
  - The default is the phone's language, matched to the closest dictionary (`de_AT` gets `de_DE`). When none fits, it is `en_GB`.
  - `WebEngine.availableSpellCheckingLanguages` lists the installed dictionaries.
- `WebProfile.spellChecking` and `WebProfile.spellCheckingLanguages` are the same settings. WebKit has one spell checker per process, so every profile shows and changes the same values.
- **Suggestions:** a long press on a misspelt word gives `contextMenuRequested(info)` with `info.misspelled` and `info.spellingSuggestions`.
  - `applySpellingSuggestion(index)` replaces the word as typed text, so the edit is undoable and the page sees `input`.
  - `learnSpelling()` adds the word to the personal dictionary in `ENCHANT_CONFIG_DIR`, in the app's data directory.
  - `ignoreSpelling()` ignores it for the session where WebKit supports that; it returns false otherwise.
- **Dictionaries:** en_US, en_GB, de_DE, fr_FR, es_ES, it_IT, sv_SE, nl_NL, pl_PL, pt_BR, pt_PT, ga_IE and fi_FI. `../engine/README.md` lists each licence.
  - Finnish (`fi_FI`) comes from Voikko through enchant's voikko provider, because no usable hunspell Finnish dictionary exists. A Finnish phone gets `fi_FI` by default.

### Content blocking reports

WebKit content filters block requests inside the WebProcess, so the UI process never hears about them: no resource-load signal, no failed load. WebKit does log each block to the page's console ("Content blocker prevented frame displaying … from loading a resource from …").

Pacific's WebProcess extension (`src/webprocess/extension.c`) watches every page's console for that message and sends the URL to the view as a user message. The view turns that into `blockedRequestCount` and `blockedRequest(url)`. The extension is installed in `/usr/lib64/shipwright-pacific-webview/web-process-extensions`; `PACIFIC_WEB_EXTENSIONS_DIR` overrides the directory.

`tests/privacy.qml`, with `tests/privacy-server.py`, checks both features against a local server:
- three blocked requests are counted and named, and the server never sees them;
- every request that does reach the server carries `Sec-GPC: 1`.

### WebProfile

A WebProfile is one `WebKitNetworkSession`. Properties:

- `ephemeral`, `dataDirectory`, `cacheDirectory`: fixed when the first view uses the profile. By default the profile is persistent, under `PACIFIC_WEB_DATA` and `PACIFIC_WEB_CACHE` when set, else `web` in the app's data and cache locations. In a Sailjail sandbox only the directories named after the organisation and application (`org.shipwright/pacific`) persist, so the app sets those two variables.
- `downloadDirectory`.
- `trackingPrevention`: on by default.
- `cookiePolicy`: `WebProfile.AcceptAll`, `AcceptNone` or `NoThirdParty` (the default).
- `ignoreTlsErrors`.
- `globalPrivacyControl`: on by default. Every view of the profile sends `Sec-GPC: 1` on every request (page, subresources, frames) and pages see `navigator.globalPrivacyControl === true`. This is WebKit's own GPC preference, applied per view; changing it takes effect on the next request.
- `created`.
- `contentFilters`: the IDs of the filters currently applied (enabled).

Methods:

- `clearData(types, sinceSeconds, function(ok))`. `types` is a combination of `WebProfile.Cookies`, `Cache`, `LocalStorage`, `IndexedDb`, `ServiceWorkers` and `AllData`.
- `prefetchDns(host)`.
- `download(url)`.
- `allowCertificate(host, pem)`.
- `compileContentFilter(id, json, function(ok, error))`: WebKit content-blocker JSON (Safari format). It is compiled once into a DFA shared by all WebProcesses, kept in the profile's filter store, and applied to every view of the profile, current and future. This is the core's EasyList-class blocking.
- `loadContentFilter(id, function(ok, error))` / `enableContentFilter(id, function(ok, error))`: applies a filter compiled earlier (this run or an earlier one) from the store, without compiling. `ok` is false when the store does not have it, so compile it again.
- `disableContentFilter(id)`: stops applying a filter on every view of the profile, including views created later. It leaves `contentFilters`. The change takes effect on the next page load, so reload a page to unblock it now. The compiled filter stays in the store. A compile or enable still running for the same id is dropped when it finishes, so turning blocking off cannot be undone by a late load.
- `disableAllContentFilters()`: disables them all (blocking off).
- `removeContentFilter(id, function(ok, error))`: deletes a filter. It disables the filter and removes the compiled filter from the store. Use it when a list is removed or replaced.
- `storedContentFilters(function(ids))`: the ids compiled in the store.

Signal: `downloadStarted(Download)`. A `Download` has `url`, `suggestedFilename` and `destination`. `destination` is writable in the handler; by default the file goes in `downloadDirectory` (or ~/Downloads) under a unique name. It also has `mimeType`, `progress`, `receivedBytes`, `totalBytes`, `state` (`Download.InProgress`, `Finished`, `Failed` or `Cancelled`), `errorString` and `cancel()`.

### WebEngine (singleton)

- `version`.
- `defaultProfile` and `privateProfile`. The private profile is ephemeral and shared by all private tabs; call `privateProfile.clearData(WebProfile.AllData)` when the last private tab closes.
- `cacheModel`: `WebEngine.DocumentViewer`, `WebBrowser` (the default) or `DocumentBrowser`.
- `preferredLanguages`, `spellCheckingLanguages`.
- Memory pressure: `memoryLimitMB`, `conservativeThreshold`, `strictThreshold`, `killThreshold`, `memoryPollInterval`. Set them before the first view exists; they are fixed when the shared context is created.
- `gpuMode`: the mode the launcher picked.

### Agent API (Pilot)

For Keel Actions and MCP: `page.read`, `page.links`, `page.click`, `page.fill`, `page.submit`, and "browse for me". The helpers run in the isolated world `"pacific"`. The page shares the DOM with them but cannot see the helpers, the element IDs or the map behind them, and cannot replace them. Every result is plain JSON with a bounded size.

- **`agentSnapshot(options, function(result, error))`**
  - Options: `{limit: 300, includeHidden: false, text: false | maxChars}`.
  - The result:
    - page fields: `{url, title, lang, viewport: {width, height, scrollX, scrollY, scrollHeight}, ...}`;
    - `elements`: links, buttons, inputs, selects, textareas, summary, contenteditable, tabindex, ARIA widget roles and `[onclick]`;
    - `forms`: `[{id, action, method, name, label}]`;
    - `frames`: cross-origin frames, which are listed but not entered;
    - `total`, `truncated`, and `text` when asked for.
  - Each element is:

    ```
    {id: "e12", tag, role, label, visible, inViewport, box: [x, y, w, h], href, name, type,
     value, checked, required, readOnly, autocomplete, options: [{value, label, selected}],
     disabled, expanded, form, editable}
    ```

  - Boxes are CSS px in the viewport.
  - IDs stay stable for an element's lifetime.
  - Open shadow roots and same-origin frames are walked.
  - Password values are masked.
  - On-screen elements come first when the list is truncated.
- **`agentClick(id, callback)`** scrolls the element into view, then dispatches a native touch tap at its centre through WebKit. The page gets trusted touch, pointer, mouse and click events, as from a finger. The result is `{ok, box, center, covered, method: "tap"}`, where `covered` means another element is on top.
- **`agentFocus(id, cb)`**.
- **`agentSetValue(id, value, cb)`** handles text, select (by value or label), checkbox, radio and contenteditable. Text goes through the prototype setter plus `input`/`change` events, which React and Vue observe.
- **`agentType(id, text, cb)`** focuses the element, then inserts the text through WebKit's editor (trusted `beforeinput`/`input`).
- **`agentSubmit(id, cb)`** calls `form.requestSubmit()` for the element's form.
- **`agentScroll(dx, dy, cb)`**.
- **`pageText(maxChars, cb)`**, **`pageHtml(maxChars, cb)`**, **`readerContent(cb)`**.
  - `readerContent` returns `{url, title, byline, siteName, excerpt, lang, html, text}`.
  - It is a quick heuristic. Full Readability is the core's job on `html`.
- **Background browsing:** use `WebView { headless: true; profile: WebEngine.privateProfile }` (or a fresh ephemeral `WebProfile`). The view needs no window or parent; `Qt.createQmlObject` or a `Component` with no parent works. It renders nothing and acknowledges frames at 10 fps.
- **Promoting a background view to a visible tab:**
  1. Set `headless: false`.
  2. Reparent the item into the tab's page and size it.
  3. Set `active: true`.

  It is the same WebKit view: page state, history and logins carry over.

## Building

The module needs Qt 6.8+ (Core, Gui and its private headers, Qml, Quick, Positioning; Sensors is optional), plus pkg-config files for the engine and EGL/GLES.

- **Phone RPMs (aarch64, Sailfish OS 5.2.0.15):**

  ```
  tools/build/native/native.sh shoal/pacific/engine/rpm/shipwright-pacific-engine.spec \
      shoal/pacific/webview/rpm/shipwright-pacific-webview.spec
  ```

  The `rpm/prebuild.sh` hooks fetch the engine RPMs and check them against `../engine/SHA256SUMS`. The build produces `shipwright-pacific-webview` and `shipwright-pacific-webview-examples` (pacific-minibrowser) in `RPMS/5.2.0.15/`.
- **Host (Fedora aarch64):**
  1. `tools/sdk-prefix.sh <prefix>` unpacks the mirrored RPMs and writes pkg-config files.
  2. Fedora has no libsoup3-devel by default. `dnf download libsoup3-devel` and point a `libsoup-3.0.pc` at its headers.
  3. Then:

     ```
     PKG_CONFIG_PATH=<prefix>/pkgconfig cmake -S shoal/pacific/webview -B build -G Ninja
     cmake --build build -j4
     ```

## Running

- **On the phone:** run everything under `/usr/libexec/pacific/pacific-env.sh`, which `../engine/README.md` explains:

  ```
  /usr/libexec/pacific/pacific-env.sh pacific-minibrowser --silica https://en.wikipedia.org
  ```

- **On the host:** copy ICU 73 from the Sailfish root into `<prefix>/icu73`, then:

  ```
  tools/host-run.sh <prefix> <build> <build>/examples/minibrowser/pacific-minibrowser \
      [--headless --snapshot | --screenshot out.png] <url>
  ```

  It uses bubblewrap to mount the engine's helpers where the engine looks for them, and uses the host's Mesa over Wayland.

  For spell checking on the host, run `tools/host-enchant.sh <prefix>` once first. It builds libvoikko and enchant into `<prefix>/enchant`, copies the dictionaries to `<prefix>/hunspell` and unpacks the Finnish data to `<prefix>/voikko`; `host-run.sh` then uses them. `tests/spelling.qml` types a misspelt English and a misspelt Finnish word into a textarea, checks that a long press offers "mistake" and that applying it replaces the word. It saves `/tmp/pacific-spelling.png` showing the red underline.

`tests/run-host-tests.sh <prefix> <build>` runs all the host tests and fails on any failure or crash:
- `smoke.qml` on GPU frames;
- `smoke.qml` again with the WebProcess on software GL (`LIBGL_ALWAYS_SOFTWARE=1`, `PACIFIC_GPU_MODE=cpu`: wl_shm frames);
- `spelling.qml`;
- `userscripts.qml`;
- `console.qml`: console capture only on demand, page-world handlers in every frame;
- `privacy.qml` and `filters.qml`, against a local server;
- `visibility.qml` and, with `KEEL_QML`, `visibility-silica.qml`.

pacific-minibrowser options:

- `--silica`: Keel chrome.
- `--headless --snapshot`: prints the agent snapshot as JSON.
- `--screenshot <png>`: saves the window once the page has loaded and quits.
- `--script-input`.
- `--timeout <s>`.

## What the engine needs from the Sailjail profile

The app's `.desktop` file (`shoal/pacific/ui/shipwright-pacific.desktop`) should say:

```
[X-Sailjail]
Permissions=Internet;Downloads;Pictures;Audio;Camera;Microphone;Location;PacificWebEngine
OrganizationName=org.shipwright
ApplicationName=pacific
```

- `Internet`: page loads, done by the NetworkProcess, which runs inside the same jail.
- `Downloads`: saving downloads to ~/Downloads.
- `Pictures`: uploads through `fileChooserRequested`; add `Videos` and `Documents` if the picker offers them.
- `Audio`: media playback through PulseAudio (`x-maemo` role).
- `Camera` and `Microphone`: getUserMedia, used only after a `permissionRequested` prompt.
- `Location`: the geolocation bridge (Qt Positioning), used only after a prompt.
- `PacificWebEngine`: installed by `shipwright-pacific-engine` (`../engine/sailjail/PacificWebEngine.permission`). It covers:
  - `/opt/pacific`, the engine's files;
  - the GPU and libhybris device nodes the WebProcess renders through (`/dev/mali0`, `/dev/dma_heap`, the binder nodes, `/dev/__properties__`, `/odm`, ...);
  - the Wayland socket.

The app's data and cache directories come from `OrganizationName` and `ApplicationName`. Those are where `WebProfile` puts cookies, storage and the HTTP cache.

The app must start with the engine environment. Under Sailjail the `Exec` must be an ELF binary (a script is refused, and the sandbox has no shell): have the binary re-exec itself through `/usr/libexec/pacific/pacific-env`, as Pacific does (`app/src/lib.rs`, `engine_env`). Outside the sandbox `pacific-env.sh` also works as a wrapper. Without the environment, the engine's libraries and helpers are not found.

## Files and licences

- `src/viewbackend.*`, `src/pacificwebview.*`, `src/bridges.*`:
  - LGPL-2.1-or-later;
  - from Igalia's and Zodiac's WPE Qt API, through Atlantic's qt5-plugin (atlantic-engine a91f8ec);
  - ported to Qt 6 and extended.
- `src/requests.*`, `src/profile.*`, `src/imcontext.*`, `js/agent.js`, `js/page-info.js`, `js/console.js`: new, LGPL-2.1-or-later.
- `js/selection.js`, `js/pickers.js`, `js/scroll.js`, `js/ime-fallback.js`:
  - MPL-2.0;
  - from Atlantic's browser (atlantic-browser c150119, `apps/wpe`), which descends from Jolla's sailfish-browser.

Dropped from Atlantic's view:

- the direct-composite `wl_subsurface` and chrome overlay. They are parked in Atlantic, because Lipstick keeps a Silica window on the base layer.
- the Adreno shader-priming program;
- the pipelined frame-ack experiment.

Frame acknowledgement on Qt's path is `PACIFIC_FRAME_ACK=sample` (the default: one acknowledgement per frame Qt shows, so WebKit's scrolling steps once per shown frame), `pipeline`, `stock` or `eager` (`src/viewbackend.cpp`).

Thanks to Atlantic (SpecSierra) for the engine build, the Qt view and the many device findings cited in the comments.
