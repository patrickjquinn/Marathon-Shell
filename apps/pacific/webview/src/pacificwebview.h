// SPDX-FileCopyrightText: 2018, 2019, 2021 Igalia S.L
// SPDX-FileCopyrightText: 2018, 2019 Zodiac Inflight Innovations
// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine qt5-plugin)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// WebView (import Shipwright.Pacific.WebView 1.0): a Qt Quick item showing a
// WPE WebKit page. Qt 6 port of Atlantic's qt5-plugin WPEQtView (derived from
// Igalia's WPE Qt API), extended with what a full browser and Pilot need.
// See ../README.md for the QML API.

#pragma once

#include "imcontext.h"
#include "profile.h"
#include "requests.h"

#include <QElapsedTimer>
#include <QHash>
#include <QJSValue>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickItem>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

#include <memory>
#include <wpe/webkit.h>

class ViewBackend;
class QOpenGLContext;
class QSGSimpleTextureNode;
class QSGTexture;

class PacificWebView : public QQuickItem {
    Q_OBJECT
    QML_NAMED_ELEMENT(WebView)
    Q_DISABLE_COPY_MOVE(PacificWebView)

    // Page state
    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QUrl icon READ icon NOTIFY iconChanged)
    Q_PROPERTY(QString themeColor READ themeColor NOTIFY iconChanged)
    // The page asked to fill the screen around a notch (viewport-fit=cover).
    Q_PROPERTY(bool viewportFitCover READ viewportFitCover NOTIFY viewportFitCoverChanged)
    // The edge (item px) the page should keep content clear of: it reads it
    // as env(safe-area-inset-top). Set by the UI for viewport-fit=cover.
    Q_PROPERTY(qreal safeAreaTop READ safeAreaTop WRITE setSafeAreaTop NOTIFY safeAreaTopChanged)
    // The bottom edge (item px) the UI's own controls cover while the page
    // draws under them (a floating toolbar): the page can scroll its end
    // clear of it and keeps position: fixed elements above it.
    Q_PROPERTY(qreal obscuredBottom READ obscuredBottom WRITE setObscuredBottom NOTIFY obscuredBottomChanged)
    // How far (item px) one finger must drag down before pulledDown().
    Q_PROPERTY(qreal pullDistance MEMBER m_pullDistance NOTIFY pullDistanceChanged)
    // A pinch is scaling the page, or its result is on its way.
    Q_PROPERTY(bool zooming READ zooming NOTIFY zoomingChanged)
    Q_PROPERTY(int loadProgress READ loadProgress NOTIFY loadProgressChanged)
    Q_PROPERTY(bool loading READ isLoading NOTIFY loadingStateChanged)
    // Notified for same-document navigations (pushState) too.
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY backForwardChanged)
    Q_PROPERTY(bool canGoForward READ canGoForward NOTIFY backForwardChanged)
    // The session history entry on screen, as a key that stays the same for
    // that entry while it is in the list (historyItemAt() names the others):
    // the UI keeps a picture of each page it leaves under its key, for the
    // swipe back and forward.
    Q_PROPERTY(QString historyKey READ historyKey NOTIFY backForwardChanged)
    // Swipe back and forward (swipeNavMoved()); on by default.
    Q_PROPERTY(bool swipeNavigation MEMBER m_swipeNavEnabled NOTIFY swipeNavigationChanged)
    // The item the swipe is measured in: one that turns with the page but
    // does not follow the finger (the UI moves the view with it). Without
    // it, the view's own coordinates.
    Q_PROPERTY(QQuickItem* swipeFrame READ swipeFrame WRITE setSwipeFrame NOTIFY swipeNavigationChanged)
    Q_PROPERTY(bool secure READ isSecure NOTIFY securityChanged)
    Q_PROPERTY(bool audioPlaying READ isAudioPlaying NOTIFY audioChanged)
    Q_PROPERTY(bool muted READ isMuted WRITE setMuted NOTIFY audioChanged)
    Q_PROPERTY(bool webProcessRunning READ webProcessRunning NOTIFY webProcessRunningChanged)
    Q_PROPERTY(bool created READ created NOTIFY webViewCreated)

    // Configuration
    Q_PROPERTY(WebProfile* profile READ profile WRITE setProfile NOTIFY profileChanged)
    Q_PROPERTY(QString userAgent READ userAgent WRITE setUserAgent NOTIFY userAgentChanged)
    Q_PROPERTY(bool desktopMode READ desktopMode WRITE setDesktopMode NOTIFY desktopModeChanged)
    Q_PROPERTY(qreal zoomFactor READ zoomFactor WRITE setZoomFactor NOTIFY zoomFactorChanged)
    Q_PROPERTY(qreal contentScale READ contentScale WRITE setContentScale NOTIFY contentScaleChanged)
    Q_PROPERTY(bool active READ isActive WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool headless READ headless WRITE setHeadless NOTIFY headlessChanged)
    // Nothing is drawn over the page: its frames may go
    // straight to the compositor on a subsurface (directsurface.h).
    Q_PROPERTY(bool directComposite READ directComposite WRITE setDirectComposite NOTIFY directCompositeChanged)
    // The newest frame from WebKit has the view's size: false from a resize
    // until WebKit has drawn at the new size (about 70 ms on the Jolla
    // Phone), when the view shows an older, smaller frame. The UI holds the
    // toolbar over the page until then, so its slide reveals drawn content.
    Q_PROPERTY(bool frameFitsView READ frameFitsView NOTIFY frameFitsViewChanged)
    // From a navigation's start until the new document has painted
    // (pacificPainted, page-info.js) or the load ends: the UI shows the page
    // being left over the view. Frames after the commit could still be the
    // old document's, and garbled as its buffers went.
    Q_PROPERTY(bool pageBlanked READ pageBlanked NOTIFY pageBlankedChanged)
    // What the page is told: document.visibilityState is "visible" exactly
    // when this is true (active, shown on screen, application on screen).
    Q_PROPERTY(bool pageVisible READ pageVisible NOTIFY pageVisibleChanged)
    Q_PROPERTY(InputMode inputMode READ inputMode WRITE setInputMode NOTIFY inputModeChanged)
    Q_PROPERTY(bool scriptSelectMenus READ scriptSelectMenus WRITE setScriptSelectMenus NOTIFY scriptSelectMenusChanged)
    Q_PROPERTY(bool captureConsole READ captureConsole WRITE setCaptureConsole NOTIFY captureConsoleChanged)
    Q_PROPERTY(bool javascriptEnabled READ javascriptEnabled WRITE setJavascriptEnabled NOTIFY settingsChanged)
    Q_PROPERTY(bool loadImages READ loadImages WRITE setLoadImages NOTIFY settingsChanged)
    Q_PROPERTY(bool mediaNeedsUserGesture READ mediaNeedsUserGesture WRITE setMediaNeedsUserGesture NOTIFY settingsChanged)

    // Input method
    Q_PROPERTY(bool editableFocused READ editableFocused NOTIFY inputMethodStateChanged)
    Q_PROPERTY(QRectF cursorRectangle READ cursorRectangle NOTIFY inputMethodStateChanged)
    Q_PROPERTY(InputPurpose inputPurpose READ inputPurpose NOTIFY inputMethodStateChanged)

    // Selection and find
    Q_PROPERTY(QString selectedText READ selectedText NOTIFY selectionChanged)
    Q_PROPERTY(int findMatchCount READ findMatchCount NOTIFY findMatchCountChanged)
    // Requests the profile's content filters blocked on the current page
    // (reset when a new page starts loading).
    Q_PROPERTY(int blockedRequestCount READ blockedRequestCount NOTIFY blockedRequestCountChanged)

public:
    enum InputMode { NativeInput, ScriptInput };
    Q_ENUM(InputMode)
    enum InputPurpose { FreeForm, Digits, Number, Phone, Url, Email, Password, Search };
    Q_ENUM(InputPurpose)
    enum TerminationReason { Crashed, ExceededMemoryLimit, TerminatedByApi };
    Q_ENUM(TerminationReason)
    enum InjectionTime { DocumentStart, DocumentEnd };
    Q_ENUM(InjectionTime)
    enum EditingCommand { Cut, Copy, Paste, PasteAsPlainText, SelectAll, Undo, Redo };
    Q_ENUM(EditingCommand)

    explicit PacificWebView(QQuickItem* parent = nullptr);
    ~PacificWebView() override;

    // Page state
    QUrl url() const;
    void setUrl(const QUrl& url);
    QString title() const;
    QUrl icon() const { return m_icon; }
    QString themeColor() const { return m_themeColor; }
    int loadProgress() const;
    bool isLoading() const;
    bool canGoBack() const;
    bool canGoForward() const;
    QString historyKey() const;
    QQuickItem* swipeFrame() const { return m_swipeFrame; }
    void setSwipeFrame(QQuickItem* frame)
    {
        if (m_swipeFrame == frame)
            return;
        m_swipeFrame = frame;
        Q_EMIT swipeNavigationChanged();
    }
    bool isSecure() const { return m_secure; }
    bool isAudioPlaying() const;
    bool isMuted() const;
    void setMuted(bool muted);
    bool webProcessRunning() const { return m_webView && !m_terminated; }
    bool created() const { return m_webView != nullptr; }

    // Configuration
    WebProfile* profile() const;
    void setProfile(WebProfile* profile);
    QString userAgent() const;
    void setUserAgent(const QString& userAgent);
    bool desktopMode() const { return m_desktopMode; }
    void setDesktopMode(bool desktop);
    qreal zoomFactor() const { return m_zoomFactor; }
    void setZoomFactor(qreal factor);
    qreal fitScale() const { return m_fitScale; }
    qreal contentScale() const;
    void setContentScale(qreal scale);
    bool isActive() const { return m_active; }
    void setActive(bool active);
    bool headless() const { return m_headless; }
    bool directComposite() const { return m_directComposite; }
    bool frameFitsView() const { return m_frameFitsView; }
    bool pageBlanked() const { return m_pageBlanked; }
    bool viewportFitCover() const { return m_viewportFitCover; }
    qreal safeAreaTop() const { return m_safeAreaTop; }
    bool zooming() const { return m_pinch.active || m_pinch.committing; }
    void setSafeAreaTop(qreal top);
    qreal obscuredBottom() const { return m_obscuredBottom; }
    void setObscuredBottom(qreal bottom);
    void setDirectComposite(bool direct);
    bool pageVisible() const { return m_pageVisible; }
    void setHeadless(bool headless);
    InputMode inputMode() const { return m_inputMode; }
    void setInputMode(InputMode mode);
    bool scriptSelectMenus() const { return m_scriptSelectMenus; }
    void setScriptSelectMenus(bool enabled);
    bool captureConsole() const { return m_captureConsole; }
    void setCaptureConsole(bool enabled);
    bool javascriptEnabled() const;
    void setJavascriptEnabled(bool enabled);
    bool loadImages() const;
    void setLoadImages(bool enabled);
    bool mediaNeedsUserGesture() const;
    void setMediaNeedsUserGesture(bool needed);

    // Input method
    bool editableFocused() const { return m_im.focused; }
    QRectF cursorRectangle() const;
    InputPurpose inputPurpose() const { return static_cast<InputPurpose>(m_im.purpose); }
    ImState imState() const { return m_im; }
    void setImState(const ImState& state, bool focusChange);
    void resetInputMethod();

    QString selectedText() const { return m_selectedText; }
    int findMatchCount() const { return m_findMatchCount; }
    int blockedRequestCount() const { return m_blockedRequestCount; }

    WebKitWebView* webView() const { return m_webView; }
    // For NewWindowRequest.openIn(): creates this view's web view as a
    // related view of the opener (shared process and session).
    bool createRelatedWebView(PacificWebView* opener);

    // Backend callbacks
    void notifyFullscreenRequest(bool enter);
    void dispatchEarlyAck();

    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;
    // Entry point for the script-message GObject closures.
    void handleScriptMessagePublic(const char* name, JSCValue* value);

public Q_SLOTS:
    void load(const QUrl& url);
    void loadHtml(const QString& html, const QUrl& baseUrl = QUrl());
    void goBack();
    void goForward();
    // The history entry `offset` steps from the one on screen (-1 back, 1
    // forward): {key, url, title}, or an empty map when there is none.
    QVariantMap historyItemAt(int offset) const;
    // A picture of the page as it is on screen, kept under historyKey (an
    // image://pacifichistory/<key> source) for the swipe back and forward
    // to show while that entry is not the one on screen; taken by the
    // engine, so it works whatever composites the view. Asynchronous:
    // historyPictureReady(key) says when it is there.
    void captureHistoryPicture();
    bool hasHistoryPicture(const QString& key) const;
    void reload();
    void reloadBypassCache();
    void stop();

    // Runs script in the page's main world. callback(result, error): result
    // is the JSON-converted value (object, array, string, number, bool, null).
    void runJavaScript(const QString& script, const QJSValue& callback = QJSValue());
    // Runs script in a named isolated world: same DOM, separate globals, the
    // page cannot see or change it. Pacific's own helpers live in "pacific".
    void runJavaScriptInWorld(const QString& script, const QString& world, const QJSValue& callback = QJSValue());

    // Find in page. findMatchCount and findResult(count) report matches.
    void findText(const QString& text, bool caseSensitive = false);
    void findNext();
    void findPrevious();
    void stopFind();

    void executeEditingCommand(EditingCommand command);
    // Inserts text at the caret as if typed (trusted editing).
    void insertText(const QString& text);
    // Copies the selection to the system clipboard.
    void copySelection();
    void clearSelection();

    // Spelling, for the last contextMenuRequested whose info had
    // misspelled: true: replace the word with info.spellingSuggestions[index],
    // add it to the personal dictionary, or ignore it for this session.
    bool applySpellingSuggestion(int index);
    // Opens WebKit's context menu at a point in CSS px (viewport), as a long
    // press does: contextMenuRequested follows (spelling, links, images).
    void contextMenuAt(qreal cssX, qreal cssY);
    bool learnSpelling();
    bool ignoreSpelling();

    // Pickers: answers to selectMenuRequested / inputPickerRequested.
    void selectMenuOption(int index);
    void closeSelectMenu();
    void resolveInputPicker(const QString& value);
    void cancelInputPicker();

    // Tab lifecycle. discard() ends the WebProcess to free its memory (the
    // view keeps its URL and session history; reload() brings it back).
    void discard();
    QString sessionState() const;
    bool restoreSessionState(const QString& base64);
    void saveThumbnail(const QString& path, int maxWidth, int maxHeight, const QJSValue& callback = QJSValue());

    // Settings and content
    void setSetting(const QString& name, const QVariant& value);
    QVariant setting(const QString& name) const;
    bool setFeatureEnabled(const QString& identifier, bool enabled);
    // User scripts and style sheets added by the UI or the core (autoconsent,
    // cosmetic filtering). world: "" = page world. skipHosts: sites (and
    // their subdomains) the script stays out of. Returns a handle for
    // removeUserScript() (0: not added).
    int addUserScript(const QString& source, const QString& world = QString(),
        InjectionTime time = DocumentEnd, bool allFrames = false, const QStringList& skipHosts = QStringList());
    void removeUserScript(int handle);
    void addUserStyleSheet(const QString& css, bool allFrames = true);
    void removeUserContent();
    // window.webkit.messageHandlers.<name>.postMessage(x) -> scriptMessage(name, x)
    bool registerScriptMessageHandler(const QString& name, const QString& world = QString());

    // Pilot / agent access (isolated world; see README "Agent API").
    // callback(result) with result a JS object; errors as {ok:false, error}.
    void agentSnapshot(const QVariantMap& options, const QJSValue& callback);
    // A trusted tap at the element's centre (native touch through WebKit),
    // after scrolling it into view; falls back to a script click when the
    // view is not laid out. callback({ok, ...})
    void agentClick(const QString& id, const QJSValue& callback = QJSValue());
    void agentFocus(const QString& id, const QJSValue& callback = QJSValue());
    void agentSetValue(const QString& id, const QVariant& value, const QJSValue& callback = QJSValue());
    // Focuses the element with a trusted tap, then inserts text as typing.
    void agentType(const QString& id, const QString& text, const QJSValue& callback = QJSValue());
    void agentSubmit(const QString& id, const QJSValue& callback = QJSValue());
    void agentScroll(int dx, int dy, const QJSValue& callback = QJSValue());
    void pageText(int maxChars, const QJSValue& callback);
    void pageHtml(int maxChars, const QJSValue& callback);
    void readerContent(const QJSValue& callback);

Q_SIGNALS:
    void webViewCreated();
    void urlChanged();
    void titleChanged();
    void iconChanged();
    void loadProgressChanged();
    void loadingStateChanged();
    void loadingChanged(LoadRequest* loadRequest);
    void backForwardChanged();
    void securityChanged();
    void certificateError(const QUrl& url, const QString& host, int errors, const QString& certificatePem);
    void audioChanged();
    void webProcessRunningChanged();
    void webProcessTerminated(PacificWebView::TerminationReason reason);
    void webProcessUnresponsive(bool unresponsive);

    void profileChanged();
    void userAgentChanged();
    void desktopModeChanged();
    void zoomFactorChanged();
    void contentScaleChanged();
    void activeChanged();
    void headlessChanged();
    void directCompositeChanged();
    void frameFitsViewChanged();
    void pageBlankedChanged();
    void viewportFitCoverChanged();
    void safeAreaTopChanged();
    void obscuredBottomChanged();
    void pageVisibleChanged();
    void inputModeChanged();
    void scriptSelectMenusChanged();
    void captureConsoleChanged();
    void settingsChanged();

    void newWindowRequested(NewWindowRequest* request);
    void navigationRequested(NavigationRequest* request);
    void closeRequested();
    void permissionRequested(PermissionRequest* request);
    void downloadRequested(Download* download);
    void scriptDialogRequested(ScriptDialog* dialog);
    void fileChooserRequested(FileChooserRequest* request);
    void authenticationRequested(AuthenticationRequest* request);
    void notificationRequested(const QString& title, const QString& body, const QString& tag, const QUrl& origin);
    void fullscreenRequested(bool fullscreen);

    void inputMethodStateChanged();
    void selectionChanged();
    // Selection handles, CSS px viewport -> item coordinates.
    void selectionHandlesChanged(const QPointF& start, const QPointF& end);
    void contextMenuRequested(const QVariantMap& info);
    void selectMenuRequested(const QVariantList& options, int selectedIndex, const QRectF& rect);
    void inputPickerRequested(const QString& type, const QString& value, const QString& min, const QString& max,
        const QString& step, const QRectF& rect);
    void scrollChanged(qreal scrollY, qreal contentHeight, qreal viewportHeight);
    void pinchConsumedByPage(bool consumed);
    // One finger dragged down (towards the top of the page) by pullDistance,
    // once per touch, whether or not the page scrolled: the UI shows its
    // toolbar even on a page that has stopped its own scrolling.
    void pulledDown();
    // Pull to refresh: one finger dragging down a page that was at its top
    // when the finger landed (and does not opt out with overscroll-behavior
    // or take the drag itself), as Chrome's rules are. `distance` is how far
    // the finger is below where it started (item px, 0 when it went back
    // up); pullEnded() comes once when the finger lifts or the pull is off,
    // with the finger's speed then (item px per ms, positive down).
    void pullMoved(qreal distance);
    void pullEnded(qreal distance, qreal velocity);
    // Swipe back and forward, as Chrome on Android does it (the screen's
    // edges belong to Sailfish's own gestures): one finger dragging sideways
    // where the page cannot scroll that way any further (scroll.js asks the
    // page under the finger, at touch-down), with history that way. Once
    // the drag is the browser's the page gets the touch's end and no more of
    // it. `dx` is how far the finger is from where the swipe began (item px,
    // positive right: back); swipeNavEnded() comes once, with the finger's
    // speed (item px per ms, positive right) as it lifted.
    void swipeNavMoved(qreal dx);
    void swipeNavEnded(qreal dx, qreal velocity);
    void swipeNavigationChanged();
    void historyPictureReady(const QString& key);
    void pullDistanceChanged();
    void zoomingChanged();
    void findMatchCountChanged();
    void blockedRequestCountChanged();
    void blockedRequest(const QUrl& url);
    void findResult(int count);
    void consoleMessage(const QString& level, const QString& message, const QString& source);
    void scriptMessage(const QString& name, const QVariant& message);

protected:
    void componentComplete() override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData& value) override;
    void updatePolish() override;
    QSGNode* updatePaintNode(QSGNode* node, UpdatePaintNodeData* data) override;
    void releaseResources() override;

    void hoverMoveEvent(QHoverEvent* event) override;
    void hoverLeaveEvent(QHoverEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;
    void mouseMoveEvent(QMouseEvent* event) override;
    void mouseReleaseEvent(QMouseEvent* event) override;
    void wheelEvent(QWheelEvent* event) override;
    void keyPressEvent(QKeyEvent* event) override;
    void keyReleaseEvent(QKeyEvent* event) override;
    void touchEvent(QTouchEvent* event) override;
    void inputMethodEvent(QInputMethodEvent* event) override;
    void focusInEvent(QFocusEvent* event) override;
    void focusOutEvent(QFocusEvent* event) override;
    bool eventFilter(QObject* watched, QEvent* event) override;

private Q_SLOTS:
    void onFrameSwapped();
    void onSceneGraphInitialized();
    void applyGlobalPrivacyControl();

private:
    friend struct PacificWebViewCallbacks;

    bool ensureWebView(WebKitWebView* related = nullptr);
    void connectWebView();
    void installPageScripts();
    void installConsoleCapture();
    void removeConsoleCapture();
    void registerBridgeHandlers();
    void applyPendingState();
    void applyActivityState();
    void setPageVisible(bool visible, bool focused);
    void updateBackendGeometry();
    QSize physicalSize() const;
    qreal itemToPhysical() const;
    qreal effectiveContentScale() const;
    QPointF cssToItem(qreal x, qreal y) const;
    void evaluate(const QString& script, const char* world, const QJSValue& callback);
    void agentCall(const QString& expression, const QJSValue& callback);
    void tapAt(const QPointF& itemPoint);
    QString defaultUserAgent(bool desktop) const;
    void handleScriptMessage(const char* name, JSCValue* value);
    void setIcon(const QUrl& icon, const QString& themeColor);
    void updateSecurity();
    bool activateContextItem(WebKitContextMenuAction action, int index);

    WebKitWebView* m_webView = nullptr;
    // Pinch to zoom (the page scale, not page zoom: the page is magnified,
    // not laid out again), unless the page handles two fingers itself.
    struct {
        bool pageConsumes = false; // this gesture, from scroll.js
        bool active = false;       // scaling now
        bool swallow = false;      // until every finger is up
        qreal startDistance = 0;
        double startScale = 1;
        double lastScale = 1;
        QElapsedTimer since;       // second finger down
        // While the fingers move, the last frame is scaled on screen about
        // `center` (item px); WebKit renders the new scale once, at the end.
        qreal visual = 1;
        QPointF center;
        // Where the fingers' midpoint is now: the scaled frame follows it,
        // as the page under the fingers does in Safari and Chrome.
        QPointF fingers;
        // The document's edges in item px of the view as the pinch began,
        // from the page (asynchronously): WebKit keeps the zoomed page
        // within them, so the preview's movement is held to them too.
        bool haveBounds = false;
        QRectF document;
        // The first frame (ViewBackend::arrivedSerial) drawn at the new
        // scale, once the page has drawn twice since; then the preview goes
        // in the render pass that draws it.
        quint64 awaitSerial = 0;
        bool showFinal = false;
        // At release the frame on screen is copied (render thread) and
        // shown, scaled, until the frame at the new scale is drawn: frames
        // that keep arriving meanwhile, some at the old scale and some at
        // the new, stay hidden (scaling those was zooming them twice).
        bool snapshotWanted = false;
        bool haveSnapshot = false;
        bool committing = false;   // the scaled frame waits for WebKit's
        QElapsedTimer committed;
    } m_pinch;
    qreal m_pullDistance = 40;
    QPointF m_pullStart;
    bool m_pullDone = false;
    // Pull to refresh (see pullMoved()): whether the page said, for this
    // touch, that it is at its top and lets the browser have the pull.
    enum class PullVerdict { Unknown, Yes, No };
    struct {
        PullVerdict verdict = PullVerdict::Unknown;
        bool active = false;
        qreal distance = 0;
        QPointF last;
        qint64 lastAt = 0;
        qreal velocity = 0; // item px per ms, smoothed
    } m_refreshPull;
    void endRefreshPull();
    bool pageZoomedIn() const;
    void trackPull(QTouchEvent* event);
    // Swipe back and forward (swipeNavMoved()): true while the browser has
    // the touch, which then no longer goes to the page.
    bool trackSwipeNav(QTouchEvent* event);
    bool m_swipeNavEnabled = true;
    QPointer<QQuickItem> m_swipeFrame;
    QPointF swipePoint(const QEventPoint& point) const;
    enum class SwipeState { Undecided, Swiping, No };
    struct {
        SwipeState state = SwipeState::No;
        // What scroll.js said for this touch: the page under the finger
        // can go no further left (back) or right (forward).
        bool pageAnswered = false;
        bool back = false;
        bool forward = false;
        QPointF start;
        qreal startX = 0; // where the swipe itself began
        qreal dx = 0;
        qreal lastX = 0;
        qint64 lastAt = 0;
        qreal velocity = 0; // item px per ms, smoothed
    } m_swipeNav;
    QPointF pinchPan() const;
    void fetchPinchBounds();
    void takePinchSnapshot(QOpenGLContext* context);
    void dropPinchSnapshot(QOpenGLContext* context);
    unsigned m_snapshotTexture = 0;
    QSize m_snapshotSize;
    QSGTexture* m_snapshotSg = nullptr;
    QSGSimpleTextureNode* m_snapshotNode = nullptr;
    QRectF m_snapshotRect;
    bool handlePinch(QTouchEvent* event);
    void finishPinch();
    void endPinchVisual();
public:
    // ViewBackend: a web frame arrived (ends a pinch's scaled preview).
    void webFrameArrived(QSize frameSize);
private:
    ViewBackend* m_backend = nullptr; // owned by the WebKitWebViewBackend
    WebKitInputMethodContext* m_imContext = nullptr;
    WebKitOptionMenu* m_optionMenu = nullptr;
    WebKitContextMenu* m_contextMenu = nullptr;
    QStringList m_spellingSuggestions;
    bool m_misspelled = false;
    QPointer<WebProfile> m_profile;
    bool m_completed = false;
    bool m_terminated = false;
    bool m_errorOccurred = false;

    QUrl m_url;
    QString m_html;
    QUrl m_baseUrl;
    QUrl m_icon;
    void applyZoom();
    void setFitScale(qreal scale);
    qreal pageZoom() const { return m_zoomFactor * m_fitScale; }
    QString m_themeColor;
    bool m_secure = false;
    QString m_userAgent;
    bool m_desktopMode = false;
    qreal m_zoomFactor = 1.0;
    // The page's fit-to-width scale (meta viewport width, or 980 CSS px
    // without one), times the user's zoom; 1 for device-width pages.
    qreal m_fitScale = 1.0;
    QVariantMap m_pendingSettings; // setSetting() before WebKit's view exists
    qreal m_contentScale = 0; // 0 = automatic, from the screen
    qreal m_lastRatio = 0;
    bool m_nodeHasShmTexture = false; // render thread
    unsigned m_wrappedTextureId = 0; // render thread: the GL texture the node shows
    // PACIFIC_TRACE_LOAD: each navigation's commit, first frame after it
    // (what the person first sees) and finish, in ms from its start.
    struct LoadTrace {
        bool enabled = qEnvironmentVariableIsSet("PACIFIC_TRACE_LOAD");
        QElapsedTimer clock;
        bool committed = false;
        bool painted = false;
        void start(const QUrl& url)
        {
            if (!enabled)
                return;
            clock.start();
            committed = painted = false;
            qInfo("Pacific load: start %s", qPrintable(url.host()));
        }
        void mark(const char* what) const
        {
            if (enabled && clock.isValid())
                qInfo("Pacific load: %s %lld ms", what, static_cast<long long>(clock.elapsed()));
        }
    } m_loadTrace; // GUI thread
    bool m_active = true;
    bool m_headless = false;
    bool m_geometryPending = false;
    bool m_sizedFrameSeen = false;
    bool m_directComposite = false;
    bool m_frameFitsView = true;
    // A touch that lands on a page still coasting from a fling catches it,
    // and never long-presses (selection.js's timer, or WebKit's): its
    // selection and context menu are dropped, as Chromium and iOS do. The
    // fling is modelled from the finger's speed as it lifted, decaying as
    // WebKit's (WEBKIT_KINETIC_DECEL_FRICTION), or seen in frames still
    // arriving shortly after a flick (a stacked fling runs longer).
    struct {
        QPointF lastPos;
        qint64 lastAt = 0;
        qreal speed = 0; // px/ms, the finger's, smoothed
        qreal liftSpeed = 0;
        QElapsedTimer lift;
        QElapsedTimer frame;
        bool down = false;
        bool caught = false;
        QElapsedTimer up;
    } m_catch;
    void trackCatch(QTouchEvent* event);
    bool catchActive() const;
    bool m_pageBlanked = false;
    bool m_paintedPending = false;
    // The navigation that blanked the page has committed its document.
    bool m_pageCommitted = false;
    // Which page change a timer was started for.
    unsigned m_pageChangeSerial = 0;
    void setPageBlanked(bool blanked);
    void endPageChangeOnNextFrame();
    QSize m_lastFrameSize;
    void updateFrameFits();
    bool m_viewportFitCover = false;
    qreal m_safeAreaTop = 0;
    void applySafeArea();
    qreal m_obscuredBottom = 0;
    void applyObscured();
    void setViewportFitCover(bool cover);
    void updateDirect();
    bool m_pageVisible = true; // WebKit's initial state
    QTimer m_hideTimer;
    InputMode m_inputMode = NativeInput;
    bool m_scriptSelectMenus = false;
    bool m_captureConsole = false;
    bool m_consoleHandler = false;
    WebKitUserScript* m_consoleScript = nullptr;
    // Scripts added through addUserScript(), by handle.
    QHash<int, WebKitUserScript*> m_userScripts;
    int m_nextUserScript = 1;
    void dropUserScripts();
    bool m_muted = false;

    ImState m_im;
    QString m_preedit;
    QString m_selectedText;
    int m_findMatchCount = 0;
    int m_blockedRequestCount = 0;
    QString m_findText;
};
