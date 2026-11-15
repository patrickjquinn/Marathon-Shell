// SPDX-FileCopyrightText: 2018, 2019, 2021 Igalia S.L
// SPDX-FileCopyrightText: 2018, 2019 Zodiac Inflight Innovations
// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine qt5-plugin)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "pacificwebview.h"

#include "bridges.h"
#include "profile.h"
#include "requests.h"
#include "viewbackend.h"

#include <QClipboard>
#include <QDesktopServices>
#include <QLineF>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QInputDevice>
#include <QInputMethod>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaMethod>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QPointingDevice>
#include <QMutex>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QScreen>
#include <QThreadPool>
#include <QTimer>
#include <QtQuick/qsgtexture_platform.h>
#include <qpa/qplatformnativeinterface.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <limits>
#include <dlfcn.h>
#include <cstddef>
#include <cstring>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <utility>

namespace {
void requestBoost(uint32_t ms);
}

namespace {

constexpr const char* kWorld = "pacific";

QString loadScript(const char* name)
{
    QFile file(QStringLiteral(":/pacific/webview/js/%1").arg(QLatin1String(name)));
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning("Pacific WebView: missing page script %s", name);
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

QVariant jscToVariant(JSCValue* value)
{
    if (!value || jsc_value_is_undefined(value))
        return {};
    char* json = jsc_value_to_json(value, 0);
    if (!json)
        return {};
    // Wrap so that scalars parse as JSON too.
    const QByteArray wrapped = QByteArray("[") + json + "]";
    g_free(json);
    const QJsonDocument doc = QJsonDocument::fromJson(wrapped);
    const QJsonArray array = doc.array();
    return array.isEmpty() ? QVariant() : array.first().toVariant();
}

QString jsonArgument(const QVariant& value)
{
    // A one-element array keeps any string safe inside a script literal.
    const QByteArray json = QJsonDocument(QJsonArray { QJsonValue::fromVariant(value) }).toJson(QJsonDocument::Compact);
    return QStringLiteral("(%1)[0]").arg(QString::fromUtf8(json));
}

bool hasProperty(gpointer object, const char* name)
{
    return g_object_class_find_property(G_OBJECT_GET_CLASS(object), name) != nullptr;
}

// The schemes WebKit loads itself. Pacific identifies as Chrome on Android
// (kMobileUserAgent), so pages also send it Android's app links: tel:,
// mailto:, intent:, market:, a shop's own scheme. Navigated to, WebKit
// replaced the page with "The URL can't be shown" (AliExpress's home page
// sent itself to its app's link as it loaded, on every visit).
bool webKitLoads(const QString& scheme)
{
    return scheme == QLatin1String("https") || scheme == QLatin1String("http") || scheme == QLatin1String("about")
        || scheme == QLatin1String("data") || scheme == QLatin1String("blob") || scheme == QLatin1String("file");
}

// An intent: link's web page for when the app is not installed
// (S.browser_fallback_url in its #Intent;...;end part).
QUrl intentFallback(const QUrl& intent)
{
    const QStringList parts = intent.fragment(QUrl::FullyEncoded).split(QLatin1Char(';'));
    for (const QString& part : parts) {
        if (!part.startsWith(QLatin1String("S.browser_fallback_url=")))
            continue;
        const QUrl fallback(QUrl::fromPercentEncoding(part.mid(23).toUtf8()));
        if (fallback.scheme() == QLatin1String("https") || fallback.scheme() == QLatin1String("http"))
            return fallback;
    }
    return {};
}

// Pacific's mobile identity: Chrome on Android, exactly as Chrome sends it
// (the reduced user agent: Android 10, model "K"). Sites sniff for
// "Android" or "iPhone": with "Linux; Sailfish OS; Mobile" Facebook showed
// its unsupported-browser page and Yahoo its desktop site, and as Safari on
// an iPhone sites offered App Store apps. Desktop mode is what Chrome on
// Android sends for desktop sites. Keep the Chrome version near current
// stable (153 in October 2026): sites warn about browsers a year old.
// The UI can replace either, per site if it likes.
const char* kMobileUserAgent = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 "
                               "(KHTML, like Gecko) Chrome/153.0.0.0 Mobile Safari/537.36";
const char* kDesktopUserAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                                "(KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36";

bool pageZoomScaling()
{
    static const bool zoom = qgetenv("PACIFIC_SCALE_MODE") == "zoom";
    return zoom;
}

struct JsCallback {
    QPointer<PacificWebView> view;
    QJSValue callback;
};

void deliver(JsCallback* data, const QVariant& result, const QString& error)
{
    std::unique_ptr<JsCallback> guard(data);
    if (!data->view || !data->callback.isCallable())
        return;
    QJSEngine* engine = qjsEngine(data->view);
    if (!engine)
        return;
    data->callback.call({ engine->toScriptValue(result), error.isEmpty() ? QJSValue(QJSValue::NullValue) : QJSValue(error) });
}

// The view needs Qt Quick on OpenGL. When the module loads before any window
// exists (the usual case: the root QML file imports it), pick OpenGL for the
// app unless it chose a graphics API itself.
void forceOpenGLRhi()
{
    if (QQuickWindow::graphicsApi() == QSGRendererInterface::OpenGL || qEnvironmentVariableIsSet("QSG_RHI_BACKEND"))
        return;
    const auto windows = QGuiApplication::topLevelWindows();
    for (QWindow* window : windows) {
        if (qobject_cast<QQuickWindow*>(window))
            return; // too late; itemChange() warns
    }
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
}
Q_COREAPP_STARTUP_FUNCTION(forceOpenGLRhi)

} // namespace

// Whether the application counts as on screen. Sailfish OS reports
// ApplicationInactive while the app is minimised to its cover, so there it
// hides pages; elsewhere (desktop, test compositors) Inactive only means
// unfocused and the page stays visible. PACIFIC_INACTIVE_HIDES=0|1 overrides.
static bool applicationShown()
{
    static const bool inactiveHides = [] {
        const QByteArray env = qgetenv("PACIFIC_INACTIVE_HIDES");
        if (!env.isEmpty())
            return env != "0";
        return QFileInfo::exists(QStringLiteral("/etc/sailfish-release"));
    }();
    switch (QGuiApplication::applicationState()) {
    case Qt::ApplicationActive:
        return true;
    case Qt::ApplicationInactive:
        return !inactiveHides;
    default:
        return false;
    }
}

// GObject signal handlers, with access to the view's internals.
struct PacificWebViewCallbacks {
    static void uriChanged(PacificWebView* self)
    {
        if (const gchar* uri = webkit_web_view_get_uri(self->m_webView))
            self->m_url = QUrl(QString::fromUtf8(uri));
        Q_EMIT self->urlChanged();
    }

    static void loadChanged(WebKitWebView*, WebKitLoadEvent event, PacificWebView* self)
    {
        LoadRequest::Status status = LoadRequest::Started;
        switch (event) {
        case WEBKIT_LOAD_STARTED:
            self->m_loadTrace.start(self->url());
            self->m_pageCommitted = false;
            self->setPageBlanked(true);
            self->m_errorOccurred = false;
            if (self->m_blockedRequestCount) {
                self->m_blockedRequestCount = 0;
                Q_EMIT self->blockedRequestCountChanged();
            }
            if (self->m_terminated) {
                self->m_terminated = false;
                Q_EMIT self->webProcessRunningChanged();
            }
            self->setIcon(QUrl(), QString());
            status = LoadRequest::Started;
            break;
        case WEBKIT_LOAD_REDIRECTED:
            status = LoadRequest::Redirected;
            break;
        case WEBKIT_LOAD_COMMITTED:
            self->updateSecurity();
            // A new document: its viewport (page-info.js) sets the fit and
            // viewport-fit again; a new web process needs the insets again.
            self->setFitScale(1.0);
            self->setViewportFitCover(false);
            self->applySafeArea();
            self->applyObscured();
            self->m_loadTrace.mark("committed");
            self->m_loadTrace.committed = true;
            self->m_pageCommitted = true;
            status = LoadRequest::Committed;
            break;
        case WEBKIT_LOAD_FINISHED:
            // A load can finish before its document's first frame, and a
            // frame then could still be the old document's: pacificPainted
            // ends the page change, or a second from here (a page where
            // Pacific's scripts do not run). One that never committed (a
            // download, Stop) leaves the old page, which is still there.
            if (self->m_pageCommitted) {
                QTimer::singleShot(1000, self, [self, serial = self->m_pageChangeSerial] {
                    if (serial == self->m_pageChangeSerial && self->m_pageBlanked) {
                        self->m_loadTrace.mark("page change ended without painting");
                        self->setPageBlanked(false);
                    }
                });
            } else {
                self->setPageBlanked(false);
            }
            if (self->m_errorOccurred) {
                self->m_errorOccurred = false;
                Q_EMIT self->backForwardChanged();
                return;
            }
            status = LoadRequest::Succeeded;
            self->m_loadTrace.mark("finished");
            break;
        }
        LoadRequest request(self->url(), status);
        Q_EMIT self->loadingChanged(&request);
        Q_EMIT self->backForwardChanged();
    }

    static gboolean loadFailed(WebKitWebView*, WebKitLoadEvent, const gchar* uri, GError* error, PacificWebView* self)
    {
        self->m_errorOccurred = true;
        const bool cancelled = g_error_matches(error, WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_CANCELLED);
        LoadRequest request(QUrl(QString::fromUtf8(uri)), cancelled ? LoadRequest::Stopped : LoadRequest::Failed,
            QString::fromUtf8(error->message), error->code, QString::fromUtf8(g_quark_to_string(error->domain)));
        Q_EMIT self->loadingChanged(&request);
        return FALSE; // WebKit shows its error page
    }

    static gboolean tlsFailed(WebKitWebView*, const gchar* uri, GTlsCertificate* certificate, GTlsCertificateFlags errors,
        PacificWebView* self)
    {
        gchar* pem = nullptr;
        g_object_get(certificate, "certificate-pem", &pem, nullptr);
        const QUrl url(QString::fromUtf8(uri));
        Q_EMIT self->certificateError(url, url.host(), static_cast<int>(errors), QString::fromUtf8(pem));
        g_free(pem);
        self->m_errorOccurred = true;
        return self->isSignalConnected(QMetaMethod::fromSignal(&PacificWebView::certificateError));
    }

    static WebKitWebView* create(WebKitWebView*, WebKitNavigationAction* action, PacificWebView* self)
    {
        NewWindowRequest request(self, action);
        QQmlEngine::setObjectOwnership(&request, QQmlEngine::CppOwnership);
        Q_EMIT self->newWindowRequested(&request);
        return request.result();
    }

    // A navigation WebKit cannot load, as Chrome on Android treats it: one
    // the person tapped goes to the system (Sailfish's handler for tel:,
    // mailto:, sms:...), an intent: link to its web fallback; one a page
    // makes on its own is dropped, and the page stays.
    static void handOff(PacificWebView* self, const QUrl& url, bool userInitiated)
    {
        qInfo("Pacific: %s navigation to %s:%s", userInitiated ? "tapped" : "dropped unasked",
            qPrintable(url.scheme()), qPrintable(url.host()));
        if (!userInitiated)
            return;
        if (url.scheme() == QLatin1String("intent")) {
            const QUrl fallback = intentFallback(url);
            if (fallback.isValid()) {
                QPointer<PacificWebView> view(self);
                // Not from inside WebKit's policy callback.
                QTimer::singleShot(0, self, [view, fallback] {
                    if (view && view->webView())
                        webkit_web_view_load_uri(view->webView(), fallback.toEncoded().constData());
                });
            }
            return;
        }
        QDesktopServices::openUrl(url);
    }

    static gboolean decidePolicy(WebKitWebView*, WebKitPolicyDecision* decision, WebKitPolicyDecisionType type,
        PacificWebView* self)
    {
        if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE) {
            auto* response = WEBKIT_RESPONSE_POLICY_DECISION(decision);
            if (webkit_response_policy_decision_is_main_frame_main_resource(response)
                && !webkit_response_policy_decision_is_mime_type_supported(response)) {
                webkit_policy_decision_download(decision);
                return TRUE;
            }
            return FALSE;
        }
        if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION || type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
            WebKitNavigationAction* action = webkit_navigation_policy_decision_get_navigation_action(WEBKIT_NAVIGATION_POLICY_DECISION(decision));
            WebKitURIRequest* uriRequest = webkit_navigation_action_get_request(action);
            const QUrl url(QString::fromUtf8(uriRequest ? webkit_uri_request_get_uri(uriRequest) : ""));
            if (!url.isEmpty() && !webKitLoads(url.scheme())) {
                webkit_policy_decision_ignore(decision);
                handOff(self, url, webkit_navigation_action_is_user_gesture(action));
                return TRUE;
            }
        }
        if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION
            || !self->isSignalConnected(QMetaMethod::fromSignal(&PacificWebView::navigationRequested)))
            return FALSE;
        NavigationRequest request(WEBKIT_NAVIGATION_POLICY_DECISION(decision));
        QQmlEngine::setObjectOwnership(&request, QQmlEngine::CppOwnership);
        Q_EMIT self->navigationRequested(&request);
        switch (request.action()) {
        case NavigationRequest::Accept:
            webkit_policy_decision_use(decision);
            break;
        case NavigationRequest::Ignore:
            webkit_policy_decision_ignore(decision);
            break;
        case NavigationRequest::Download:
            webkit_policy_decision_download(decision);
            break;
        }
        return TRUE;
    }

    static gboolean permission(WebKitWebView*, WebKitPermissionRequest* request, PacificWebView* self)
    {
        // Enumerating devices reveals only their kinds; WebKit then asks
        // again for real access.
        if (WEBKIT_IS_DEVICE_INFO_PERMISSION_REQUEST(request)) {
            webkit_permission_request_allow(request);
            return TRUE;
        }
        auto* wrapped = new PermissionRequest(request, self->url().adjusted(QUrl::RemovePath | QUrl::RemoveQuery | QUrl::RemoveFragment), self);
        QQmlEngine::setObjectOwnership(wrapped, QQmlEngine::CppOwnership);
        QObject::connect(wrapped, &PermissionRequest::answeredChanged, wrapped, &QObject::deleteLater);
        Q_EMIT self->permissionRequested(wrapped);
        return TRUE;
    }

    static gboolean scriptDialog(WebKitWebView*, WebKitScriptDialog* dialog, PacificWebView* self)
    {
        if (!self->isSignalConnected(QMetaMethod::fromSignal(&PacificWebView::scriptDialogRequested)))
            return FALSE;
        auto* wrapped = new ScriptDialog(dialog, self);
        QQmlEngine::setObjectOwnership(wrapped, QQmlEngine::CppOwnership);
        Q_EMIT self->scriptDialogRequested(wrapped);
        return TRUE;
    }

    static gboolean fileChooser(WebKitWebView*, WebKitFileChooserRequest* request, PacificWebView* self)
    {
        if (!self->isSignalConnected(QMetaMethod::fromSignal(&PacificWebView::fileChooserRequested)))
            return FALSE;
        auto* wrapped = new FileChooserRequest(request, self);
        QQmlEngine::setObjectOwnership(wrapped, QQmlEngine::CppOwnership);
        Q_EMIT self->fileChooserRequested(wrapped);
        return TRUE;
    }

    static gboolean authenticate(WebKitWebView*, WebKitAuthenticationRequest* request, PacificWebView* self)
    {
        if (!self->isSignalConnected(QMetaMethod::fromSignal(&PacificWebView::authenticationRequested)))
            return FALSE;
        auto* wrapped = new AuthenticationRequest(request, self);
        QQmlEngine::setObjectOwnership(wrapped, QQmlEngine::CppOwnership);
        Q_EMIT self->authenticationRequested(wrapped);
        return TRUE;
    }

    static gboolean notification(WebKitWebView*, WebKitNotification* notification, PacificWebView* self)
    {
        if (!self->isSignalConnected(QMetaMethod::fromSignal(&PacificWebView::notificationRequested)))
            return FALSE;
        Q_EMIT self->notificationRequested(QString::fromUtf8(webkit_notification_get_title(notification)),
            QString::fromUtf8(webkit_notification_get_body(notification)),
            QString::fromUtf8(webkit_notification_get_tag(notification)),
            self->url().adjusted(QUrl::RemovePath | QUrl::RemoveQuery | QUrl::RemoveFragment));
        return TRUE;
    }

    static void terminated(WebKitWebView*, WebKitWebProcessTerminationReason reason, PacificWebView* self)
    {
        self->m_terminated = true;
        self->setPageBlanked(false);
        PacificWebView::TerminationReason r = PacificWebView::Crashed;
        if (reason == WEBKIT_WEB_PROCESS_EXCEEDED_MEMORY_LIMIT)
            r = PacificWebView::ExceededMemoryLimit;
        else if (reason == WEBKIT_WEB_PROCESS_TERMINATED_BY_API)
            r = PacificWebView::TerminatedByApi;
        if (self->m_im.focused)
            self->setImState(ImState(), true);
        Q_EMIT self->webProcessRunningChanged();
        Q_EMIT self->webProcessTerminated(r);
    }

    static gboolean optionMenu(WebKitWebView*, WebKitOptionMenu* menu, WebKitRectangle* rect, PacificWebView* self)
    {
        if (!self->isSignalConnected(QMetaMethod::fromSignal(&PacificWebView::selectMenuRequested)))
            return FALSE;
        if (self->m_optionMenu)
            webkit_option_menu_close(self->m_optionMenu);
        g_clear_object(&self->m_optionMenu);
        self->m_optionMenu = WEBKIT_OPTION_MENU(g_object_ref(menu));
        g_signal_connect_swapped(menu, "close", G_CALLBACK(+[](PacificWebView* view) {
            g_clear_object(&view->m_optionMenu);
        }), self);
        QVariantList options;
        int selected = -1;
        const guint n = webkit_option_menu_get_n_items(menu);
        for (guint i = 0; i < n; ++i) {
            WebKitOptionMenuItem* item = webkit_option_menu_get_item(menu, i);
            QVariantMap option;
            option.insert(QStringLiteral("label"), QString::fromUtf8(webkit_option_menu_item_get_label(item)));
            option.insert(QStringLiteral("enabled"), static_cast<bool>(webkit_option_menu_item_is_enabled(item)));
            option.insert(QStringLiteral("groupLabel"), static_cast<bool>(webkit_option_menu_item_is_group_label(item)));
            option.insert(QStringLiteral("groupChild"), static_cast<bool>(webkit_option_menu_item_is_group_child(item)));
            if (webkit_option_menu_item_is_selected(item) && selected < 0)
                selected = static_cast<int>(i);
            options.append(option);
        }
        const QPointF topLeft = self->cssToItem(rect->x, rect->y);
        const QPointF bottomRight = self->cssToItem(rect->x + rect->width, rect->y + rect->height);
        Q_EMIT self->selectMenuRequested(options, selected, QRectF(topLeft, bottomRight));
        return TRUE;
    }

    static gboolean contextMenu(WebKitWebView*, WebKitContextMenu* menu, WebKitHitTestResult* hit, PacificWebView* self)
    {
        // A touch that caught a fling: no menu (TRUE: nor WebKit's).
        if (self->catchActive())
            return TRUE;
        QVariantMap info;
        if (webkit_hit_test_result_context_is_link(hit))
            info.insert(QStringLiteral("linkUrl"), QString::fromUtf8(webkit_hit_test_result_get_link_uri(hit)));
        if (webkit_hit_test_result_context_is_image(hit))
            info.insert(QStringLiteral("imageUrl"), QString::fromUtf8(webkit_hit_test_result_get_image_uri(hit)));
        if (webkit_hit_test_result_context_is_media(hit))
            info.insert(QStringLiteral("mediaUrl"), QString::fromUtf8(webkit_hit_test_result_get_media_uri(hit)));
        info.insert(QStringLiteral("editable"), static_cast<bool>(webkit_hit_test_result_context_is_editable(hit)));
        info.insert(QStringLiteral("selectionText"), self->m_selectedText);
        info.insert(QStringLiteral("pageUrl"), self->url().toString());
        info.insert(QStringLiteral("source"), QStringLiteral("native"));
        // Spelling: WebKit puts guesses for a misspelled word under the
        // pointer into the menu it built; keep the menu so the UI can pick one.
        QStringList suggestions;
        bool misspelled = false;
        for (GList* l = webkit_context_menu_get_items(menu); l; l = l->next) {
            auto* item = static_cast<WebKitContextMenuItem*>(l->data);
            switch (webkit_context_menu_item_get_stock_action(item)) {
            case WEBKIT_CONTEXT_MENU_ACTION_SPELLING_GUESS:
                suggestions.append(QString::fromUtf8(webkit_context_menu_item_get_title(item)));
                misspelled = true;
                break;
            case WEBKIT_CONTEXT_MENU_ACTION_NO_GUESSES_FOUND:
            case WEBKIT_CONTEXT_MENU_ACTION_LEARN_SPELLING:
            case WEBKIT_CONTEXT_MENU_ACTION_IGNORE_SPELLING:
                misspelled = true;
                break;
            default:
                break;
            }
        }
        info.insert(QStringLiteral("misspelled"), misspelled);
        info.insert(QStringLiteral("spellingSuggestions"), suggestions);
        self->m_spellingSuggestions = suggestions;
        self->m_misspelled = misspelled;
        if (self->m_contextMenu)
            g_object_unref(self->m_contextMenu);
        self->m_contextMenu = WEBKIT_CONTEXT_MENU(g_object_ref(menu));
        Q_EMIT self->contextMenuRequested(info);
        return TRUE; // WPE has no menu of its own to show
    }

    static void findCounted(WebKitFindController*, guint count, PacificWebView* self)
    {
        self->m_findMatchCount = static_cast<int>(count);
        Q_EMIT self->findMatchCountChanged();
        Q_EMIT self->findResult(self->m_findMatchCount);
    }

    static void findFailed(WebKitFindController*, PacificWebView* self)
    {
        self->m_findMatchCount = 0;
        Q_EMIT self->findMatchCountChanged();
        Q_EMIT self->findResult(0);
    }

    static gboolean userMessage(WebKitWebView*, WebKitUserMessage* message, PacificWebView* self)
    {
        if (g_strcmp0(webkit_user_message_get_name(message), "pacific.blocked") != 0)
            return FALSE;
        GVariant* parameters = webkit_user_message_get_parameters(message);
        if (!parameters || !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ss)")))
            return TRUE;
        const char* url = nullptr;
        const char* page = nullptr;
        g_variant_get(parameters, "(&s&s)", &url, &page);
        self->m_blockedRequestCount++;
        Q_EMIT self->blockedRequestCountChanged();
        Q_EMIT self->blockedRequest(QUrl(QString::fromUtf8(url)));
        return TRUE;
    }

    static void responsive(PacificWebView* self)
    {
        Q_EMIT self->webProcessUnresponsive(!webkit_web_view_get_is_web_process_responsive(self->m_webView));
    }
};

PacificWebView::PacificWebView(QQuickItem* parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    setFlag(ItemIsFocusScope, false);
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);
    setAcceptTouchEvents(true);
    setActiveFocusOnTab(true);
    m_hideTimer.setSingleShot(true);
    m_hideTimer.setInterval(200);
    connect(&m_hideTimer, &QTimer::timeout, this, [this] {
        // Still hidden after the grace period?
        QQuickWindow* win = window();
        const bool shown = !m_headless && win && isVisible() && win->isVisible() && win->isExposed() && applicationShown();
        if (!(m_active && shown))
            setPageVisible(false, false);
    });
    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, &PacificWebView::applyActivityState);
}

PacificWebView::~PacificWebView()
{
    if (m_optionMenu) {
        g_signal_handlers_disconnect_by_data(m_optionMenu, this);
        g_clear_object(&m_optionMenu);
    }
    if (m_contextMenu)
        g_clear_object(&m_contextMenu);
    if (m_consoleScript)
        webkit_user_script_unref(m_consoleScript);
    dropUserScripts();
    if (m_imContext) {
        ImContext::detach(m_imContext);
        g_clear_object(&m_imContext);
    }
    if (m_webView) {
        g_signal_handlers_disconnect_by_data(m_webView, this);
        if (WebKitBackForwardList* list = webkit_web_view_get_back_forward_list(m_webView))
            g_signal_handlers_disconnect_by_data(list, this);
        if (WebKitFindController* find = webkit_web_view_get_find_controller(m_webView))
            g_signal_handlers_disconnect_by_data(find, this);
        if (WebKitUserContentManager* ucm = webkit_web_view_get_user_content_manager(m_webView))
            g_signal_handlers_disconnect_by_data(ucm, this);
        if (m_profile)
            disconnect(m_profile, nullptr, this, nullptr);
        // Destroys the view backend (and ViewBackend) with it.
        g_object_unref(m_webView);
        m_webView = nullptr;
    }
}

// --- creation --------------------------------------------------------------

static EGLDisplay platformEglDisplay()
{
    QPlatformNativeInterface* native = QGuiApplication::platformNativeInterface();
    if (!native)
        return EGL_NO_DISPLAY;
    void* display = native->nativeResourceForIntegration(QByteArrayLiteral("egldisplay"));
    return display ? static_cast<EGLDisplay>(display) : EGL_NO_DISPLAY;
}

void PacificWebView::componentComplete()
{
    QQuickItem::componentComplete();
    m_completed = true;
    ensureWebView();
}

bool PacificWebView::ensureWebView(WebKitWebView* related)
{
    if (m_webView)
        return true;
    if (!m_completed)
        return false;
    if (!ViewBackend::displayInitialized() && !ViewBackend::initializeDisplay(platformEglDisplay())) {
        // Some platforms only expose the display once a window has a GL
        // context; itemChange() tries again then.
        return false;
    }

    auto* backend = new ViewBackend(physicalSize(), pageZoomScaling() ? 1.0 : effectiveContentScale(), this);
    backend->setItemToPhysical(itemToPhysical());
    backend->setHeadless(m_headless);
    m_backend = backend;
    WebKitWebViewBackend* viewBackend = webkit_web_view_backend_new(backend->backend(),
        [](gpointer data) { delete static_cast<ViewBackend*>(data); }, backend);

    WebKitSettings* settings = webkit_settings_new();
    for (const char* name : { "enable-developer-extras", "enable-webgl", "enable-mediasource", "enable-encrypted-media",
             "enable-media-stream", "enable-webrtc", "enable-back-forward-navigation-gestures", "enable-smooth-scrolling" }) {
        if (hasProperty(settings, name) && g_strcmp0(name, "enable-back-forward-navigation-gestures") != 0)
            g_object_set(settings, name, TRUE, nullptr);
    }
    if (hasProperty(settings, "javascript-can-open-windows-automatically"))
        g_object_set(settings, "javascript-can-open-windows-automatically", FALSE, nullptr);
    webkit_settings_set_user_agent(settings, m_userAgent.isEmpty() ? defaultUserAgent(m_desktopMode).toUtf8().constData()
                                                                   : m_userAgent.toUtf8().constData());

    if (related) {
        m_webView = WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "backend", viewBackend, "settings", settings,
            "related-view", related, nullptr));
    } else {
        WebProfile* profile = m_profile ? m_profile.data() : WebEngine::instance()->defaultProfile();
        m_profile = profile;
        m_webView = WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "backend", viewBackend, "settings", settings,
            "web-context", WebEngine::instance()->context(), "network-session", profile->session(), nullptr));
    }
    g_object_unref(settings);

    // libwpe drops dispatches made before a client is attached; this is the
    // first moment the scale can reach WebKit.
    backend->applyDeviceScale();

    m_imContext = ImContext::create(this);
    webkit_web_view_set_input_method_context(m_webView, m_imContext);

    connectWebView();
    installPageScripts();
    registerBridgeHandlers();
    ClipboardBridge::ensure();
    DeviceOrientationBridge::attach(m_webView);
    applyPendingState();
    applyActivityState();

    if (!related) {
        if (!m_url.isEmpty())
            webkit_web_view_load_uri(m_webView, m_url.toString().toUtf8().constData());
        else if (!m_html.isEmpty())
            webkit_web_view_load_html(m_webView, m_html.toUtf8().constData(), m_baseUrl.toString().toUtf8().constData());
    }
    Q_EMIT webViewCreated();
    Q_EMIT profileChanged();
    return true;
}

bool PacificWebView::createRelatedWebView(PacificWebView* opener)
{
    if (m_webView || !opener || !opener->m_webView)
        return false;
    m_completed = true; // created from a handler, possibly before componentComplete
    m_profile = opener->m_profile;
    return ensureWebView(opener->m_webView);
}

void PacificWebView::connectWebView()
{
    using C = PacificWebViewCallbacks;
    g_signal_connect_swapped(m_webView, "notify::uri", G_CALLBACK(C::uriChanged), this);
    g_signal_connect_swapped(m_webView, "notify::title", G_CALLBACK(+[](PacificWebView* v) { Q_EMIT v->titleChanged(); }), this);
    g_signal_connect_swapped(m_webView, "notify::estimated-load-progress",
        G_CALLBACK(+[](PacificWebView* v) { Q_EMIT v->loadProgressChanged(); }), this);
    g_signal_connect_swapped(m_webView, "notify::is-loading",
        G_CALLBACK(+[](PacificWebView* v) { Q_EMIT v->loadingStateChanged(); }), this);
    g_signal_connect_swapped(m_webView, "notify::is-playing-audio",
        G_CALLBACK(+[](PacificWebView* v) { Q_EMIT v->audioChanged(); }), this);
    g_signal_connect_swapped(m_webView, "notify::is-muted", G_CALLBACK(+[](PacificWebView* v) { Q_EMIT v->audioChanged(); }), this);
    g_signal_connect_swapped(m_webView, "notify::is-web-process-responsive", G_CALLBACK(C::responsive), this);
    g_signal_connect(m_webView, "load-changed", G_CALLBACK(C::loadChanged), this);
    g_signal_connect(m_webView, "load-failed", G_CALLBACK(C::loadFailed), this);
    g_signal_connect(m_webView, "load-failed-with-tls-errors", G_CALLBACK(C::tlsFailed), this);
    g_signal_connect_swapped(m_webView, "insecure-content-detected", G_CALLBACK(+[](PacificWebView* v) {
        if (v->m_secure) {
            v->m_secure = false;
            Q_EMIT v->securityChanged();
        }
    }), this);
    g_signal_connect(m_webView, "create", G_CALLBACK(C::create), this);
    // Requests blocked by the profile's content filters, reported by
    // Pacific's WebProcess extension (src/webprocess/extension.c).
    g_signal_connect(m_webView, "user-message-received", G_CALLBACK(C::userMessage), this);
    g_signal_connect_swapped(m_webView, "close", G_CALLBACK(+[](PacificWebView* v) { Q_EMIT v->closeRequested(); }), this);
    g_signal_connect(m_webView, "decide-policy", G_CALLBACK(C::decidePolicy), this);
    g_signal_connect(m_webView, "permission-request", G_CALLBACK(C::permission), this);
    g_signal_connect(m_webView, "script-dialog", G_CALLBACK(C::scriptDialog), this);
    g_signal_connect(m_webView, "run-file-chooser", G_CALLBACK(C::fileChooser), this);
    g_signal_connect(m_webView, "authenticate", G_CALLBACK(C::authenticate), this);
    g_signal_connect(m_webView, "show-notification", G_CALLBACK(C::notification), this);
    g_signal_connect(m_webView, "web-process-terminated", G_CALLBACK(C::terminated), this);
    g_signal_connect(m_webView, "show-option-menu", G_CALLBACK(C::optionMenu), this);
    g_signal_connect(m_webView, "context-menu", G_CALLBACK(C::contextMenu), this);

    // Same-document navigations (pushState) change the history without a
    // load; the list's own signal catches them (Atlantic).
    if (WebKitBackForwardList* list = webkit_web_view_get_back_forward_list(m_webView))
        g_signal_connect_swapped(list, "changed", G_CALLBACK(+[](PacificWebView* v) { Q_EMIT v->backForwardChanged(); }), this);

    WebKitFindController* find = webkit_web_view_get_find_controller(m_webView);
    g_signal_connect(find, "counted-matches", G_CALLBACK(C::findCounted), this);
    // Only counted-matches has the total: a search's found-text says
    // G_MAXUINT (not counted) and a step to the next match says 1, which
    // overwrote it.
    g_signal_connect(find, "failed-to-find-text", G_CALLBACK(C::findFailed), this);

    if (m_profile) {
        connect(m_profile, &WebProfile::downloadStarted, this, [this](Download* download) {
            if (download->webView() == m_webView)
                Q_EMIT downloadRequested(download);
        });
        WebKitUserContentManager* ucm = webkit_web_view_get_user_content_manager(m_webView);
        const auto filters = m_profile->filters();
        for (WebKitUserContentFilter* filter : filters)
            webkit_user_content_manager_add_filter(ucm, filter);
        connect(m_profile, &WebProfile::contentFilterAdded, this, [this](const QString& id) {
            if (WebKitUserContentFilter* filter = m_profile->filters().value(id))
                webkit_user_content_manager_add_filter(webkit_web_view_get_user_content_manager(m_webView), filter);
        });
        connect(m_profile, &WebProfile::globalPrivacyControlChanged, this, &PacificWebView::applyGlobalPrivacyControl);
        connect(m_profile, &WebProfile::contentFilterRemoved, this, [this](const QString& id) {
            webkit_user_content_manager_remove_filter_by_id(webkit_web_view_get_user_content_manager(m_webView),
                id.toUtf8().constData());
        });
    }

    // WPE ships these runtime preferences off (GTK and Cocoa have them on):
    // hidden-page timer throttling and animation suspension, so background
    // tabs stop burning CPU; WebRTC (compiled in); and the HTML5 date, time
    // and colour input types, which otherwise degrade to text (Atlantic).
    WebKitSettings* settings = webkit_web_view_get_settings(m_webView);
    WebKitFeatureList* features = webkit_settings_get_all_features();
    const gsize count = webkit_feature_list_get_length(features);
    for (gsize i = 0; i < count; ++i) {
        WebKitFeature* feature = webkit_feature_list_get(features, i);
        const char* id = webkit_feature_get_identifier(feature);
        for (const char* wanted : { "HiddenPageDOMTimerThrottling", "HiddenPageCSSAnimationSuspension",
                 "PeerConnection", "MediaDevices", "InputTypeDate", "InputTypeDateTimeLocal", "InputTypeMonth",
                 "InputTypeWeek", "InputTypeTime", "InputTypeColor" }) {
            if (!g_strcmp0(id, wanted))
                webkit_settings_set_feature_enabled(settings, feature, TRUE);
        }
    }
    webkit_feature_list_unref(features);
    applyGlobalPrivacyControl();
}

void PacificWebView::applyGlobalPrivacyControl()
{
    // WebKit's own Global Privacy Control: Sec-GPC: 1 on every request and
    // navigator.globalPrivacyControl === true, from the profile's setting.
    if (m_webView && m_profile)
        setFeatureEnabled(QStringLiteral("GlobalPrivacyControl"), m_profile->globalPrivacyControl());
}

// One "script-message-received::<name>" connection per handler name, carrying
// the name with it.
struct ScriptMessageClosure {
    QPointer<PacificWebView> view;
    QByteArray name;
};

static void onScriptMessage(WebKitUserContentManager*, JSCValue* value, ScriptMessageClosure* closure)
{
    if (closure->view)
        closure->view->handleScriptMessagePublic(closure->name.constData(), value);
}

void PacificWebView::handleScriptMessagePublic(const char* name, JSCValue* value)
{
    handleScriptMessage(name, value);
}

static void connectScriptMessage(WebKitUserContentManager* ucm, PacificWebView* view, const char* name)
{
    const QByteArray detailed = QByteArray("script-message-received::") + name;
    auto* closure = new ScriptMessageClosure { view, name };
    g_signal_connect_data(ucm, detailed.constData(), G_CALLBACK(onScriptMessage), closure,
        [](gpointer data, GClosure*) { delete static_cast<ScriptMessageClosure*>(data); }, GConnectFlags(0));
}

void PacificWebView::installPageScripts()
{
    WebKitUserContentManager* ucm = webkit_web_view_get_user_content_manager(m_webView);
    // Pacific's bridges run in their own script world: same DOM, separate
    // JavaScript globals, invisible to the page.
    static const struct {
        const char* file;
        bool allFrames;
        WebKitUserScriptInjectionTime time;
    } scripts[] = {
        { "selection.js", false, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END },
        { "pickers.js", true, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START },
        { "scroll.js", false, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START },
        { "page-info.js", false, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START },
        { "ime-fallback.js", true, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START },
        { "agent.js", false, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START },
    };
    for (const auto& s : scripts) {
        const QString source = loadScript(s.file);
        if (source.isEmpty())
            continue;
        WebKitUserScript* script = webkit_user_script_new_for_world(source.toUtf8().constData(),
            s.allFrames ? WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES : WEBKIT_USER_CONTENT_INJECT_TOP_FRAME, s.time, kWorld,
            nullptr, nullptr);
        webkit_user_content_manager_add_script(ucm, script);
        webkit_user_script_unref(script);
    }
    if (m_scriptSelectMenus) {
        WebKitUserScript* flag = webkit_user_script_new_for_world("window.__pacificScriptSelect = true;",
            WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, kWorld, nullptr, nullptr);
        webkit_user_content_manager_add_script(ucm, flag);
        webkit_user_script_unref(flag);
    }
    // (Re)installed with the rest: removeUserContent() took it out too.
    if (m_consoleScript) {
        webkit_user_script_unref(m_consoleScript);
        m_consoleScript = nullptr;
    }
    if (m_captureConsole)
        installConsoleCapture();
}

// Console capture costs every page a wrapped console and a message per call,
// so it is only there while captureConsole is on: the handler is registered
// the first time, the script is added now and removed when it goes off.
void PacificWebView::installConsoleCapture()
{
    WebKitUserContentManager* ucm = webkit_web_view_get_user_content_manager(m_webView);
    if (!m_consoleHandler) {
        webkit_user_content_manager_register_script_message_handler(ucm, "pacificConsole", nullptr);
        connectScriptMessage(ucm, this, "pacificConsole");
        m_consoleHandler = true;
    }
    if (m_consoleScript)
        return;
    const QString source = loadScript("console.js");
    m_consoleScript = webkit_user_script_new(source.toUtf8().constData(), WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
    webkit_user_content_manager_add_script(ucm, m_consoleScript);
}

void PacificWebView::removeConsoleCapture()
{
    if (!m_consoleScript)
        return;
    webkit_user_content_manager_remove_script(webkit_web_view_get_user_content_manager(m_webView), m_consoleScript);
    webkit_user_script_unref(m_consoleScript);
    m_consoleScript = nullptr;
}

void PacificWebView::registerBridgeHandlers()
{
    WebKitUserContentManager* ucm = webkit_web_view_get_user_content_manager(m_webView);
    for (const char* name : { "pacificSelection", "pacificContext", "pacificSelect", "pacificPicker", "pacificScroll",
             "pacificPinch", "pacificPageInfo", "pacificPrefetch", "pacificPull", "pacificSwipe", "pacificPainted" }) {
        webkit_user_content_manager_register_script_message_handler(ucm, name, kWorld);
        connectScriptMessage(ucm, this, name);
    }
}

void PacificWebView::applyPendingState()
{
    if (pageZoomScaling() || !qFuzzyCompare(pageZoom(), 1.0))
        applyZoom();
    if (m_muted)
        webkit_web_view_set_is_muted(m_webView, TRUE);
    const QVariantMap pending = std::exchange(m_pendingSettings, {});
    for (auto it = pending.cbegin(); it != pending.cend(); ++it)
        setSetting(it.key(), it.value());
}

void PacificWebView::handleScriptMessage(const char* name, JSCValue* value)
{
    const QVariant message = jscToVariant(value);
    const QVariantMap map = message.toMap();
    const QByteArray n(name);
    if (n == "pacificSelection") {
        if (catchActive() && map.value(QStringLiteral("type")).toString() == QLatin1String("select")) {
            if (qEnvironmentVariableIsSet("PACIFIC_DEBUG_CATCH"))
                qInfo("Pacific catch: selection dropped");
            // The touch caught a fling: no long press.
            clearSelection();
            return;
        }
        if (map.value(QStringLiteral("type")).toString() == QLatin1String("select")) {
            if (qEnvironmentVariableIsSet("PACIFIC_DEBUG_CATCH"))
                qInfo("Pacific catch: selection shown");
            m_selectedText = map.value(QStringLiteral("text")).toString();
            Q_EMIT selectionHandlesChanged(
                cssToItem(map.value(QStringLiteral("startX")).toReal(), map.value(QStringLiteral("startY")).toReal()),
                cssToItem(map.value(QStringLiteral("endX")).toReal(), map.value(QStringLiteral("endY")).toReal()));
        } else {
            m_selectedText.clear();
        }
        Q_EMIT selectionChanged();
    } else if (n == "pacificContext") {
        if (catchActive())
            return;
        QVariantMap info = map;
        const QPointF p = cssToItem(map.value(QStringLiteral("x")).toReal(), map.value(QStringLiteral("y")).toReal());
        info.insert(QStringLiteral("x"), p.x());
        info.insert(QStringLiteral("y"), p.y());
        info.insert(QStringLiteral("source"), QStringLiteral("page"));
        Q_EMIT contextMenuRequested(info);
    } else if (n == "pacificSelect" || n == "pacificPicker") {
        const QVariantMap r = map.value(QStringLiteral("rect")).toMap();
        const qreal x = r.value(QStringLiteral("x")).toReal();
        const qreal y = r.value(QStringLiteral("y")).toReal();
        const QRectF rect(cssToItem(x, y),
            cssToItem(x + r.value(QStringLiteral("width")).toReal(), y + r.value(QStringLiteral("height")).toReal()));
        if (n == "pacificSelect") {
            Q_EMIT selectMenuRequested(map.value(QStringLiteral("options")).toList(),
                map.value(QStringLiteral("selectedIndex")).toInt(), rect);
        } else {
            Q_EMIT inputPickerRequested(map.value(QStringLiteral("type")).toString(),
                map.value(QStringLiteral("value")).toString(), map.value(QStringLiteral("min")).toString(),
                map.value(QStringLiteral("max")).toString(), map.value(QStringLiteral("step")).toString(), rect);
        }
    } else if (n == "pacificPull") {
        // scroll.js, for the touch now down: at the top and pullable, or the
        // page took the drag (preventDefault on touchmove).
        if (map.value(QStringLiteral("consumed")).toBool()) {
            m_refreshPull.verdict = PullVerdict::No;
            endRefreshPull();
        } else if (m_refreshPull.verdict == PullVerdict::Unknown) {
            m_refreshPull.verdict = map.value(QStringLiteral("pullable")).toBool() && !pageZoomedIn()
                ? PullVerdict::Yes : PullVerdict::No;
        }
    } else if (n == "pacificSwipe") {
        // scroll.js, for the touch now down: whether the page under the
        // finger can scroll any further left or right; or that it took the
        // drag itself.
        if (map.value(QStringLiteral("consumed")).toBool()) {
            if (m_swipeNav.state == SwipeState::Undecided)
                m_swipeNav.state = SwipeState::No;
        } else if (!m_swipeNav.pageAnswered) {
            m_swipeNav.pageAnswered = true;
            m_swipeNav.back = map.value(QStringLiteral("back")).toBool();
            m_swipeNav.forward = map.value(QStringLiteral("forward")).toBool();
        }
    } else if (n == "pacificScroll") {
        requestBoost(600);
        // The page scrolled after all: no pull.
        if (m_refreshPull.active && map.value(QStringLiteral("scrollY")).toReal() > 0.5) {
            m_refreshPull.verdict = PullVerdict::No;
            endRefreshPull();
        }
        const qreal factor = cssToItem(1, 0).x() - cssToItem(0, 0).x();
        Q_EMIT scrollChanged(map.value(QStringLiteral("scrollY")).toReal() * factor,
            map.value(QStringLiteral("scrollHeight")).toReal() * factor,
            map.value(QStringLiteral("innerHeight")).toReal() * factor);
    } else if (n == "pacificPrefetch") {
        // A finger came down on a link to another site (scroll.js): its
        // name is resolved while the tap finishes, a 100-300 ms head start
        // on the lookup the load would start with.
        const QString host = map.value(QStringLiteral("host")).toString();
        if (m_profile && !host.isEmpty() && host.size() < 254 && !host.contains(QLatin1Char('/')))
            m_profile->prefetchDns(host);
    } else if (n == "pacificPinch") {
        m_pinch.pageConsumes = map.value(QStringLiteral("consumed")).toBool();
        Q_EMIT pinchConsumedByPage(m_pinch.pageConsumes);
    } else if (n == "pacificPainted") {
        // The new document has painted: the page being left goes with the
        // next frame that reaches the view (this message can arrive before
        // it, and the frame on screen then was still the old document's),
        // or after a second if none comes (the first frame of a Wikipedia
        // article reached the view 300-450 ms after this message).
        if (m_pageCommitted) {
            m_loadTrace.mark("painted");
            endPageChangeOnNextFrame();
        }
    } else if (n == "pacificPageInfo") {
        // Prefer an explicit large icon (touch icons are 180 px), then any.
        QUrl best;
        int bestScore = -1;
        const QVariantList icons = map.value(QStringLiteral("icons")).toList();
        for (const QVariant& v : icons) {
            const QVariantMap icon = v.toMap();
            const QString rel = icon.value(QStringLiteral("rel")).toString();
            const QString sizes = icon.value(QStringLiteral("sizes")).toString();
            int score = rel.contains(QLatin1String("apple-touch")) ? 180 : 32;
            if (!sizes.isEmpty() && sizes != QLatin1String("any"))
                score = sizes.section(QLatin1Char('x'), 0, 0).toInt();
            if (sizes == QLatin1String("any") || icon.value(QStringLiteral("href")).toString().endsWith(QLatin1String(".svg")))
                score = 256;
            if (score > 512)
                score = 512 - score / 100; // oversized icons are slow to decode
            if (score > bestScore) {
                bestScore = score;
                best = QUrl(icon.value(QStringLiteral("href")).toString());
            }
        }
        setIcon(best, map.value(QStringLiteral("themeColor")).toString());
        // WPE has no meta viewport support (ENABLE_META_VIEWPORT is off), so
        // the page is laid out at the view's own width. As a phone browser
        // does, lay out at the width the page asks for (or 980 CSS px when
        // it has no viewport tag) and scale it down to fit: page zoom does
        // both at once.
        setViewportFitCover(map.value(QStringLiteral("viewportFitCover")).toBool());
        if (map.contains(QStringLiteral("viewportWidth"))) {
            const qreal wanted = map.value(QStringLiteral("viewportWidth")).toReal();
            const qreal viewCss = map.value(QStringLiteral("viewWidth")).toReal() * pageZoom();
            setFitScale(wanted > 0 && viewCss > 0 ? viewCss / wanted : 1.0);
        }
    } else if (n == "pacificConsole") {
        // A page loaded while capture was on can still post.
        if (!m_captureConsole)
            return;
        Q_EMIT consoleMessage(map.value(QStringLiteral("level")).toString(), map.value(QStringLiteral("message")).toString(),
            map.value(QStringLiteral("source")).toString());
    } else {
        Q_EMIT scriptMessage(QString::fromUtf8(name), message);
    }
}

void PacificWebView::setViewportFitCover(bool cover)
{
    if (cover == m_viewportFitCover)
        return;
    m_viewportFitCover = cover;
    Q_EMIT viewportFitCoverChanged();
}

void PacificWebView::setSafeAreaTop(qreal top)
{
    if (qFuzzyCompare(top + 1, m_safeAreaTop + 1))
        return;
    m_safeAreaTop = top;
    applySafeArea();
    Q_EMIT safeAreaTopChanged();
}

// env(safe-area-inset-top) in CSS px, through the engine's
// wpe_sfos_set_safe_area_insets (absent: pages see 0, as before).
void PacificWebView::applySafeArea()
{
    using SetInsetsFn = void (*)(WebKitWebView*, double, double, double, double);
    static const auto setInsets = reinterpret_cast<SetInsetsFn>(engineSymbol("wpe_sfos_set_safe_area_insets"));
    if (!m_webView || !setInsets)
        return;
    const qreal itemPerCss = cssToItem(1, 0).x() - cssToItem(0, 0).x();
    setInsets(m_webView, itemPerCss > 0 ? m_safeAreaTop / itemPerCss : 0, 0, 0, 0);
}

void PacificWebView::setObscuredBottom(qreal bottom)
{
    bottom = qMax<qreal>(0, bottom);
    if (qFuzzyCompare(bottom + 1, m_obscuredBottom + 1))
        return;
    m_obscuredBottom = bottom;
    applyObscured();
    Q_EMIT obscuredBottomChanged();
}

// In CSS px, through the engine's wpe_sfos_set_obscured_content_insets
// (absent: fixed elements stay under the UI's controls, as before). The
// engine keeps them across web processes.
void PacificWebView::applyObscured()
{
    using SetInsetsFn = void (*)(WebKitWebView*, double, double, double, double);
    static const auto setInsets
        = reinterpret_cast<SetInsetsFn>(engineSymbol("wpe_sfos_set_obscured_content_insets"));
    if (!m_webView || !setInsets)
        return;
    const qreal itemPerCss = cssToItem(1, 0).x() - cssToItem(0, 0).x();
    setInsets(m_webView, 0, 0, itemPerCss > 0 ? m_obscuredBottom / itemPerCss : 0, 0);
}

void PacificWebView::setIcon(const QUrl& icon, const QString& themeColor)
{
    if (icon == m_icon && themeColor == m_themeColor)
        return;
    m_icon = icon;
    m_themeColor = themeColor;
    Q_EMIT iconChanged();
}

void PacificWebView::updateSecurity()
{
    GTlsCertificate* certificate = nullptr;
    GTlsCertificateFlags errors = G_TLS_CERTIFICATE_NO_FLAGS;
    const bool https = url().scheme() == QLatin1String("https");
    const bool secure = https && webkit_web_view_get_tls_info(m_webView, &certificate, &errors) && errors == 0;
    if (secure != m_secure) {
        m_secure = secure;
        Q_EMIT securityChanged();
    }
}

// --- geometry, window, painting ---------------------------------------------

qreal PacificWebView::itemToPhysical() const
{
    return window() ? window()->effectiveDevicePixelRatio() : 1.0;
}

qreal PacificWebView::effectiveContentScale() const
{
    if (m_contentScale > 0)
        return m_contentScale;
    const QScreen* screen = window() ? window()->screen() : QGuiApplication::primaryScreen();
    // With Qt's high-DPI scaling on (desktops), a Qt logical pixel is
    // already a CSS pixel: the scale is the device pixel ratio, and the page
    // is as wide in CSS px as the item is in Qt px.
    const qreal ratio = window() ? window()->effectiveDevicePixelRatio() : (screen ? screen->devicePixelRatio() : 1.0);
    if (ratio > 1.0)
        return ratio;
    // Sailfish OS runs Qt at ratio 1: a CSS pixel is 1/160 inch, as on
    // phones, rounded to a quarter step.
    const qreal dpi = screen ? screen->physicalDotsPerInch() : 160.0;
    const qreal scale = std::round(dpi / 160.0 * 4.0) / 4.0;
    return qBound(1.0, scale, 4.0);
}

qreal PacificWebView::contentScale() const
{
    return effectiveContentScale();
}

QSize PacificWebView::physicalSize() const
{
    QSizeF size(width(), height());
    if (size.isEmpty()) {
        // Off screen and unsized (Pilot's background tabs): a phone viewport.
        const qreal scale = effectiveContentScale();
        return { qRound(412 * scale), qRound(915 * scale) };
    }
    const qreal ratio = itemToPhysical();
    return { qRound(size.width() * ratio), qRound(size.height() * ratio) };
}

QPointF PacificWebView::cssToItem(qreal x, qreal y) const
{
    const qreal factor = effectiveContentScale() * pageZoom() / itemToPhysical();
    return { x * factor, y * factor };
}

void PacificWebView::updatePolish()
{
    QQuickItem::updatePolish();
    if (m_geometryPending) {
        m_geometryPending = false;
        updateBackendGeometry();
    }
}

void PacificWebView::updateBackendGeometry()
{
    if (!m_backend)
        return;
    if (qEnvironmentVariableIsSet("PACIFIC_DEBUG_ACTIVITY")) {
        const QSize size = physicalSize();
        qInfo("Pacific WebView %p: geometry item %gx%g, physical %dx%d, scale %g", static_cast<void*>(this), width(), height(),
            size.width(), size.height(), effectiveContentScale());
    }
    m_backend->setItemToPhysical(itemToPhysical());
    if (!pageZoomScaling())
        m_backend->setDeviceScale(effectiveContentScale());
    m_backend->resize(physicalSize());
    updateDirect();
}

void PacificWebView::setDirectComposite(bool direct)
{
    if (direct == m_directComposite)
        return;
    m_directComposite = direct;
    updateDirect();
    Q_EMIT directCompositeChanged();
}

void PacificWebView::updateDirect()
{
    if (!m_backend)
        return;
    QQuickWindow* win = window();
    const bool wanted = m_directComposite && m_pageVisible && win && !m_headless && isVisible()
        && !m_pinch.active && !m_pinch.committing;
    const QPointF origin = mapToScene(QPointF(0, 0));
    m_backend->setDirect(wanted, win, QRect(QPoint(qRound(origin.x()), qRound(origin.y())), physicalSize()));
}

void PacificWebView::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    updateFrameFits();
    if (newGeometry.size() == oldGeometry.size()) {
        updateDirect();
        return;
    }
    // WebKit gets the size Qt is about to render at (updatePolish): a window
    // passes through provisional sizes on its way to full screen (500x338 at
    // start, briefly), and each one would cost WebKit a layout and a frame.
    m_geometryPending = true;
    polish();
    // Keyboard reflow: when the view shrinks under an open keyboard, bring the
    // focused field back into sight once WebKit has the new size.
    if (m_im.focused && newGeometry.height() < oldGeometry.height()) {
        QTimer::singleShot(120, this, [this] {
            evaluate(QStringLiteral("(function(){var a=document.activeElement;"
                                    "if(a&&a.scrollIntoView)a.scrollIntoView({block:'center',inline:'nearest'});})()"),
                kWorld, QJSValue());
        });
    }
}

void PacificWebView::itemChange(ItemChange change, const ItemChangeData& value)
{
    QQuickItem::itemChange(change, value);
    if (change == ItemSceneChange) {
        QQuickWindow* win = value.window;
        if (win) {
            if (win->rendererInterface()->graphicsApi() != QSGRendererInterface::OpenGL
                && win->rendererInterface()->graphicsApi() != QSGRendererInterface::Unknown) {
                qWarning("Pacific WebView: Qt Quick is not on the OpenGL RHI; call "
                         "QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL) before creating windows");
            }
            connect(win, &QQuickWindow::frameSwapped, this, &PacificWebView::onFrameSwapped, Qt::UniqueConnection);
            connect(win, &QQuickWindow::sceneGraphInitialized, this, &PacificWebView::onSceneGraphInitialized,
                Qt::QueuedConnection);
            connect(win, &QWindow::screenChanged, this, &PacificWebView::updateBackendGeometry, Qt::UniqueConnection);
            connect(win, &QWindow::visibilityChanged, this, &PacificWebView::applyActivityState, Qt::UniqueConnection);
            connect(win, &QWindow::activeChanged, this, &PacificWebView::applyActivityState, Qt::UniqueConnection);
            win->installEventFilter(this);
        }
        if (!m_webView)
            ensureWebView();
        m_geometryPending = true;
        polish();
        applyActivityState();
    } else if (change == ItemVisibleHasChanged) {
        applyActivityState();
        if (value.boolValue && m_backend)
            m_backend->redraw();
    }
}

void PacificWebView::applyActivityState()
{
    if (!m_backend)
        return;
    QQuickWindow* win = window();
    // The page is visible when this is the foreground tab (active), the item
    // is effectively visible in an exposed window, and the app is on screen.
    // The application state is handled here: bind active to "this tab is in
    // front" only.
    const bool shown = !m_headless && win && isVisible() && win->isVisible() && win->isExposed() && applicationShown();
    const bool visible = m_active && shown;
    const bool focused = visible && (QGuiApplication::applicationState() == Qt::ApplicationActive || win->isActive());
    if (qEnvironmentVariableIsSet("PACIFIC_DEBUG_ACTIVITY")) {
        qInfo("Pacific WebView %p: active=%d headless=%d window=%d item visible=%d window visible=%d exposed=%d app state=%d -> visible=%d focused=%d (%s)",
            static_cast<void*>(this), m_active, m_headless, win != nullptr, isVisible(), win ? win->isVisible() : 0,
            win ? win->isExposed() : 0, static_cast<int>(QGuiApplication::applicationState()), visible, focused,
            qPrintable(url().toString().left(80)));
    }
    m_backend->setHeadless(m_headless || !win);
    if (!visible && m_pageVisible) {
        // Hiding waits a moment: page transitions hide and show the item
        // within a few frames, and every flip would stop and restart the
        // page's animations and timers.
        if (!m_hideTimer.isActive())
            m_hideTimer.start();
        return;
    }
    m_hideTimer.stop();
    setPageVisible(visible, focused);
}

void PacificWebView::setPageVisible(bool visible, bool focused)
{
    if (m_backend) {
        m_backend->setActivityState(visible, focused);
        // Draw the frame kept while hidden right away.
        if (visible && !m_pageVisible)
            m_backend->redraw();
    }
    if (visible != m_pageVisible) {
        m_pageVisible = visible;
        updateDirect();
        Q_EMIT pageVisibleChanged();
    }
}

QSGNode* PacificWebView::updatePaintNode(QSGNode* node, UpdatePaintNodeData*)
{
    if (!m_backend || m_headless)
        return node;
    QOpenGLContext* context = QOpenGLContext::currentContext();
    if (!context) {
        static bool warned = false;
        if (!warned) {
            warned = true;
            qWarning("Pacific WebView: no current OpenGL context in the scene graph; the OpenGL RHI is required");
        }
        return node;
    }
    if (!ViewBackend::displayInitialized())
        return node;

    // Software frames (wl_shm): Qt uploads the copied pixels itself.
    QImage shmFrame;
    if (m_backend->takeShmFrame(&shmFrame)) {
        auto* textureNode = static_cast<QSGSimpleTextureNode*>(node);
        if (!textureNode) {
            textureNode = new QSGSimpleTextureNode();
            textureNode->setOwnsTexture(true);
            textureNode->setFiltering(QSGTexture::Linear);
        }
        textureNode->setTexture(window()->createTextureFromImage(shmFrame));
        m_nodeHasShmTexture = true;
        const QRectF item = boundingRect();
        const qreal scale = item.width() / shmFrame.width();
        textureNode->setRect(QRectF(0, 0, item.width(), shmFrame.height() * scale));
        return textureNode;
    }
    if (m_backend->hasShmFrame())
        return node; // the last software frame is still on screen

    // Before texture() moves on to newer frames: the frame on screen now is
    // the one the pinch scaled.
    if (m_pinch.snapshotWanted) {
        m_pinch.snapshotWanted = false;
        takePinchSnapshot(context);
    }
    const unsigned textureId = m_backend->texture(context);
    if (!textureId)
        return node;

    auto* textureNode = static_cast<QSGSimpleTextureNode*>(node);
    if (!textureNode) {
        textureNode = new QSGSimpleTextureNode();
        textureNode->setOwnsTexture(true);
        textureNode->setFiltering(QSGTexture::Linear);
    }
    const QSize frameSize = m_backend->currentImageSize();
    // Nothing until WebKit has drawn at the view's width once: a first frame
    // at another size would show as a band across the top. Within a device
    // pixel per unit of scale: at a scale that does not divide the width
    // (1.75 at 270 DPI: 720 px is 411 CSS px, drawn 719 px wide) WebKit's
    // frames never match exactly, and the view stayed blank (reported from
    // Marathon OS; the Jolla Phone's scale divides evenly).
    if (!m_sizedFrameSeen) {
        const int slack = qMax(1, static_cast<int>(std::ceil(effectiveContentScale())));
        if (frameSize.isEmpty() || std::abs(frameSize.width() - physicalSize().width()) > slack)
            return node;
        m_sizedFrameSeen = true;
    }
    const QSize textureSize = frameSize.isEmpty() ? physicalSize() : frameSize;
    QSGTexture* texture = textureNode->texture();
    // A wrapper (no GPU work) per texture: the backend keeps one per frame
    // buffer, so it changes as WebKit cycles through them. Opaque: WebKit
    // fills every frame (the page's background, white by default), and a
    // blended full-screen quad cost fill rate on every Qt frame.
    if (!texture || texture->textureSize() != textureSize || m_nodeHasShmTexture
        || m_wrappedTextureId != textureId) {
        m_nodeHasShmTexture = false;
        texture = QNativeInterface::QSGOpenGLTexture::fromNative(textureId, window(), textureSize);
        textureNode->setTexture(texture);
        m_wrappedTextureId = textureId;
    }
    const QRectF item = boundingRect();
    if (frameSize.isEmpty() || frameSize.width() <= 0) {
        textureNode->setRect(item);
    } else {
        // Between a resize and the first frame at the new size, draw the old
        // frame at its own aspect, top-anchored, instead of stretching it
        // (Atlantic's WEBKIT_ANCHOR_STALE_FRAME). In steady state this is
        // exactly boundingRect().
        const qreal scale = item.width() / frameSize.width();
        textureNode->setRect(QRectF(0, 0, item.width(), frameSize.height() * scale));
    }
    // The frame at the pinch's new scale is the one drawn now: the preview
    // ends here, in this same render pass.
    if (m_pinch.committing && !m_pinch.showFinal && m_backend->committedSerial() >= m_pinch.awaitSerial) {
        m_pinch.showFinal = true;
        QMetaObject::invokeMethod(this, &PacificWebView::endPinchVisual, Qt::QueuedConnection);
    }
    // After the fingers lift, until the frame at the new scale: the
    // snapshot of the frame they left, scaled; the live frames stay hidden.
    const bool frozen = m_pinch.committing && !m_pinch.showFinal && m_pinch.haveSnapshot && m_snapshotSg;
    // While they are down (or after, with no snapshot): the live frame
    // scaled about where the pinch began and moved with the fingers since.
    const bool scaling = !qFuzzyCompare(m_pinch.visual, 1.0) && !frozen
        && (m_pinch.active || (m_pinch.committing && !m_pinch.showFinal));
    auto pinchRect = [this](const QRectF& r) {
        const QPointF c = m_pinch.center;
        const qreal v = m_pinch.visual;
        return QRectF(c + (r.topLeft() - c) * v + pinchPan(), r.size() * v);
    };
    static const bool debugPinch = qEnvironmentVariableIsSet("PACIFIC_DEBUG_PINCH");
    if (debugPinch && (m_pinch.committing || m_pinch.showFinal))
        qInfo("Pacific pinch draw: snapshot %d scaled %d final %d frame %llu awaiting %llu at %lld ms", frozen, scaling,
            m_pinch.showFinal, static_cast<unsigned long long>(m_backend->committedSerial()),
            static_cast<unsigned long long>(m_pinch.awaitSerial), static_cast<long long>(m_pinch.committed.elapsed()));
    if (scaling)
        textureNode->setRect(pinchRect(textureNode->rect()));
    if (frozen) {
        while (textureNode->childCount() && textureNode->firstChild() != m_snapshotNode) {
            QSGNode* child = textureNode->firstChild();
            textureNode->removeChildNode(child);
            delete child;
        }
        if (!m_snapshotNode) {
            m_snapshotNode = new QSGSimpleTextureNode();
            m_snapshotNode->setOwnsTexture(false);
            m_snapshotNode->setFiltering(QSGTexture::Linear);
            textureNode->appendChildNode(m_snapshotNode);
        }
        m_snapshotNode->setTexture(m_snapshotSg);
        m_snapshotNode->setRect(pinchRect(m_snapshotRect));
        textureNode->setRect(QRectF());
        return textureNode;
    }
    if (m_snapshotNode || m_snapshotTexture)
        dropPinchSnapshot(context);
    // Below a stale frame shorter than the view (the toolbar slid away and
    // the page grew; WebKit takes about 70 ms to draw at the new height), a
    // row of the frame's pixels near its bottom, stretched down: usually the
    // page's background, where the window's white showed through. Not the
    // last row: WebKit's frame can be a pixel taller than the page (rounding
    // through CSS pixels) and that row is blank.
    auto* fill = textureNode->childCount() ? static_cast<QSGSimpleTextureNode*>(textureNode->firstChild()) : nullptr;
    const qreal frameBottom = textureNode->rect().bottom();
    if (!scaling && !frameSize.isEmpty() && frameBottom < item.height() - 0.5) {
        if (!fill) {
            fill = new QSGSimpleTextureNode();
            fill->setOwnsTexture(false);
            fill->setFiltering(QSGTexture::Nearest);
            textureNode->appendChildNode(fill);
        }
        fill->setTexture(texture);
        fill->setSourceRect(QRectF(0, qMax(0, frameSize.height() - 4), frameSize.width(), 1));
        fill->setRect(QRectF(0, frameBottom, item.width(), item.height() - frameBottom));
    } else if (fill) {
        textureNode->removeChildNode(fill);
        delete fill;
    }
    return textureNode;
}

// Render thread, context current: a copy of the frame on screen (one blit).
void PacificWebView::takePinchSnapshot(QOpenGLContext* context)
{
    const unsigned source = m_backend ? m_backend->textureId() : 0;
    const QSize size = m_backend ? m_backend->committedImageSize() : QSize();
    if (!source || size.isEmpty())
        return;
    QOpenGLExtraFunctions* gl = context->extraFunctions();
    GLint previous = 0;
    gl->glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previous);
    if (size != m_snapshotSize && m_snapshotTexture) {
        delete m_snapshotSg;
        m_snapshotSg = nullptr;
        gl->glDeleteTextures(1, &m_snapshotTexture);
        m_snapshotTexture = 0;
    }
    if (!m_snapshotTexture) {
        gl->glGenTextures(1, &m_snapshotTexture);
        gl->glBindTexture(GL_TEXTURE_2D, m_snapshotTexture);
        gl->glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, size.width(), size.height(), 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        m_snapshotSize = size;
    }
    std::array<GLuint, 2> fbo {};
    gl->glGenFramebuffers(2, fbo.data());
    gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo[0]);
    gl->glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, source, 0);
    gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo[1]);
    gl->glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_snapshotTexture, 0);
    gl->glBlitFramebuffer(0, 0, size.width(), size.height(), 0, 0, size.width(), size.height(), GL_COLOR_BUFFER_BIT,
        GL_NEAREST);
    gl->glBindFramebuffer(GL_FRAMEBUFFER, static_cast<GLuint>(previous));
    gl->glDeleteFramebuffers(2, fbo.data());
    if (!m_snapshotSg)
        m_snapshotSg = QNativeInterface::QSGOpenGLTexture::fromNative(m_snapshotTexture, window(), size,
            QQuickWindow::TextureHasAlphaChannel);
    // Where the frame was drawn before the pinch's scaling: the item's
    // width, at the frame's own aspect.
    const qreal width = boundingRect().width();
    m_snapshotRect = QRectF(0, 0, width, size.height() * width / size.width());
    m_pinch.haveSnapshot = true;
}

void PacificWebView::dropPinchSnapshot(QOpenGLContext* context)
{
    if (m_snapshotNode) {
        if (QSGNode* parent = m_snapshotNode->parent())
            parent->removeChildNode(m_snapshotNode);
        delete m_snapshotNode;
        m_snapshotNode = nullptr;
    }
    delete m_snapshotSg;
    m_snapshotSg = nullptr;
    if (m_snapshotTexture && context) {
        context->functions()->glDeleteTextures(1, &m_snapshotTexture);
        m_snapshotTexture = 0;
        m_snapshotSize = {};
    }
}

void PacificWebView::releaseResources()
{
    QQuickItem::releaseResources();
}

void PacificWebView::onSceneGraphInitialized()
{
    if (!m_webView)
        ensureWebView();
}

bool PacificWebView::eventFilter(QObject* watched, QEvent* event)
{
    // Exposure has no signal: the window's Expose event says it changed.
    if (event->type() == QEvent::Expose && watched == window())
        QMetaObject::invokeMethod(this, &PacificWebView::applyActivityState, Qt::QueuedConnection);
    return QQuickItem::eventFilter(watched, event);
}

void PacificWebView::onFrameSwapped()
{
    if (!m_backend)
        return;
    m_backend->didRenderFrame();
    // A window's device pixel ratio can settle only after it is exposed
    // (fractional scaling on desktops), with no geometry change to tell us.
    const qreal ratio = itemToPhysical();
    if (!qFuzzyCompare(ratio, m_lastRatio)) {
        m_lastRatio = ratio;
        updateBackendGeometry();
    }
}

void PacificWebView::dispatchEarlyAck()
{
    if (m_backend)
        m_backend->dispatchEarlyAck();
}

void PacificWebView::notifyFullscreenRequest(bool enter)
{
    Q_EMIT fullscreenRequested(enter);
}

// --- page state --------------------------------------------------------------

QUrl PacificWebView::url() const
{
    if (m_webView) {
        if (const gchar* uri = webkit_web_view_get_uri(m_webView))
            return QUrl(QString::fromUtf8(uri));
    }
    return m_url;
}

void PacificWebView::setUrl(const QUrl& url)
{
    // Compare with what is shown, not what was last assigned: after a link
    // or redirect away from X, assigning X again must load it (Atlantic).
    if (url == this->url() && m_webView)
        return;
    load(url);
}

void PacificWebView::load(const QUrl& url)
{
    m_url = url;
    m_html.clear();
    m_errorOccurred = false;
    if (m_webView)
        webkit_web_view_load_uri(m_webView, url.toString(QUrl::FullyEncoded).toUtf8().constData());
    else
        Q_EMIT urlChanged();
}

void PacificWebView::loadHtml(const QString& html, const QUrl& baseUrl)
{
    m_html = html;
    m_baseUrl = baseUrl;
    m_url.clear();
    if (m_webView)
        webkit_web_view_load_html(m_webView, html.toUtf8().constData(), baseUrl.toString().toUtf8().constData());
}

QString PacificWebView::title() const
{
    return m_webView ? QString::fromUtf8(webkit_web_view_get_title(m_webView)) : QString();
}

int PacificWebView::loadProgress() const
{
    return m_webView ? qRound(webkit_web_view_get_estimated_load_progress(m_webView) * 100) : 0;
}

bool PacificWebView::isLoading() const
{
    return m_webView && webkit_web_view_is_loading(m_webView);
}

bool PacificWebView::canGoBack() const
{
    return m_webView && webkit_web_view_can_go_back(m_webView);
}

bool PacificWebView::canGoForward() const
{
    return m_webView && webkit_web_view_can_go_forward(m_webView);
}

namespace {
// The entry's address in memory, which is unique while it lives, and its
// URL's hash, so an entry freed and another later at the same address do
// not share a key (and a picture).
QString historyItemKey(WebKitBackForwardListItem* item)
{
    if (!item)
        return QString();
    return QString::number(reinterpret_cast<quintptr>(item), 16) + QLatin1Char('-')
        + QString::number(qHash(QByteArrayView(webkit_back_forward_list_item_get_uri(item))), 16);
}
}

QString PacificWebView::historyKey() const
{
    if (!m_webView)
        return QString();
    WebKitBackForwardList* list = webkit_web_view_get_back_forward_list(m_webView);
    return list ? historyItemKey(webkit_back_forward_list_get_current_item(list)) : QString();
}

QVariantMap PacificWebView::historyItemAt(int offset) const
{
    if (!m_webView)
        return {};
    WebKitBackForwardList* list = webkit_web_view_get_back_forward_list(m_webView);
    WebKitBackForwardListItem* item = list ? webkit_back_forward_list_get_nth_item(list, offset) : nullptr;
    if (!item)
        return {};
    return {
        { QStringLiteral("key"), historyItemKey(item) },
        { QStringLiteral("url"), QString::fromUtf8(webkit_back_forward_list_item_get_uri(item)) },
        { QStringLiteral("title"), QString::fromUtf8(webkit_back_forward_list_item_get_title(item)) },
    };
}

bool PacificWebView::isAudioPlaying() const
{
    return m_webView && webkit_web_view_is_playing_audio(m_webView);
}

bool PacificWebView::isMuted() const
{
    return m_webView ? static_cast<bool>(webkit_web_view_get_is_muted(m_webView)) : m_muted;
}

void PacificWebView::setMuted(bool muted)
{
    m_muted = muted;
    if (m_webView)
        webkit_web_view_set_is_muted(m_webView, muted);
    else
        Q_EMIT audioChanged();
}

// Strict one-step history: webkit_web_view_go_back() skips entries created by
// script without a user gesture, which collapses SPA routes (Atlantic,
// forum.sailfishos.org). PACIFIC_STRICT_HISTORY_NAV=0 restores WebKit's way.
static bool strictHistory()
{
    static const bool strict = qgetenv("PACIFIC_STRICT_HISTORY_NAV") != "0";
    return strict;
}

void PacificWebView::goBack()
{
    if (!m_webView)
        return;
    WebKitBackForwardList* list = webkit_web_view_get_back_forward_list(m_webView);
    if (strictHistory() && list) {
        if (WebKitBackForwardListItem* item = webkit_back_forward_list_get_back_item(list)) {
            webkit_web_view_go_to_back_forward_list_item(m_webView, item);
            return;
        }
    }
    webkit_web_view_go_back(m_webView);
}

void PacificWebView::goForward()
{
    if (!m_webView)
        return;
    WebKitBackForwardList* list = webkit_web_view_get_back_forward_list(m_webView);
    if (strictHistory() && list) {
        if (WebKitBackForwardListItem* item = webkit_back_forward_list_get_forward_item(list)) {
            webkit_web_view_go_to_back_forward_list_item(m_webView, item);
            return;
        }
    }
    webkit_web_view_go_forward(m_webView);
}

void PacificWebView::reload()
{
    if (m_webView)
        webkit_web_view_reload(m_webView);
}

void PacificWebView::reloadBypassCache()
{
    if (m_webView)
        webkit_web_view_reload_bypass_cache(m_webView);
}

void PacificWebView::stop()
{
    if (m_webView)
        webkit_web_view_stop_loading(m_webView);
}

// --- configuration -----------------------------------------------------------

WebProfile* PacificWebView::profile() const
{
    return m_profile;
}

void PacificWebView::setProfile(WebProfile* profile)
{
    if (m_webView) {
        qWarning("WebView.profile: set it before the view is created; ignored");
        return;
    }
    if (profile == m_profile)
        return;
    m_profile = profile;
    Q_EMIT profileChanged();
}

QString PacificWebView::defaultUserAgent(bool desktop) const
{
    // PACIFIC_USER_AGENT replaces the mobile one, for trying others.
    static const QString mobile = qEnvironmentVariableIsSet("PACIFIC_USER_AGENT")
        ? qEnvironmentVariable("PACIFIC_USER_AGENT")
        : QString::fromLatin1(kMobileUserAgent);
    return desktop ? QString::fromLatin1(kDesktopUserAgent) : mobile;
}

QString PacificWebView::userAgent() const
{
    if (m_webView)
        return QString::fromUtf8(webkit_settings_get_user_agent(webkit_web_view_get_settings(m_webView)));
    return m_userAgent.isEmpty() ? defaultUserAgent(m_desktopMode) : m_userAgent;
}

void PacificWebView::setUserAgent(const QString& userAgent)
{
    if (userAgent == m_userAgent)
        return;
    m_userAgent = userAgent;
    if (m_webView) {
        const QString ua = userAgent.isEmpty() ? defaultUserAgent(m_desktopMode) : userAgent;
        webkit_settings_set_user_agent(webkit_web_view_get_settings(m_webView), ua.toUtf8().constData());
    }
    Q_EMIT userAgentChanged();
}

void PacificWebView::setDesktopMode(bool desktop)
{
    if (desktop == m_desktopMode)
        return;
    m_desktopMode = desktop;
    if (m_webView && m_userAgent.isEmpty()) {
        webkit_settings_set_user_agent(webkit_web_view_get_settings(m_webView), defaultUserAgent(desktop).toUtf8().constData());
        Q_EMIT userAgentChanged();
    }
    Q_EMIT desktopModeChanged();
}

void PacificWebView::setZoomFactor(qreal factor)
{
    factor = qBound(0.25, factor, 5.0);
    if (qFuzzyCompare(factor, m_zoomFactor))
        return;
    m_zoomFactor = factor;
    applyZoom();
    Q_EMIT zoomFactorChanged();
}

void PacificWebView::applyZoom()
{
    if (m_webView)
        webkit_web_view_set_zoom_level(m_webView, (pageZoomScaling() ? effectiveContentScale() : 1.0) * pageZoom());
}

void PacificWebView::setFitScale(qreal scale)
{
    scale = qBound(0.25, scale, 1.0);
    if (qFuzzyCompare(scale, m_fitScale))
        return;
    m_fitScale = scale;
    applyZoom();
    applySafeArea();
    applyObscured();
}

void PacificWebView::setContentScale(qreal scale)
{
    if (qFuzzyCompare(scale, m_contentScale))
        return;
    m_contentScale = scale;
    updateBackendGeometry();
    if (pageZoomScaling())
        applyZoom();
    Q_EMIT contentScaleChanged();
}

void PacificWebView::setActive(bool active)
{
    if (active == m_active)
        return;
    m_active = active;
    applyActivityState();
    if (!active && m_im.focused && hasActiveFocus())
        QGuiApplication::inputMethod()->hide();
    Q_EMIT activeChanged();
}

void PacificWebView::setHeadless(bool headless)
{
    if (headless == m_headless)
        return;
    m_headless = headless;
    applyActivityState();
    update();
    Q_EMIT headlessChanged();
}

void PacificWebView::setInputMode(InputMode mode)
{
    if (mode == m_inputMode)
        return;
    m_inputMode = mode;
    m_preedit.clear();
    Q_EMIT inputModeChanged();
}

void PacificWebView::setScriptSelectMenus(bool enabled)
{
    if (enabled == m_scriptSelectMenus)
        return;
    m_scriptSelectMenus = enabled;
    if (m_webView) {
        evaluate(QStringLiteral("window.__pacificScriptSelect = %1;").arg(enabled ? QLatin1String("true") : QLatin1String("false")), kWorld, QJSValue());
        if (enabled) {
            WebKitUserScript* flag = webkit_user_script_new_for_world("window.__pacificScriptSelect = true;",
                WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, kWorld, nullptr, nullptr);
            webkit_user_content_manager_add_script(webkit_web_view_get_user_content_manager(m_webView), flag);
            webkit_user_script_unref(flag);
        }
    }
    Q_EMIT scriptSelectMenusChanged();
}

void PacificWebView::setCaptureConsole(bool enabled)
{
    if (enabled == m_captureConsole)
        return;
    m_captureConsole = enabled;
    if (m_webView) {
        if (enabled)
            installConsoleCapture();
        else
            removeConsoleCapture();
    }
    Q_EMIT captureConsoleChanged();
}

bool PacificWebView::javascriptEnabled() const
{
    return setting(QStringLiteral("enable-javascript")).toBool();
}

void PacificWebView::setJavascriptEnabled(bool enabled)
{
    setSetting(QStringLiteral("enable-javascript"), enabled);
}

bool PacificWebView::loadImages() const
{
    return setting(QStringLiteral("auto-load-images")).toBool();
}

void PacificWebView::setLoadImages(bool enabled)
{
    setSetting(QStringLiteral("auto-load-images"), enabled);
}

bool PacificWebView::mediaNeedsUserGesture() const
{
    return setting(QStringLiteral("media-playback-requires-user-gesture")).toBool();
}

void PacificWebView::setMediaNeedsUserGesture(bool needed)
{
    setSetting(QStringLiteral("media-playback-requires-user-gesture"), needed);
}

void PacificWebView::setSetting(const QString& name, const QVariant& value)
{
    if (!m_webView) {
        // Restored and background tabs get their settings before WebKit's
        // view exists: keep them for applyPendingState().
        m_pendingSettings.insert(name, value);
        return;
    }
    WebKitSettings* settings = webkit_web_view_get_settings(m_webView);
    const QByteArray key = name.toUtf8();
    GParamSpec* spec = g_object_class_find_property(G_OBJECT_GET_CLASS(settings), key.constData());
    if (!spec) {
        qWarning("WebView.setSetting: no WebKitSettings property %s", key.constData());
        return;
    }
    GValue gvalue = G_VALUE_INIT;
    g_value_init(&gvalue, spec->value_type);
    if (spec->value_type == G_TYPE_BOOLEAN)
        g_value_set_boolean(&gvalue, value.toBool());
    else if (spec->value_type == G_TYPE_UINT)
        g_value_set_uint(&gvalue, value.toUInt());
    else if (spec->value_type == G_TYPE_INT)
        g_value_set_int(&gvalue, value.toInt());
    else if (spec->value_type == G_TYPE_STRING)
        g_value_set_string(&gvalue, value.toString().toUtf8().constData());
    else if (G_TYPE_IS_ENUM(spec->value_type))
        g_value_set_enum(&gvalue, value.toInt());
    else {
        qWarning("WebView.setSetting: unsupported type for %s", key.constData());
        g_value_unset(&gvalue);
        return;
    }
    g_object_set_property(G_OBJECT(settings), key.constData(), &gvalue);
    g_value_unset(&gvalue);
    Q_EMIT settingsChanged();
}

QVariant PacificWebView::setting(const QString& name) const
{
    if (!m_webView)
        return {};
    WebKitSettings* settings = webkit_web_view_get_settings(m_webView);
    const QByteArray key = name.toUtf8();
    GParamSpec* spec = g_object_class_find_property(G_OBJECT_GET_CLASS(settings), key.constData());
    if (!spec)
        return {};
    GValue gvalue = G_VALUE_INIT;
    g_value_init(&gvalue, spec->value_type);
    g_object_get_property(G_OBJECT(settings), key.constData(), &gvalue);
    QVariant result;
    if (spec->value_type == G_TYPE_BOOLEAN)
        result = static_cast<bool>(g_value_get_boolean(&gvalue));
    else if (spec->value_type == G_TYPE_UINT)
        result = g_value_get_uint(&gvalue);
    else if (spec->value_type == G_TYPE_INT)
        result = g_value_get_int(&gvalue);
    else if (spec->value_type == G_TYPE_STRING)
        result = QString::fromUtf8(g_value_get_string(&gvalue));
    else if (G_TYPE_IS_ENUM(spec->value_type))
        result = g_value_get_enum(&gvalue);
    g_value_unset(&gvalue);
    return result;
}

bool PacificWebView::setFeatureEnabled(const QString& identifier, bool enabled)
{
    if (!m_webView)
        return false;
    bool found = false;
    WebKitFeatureList* features = webkit_settings_get_all_features();
    const gsize count = webkit_feature_list_get_length(features);
    const QByteArray id = identifier.toUtf8();
    for (gsize i = 0; i < count; ++i) {
        WebKitFeature* feature = webkit_feature_list_get(features, i);
        if (id == webkit_feature_get_identifier(feature)) {
            webkit_settings_set_feature_enabled(webkit_web_view_get_settings(m_webView), feature, enabled);
            found = true;
            break;
        }
    }
    webkit_feature_list_unref(features);
    return found;
}

int PacificWebView::addUserScript(const QString& source, const QString& world, InjectionTime time, bool allFrames,
    const QStringList& skipHosts)
{
    if (!m_webView)
        return 0;
    const QByteArray src = source.toUtf8();
    const auto frames = allFrames ? WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES : WEBKIT_USER_CONTENT_INJECT_TOP_FRAME;
    const auto when = time == DocumentStart ? WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START
                                            : WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END;
    // WebKit's URL patterns: "*.host" covers the host and its subdomains.
    QByteArrayList patterns;
    for (const QString& host : skipHosts) {
        if (!host.isEmpty())
            patterns.append(QStringLiteral("*://*.%1/*").arg(host).toUtf8());
    }
    QList<const gchar*> blockList;
    for (const QByteArray& pattern : patterns)
        blockList.append(pattern.constData());
    blockList.append(nullptr);
    const gchar* const* block = patterns.isEmpty() ? nullptr : blockList.constData();
    // An empty world is the page's own: webkit_user_script_new_for_world()
    // requires a name (it asserts and returns NULL for none).
    const QByteArray w = world.toUtf8();
    WebKitUserScript* script = world.isEmpty()
        ? webkit_user_script_new(src.constData(), frames, when, nullptr, block)
        : webkit_user_script_new_for_world(src.constData(), frames, when, w.constData(), nullptr, block);
    if (!script) {
        qWarning("WebView.addUserScript: WebKit refused the script");
        return 0;
    }
    webkit_user_content_manager_add_script(webkit_web_view_get_user_content_manager(m_webView), script);
    const int handle = m_nextUserScript++;
    m_userScripts.insert(handle, script);
    return handle;
}

void PacificWebView::removeUserScript(int handle)
{
    WebKitUserScript* script = m_userScripts.take(handle);
    if (!script)
        return;
    if (m_webView)
        webkit_user_content_manager_remove_script(webkit_web_view_get_user_content_manager(m_webView), script);
    webkit_user_script_unref(script);
}

void PacificWebView::dropUserScripts()
{
    for (WebKitUserScript* script : std::as_const(m_userScripts))
        webkit_user_script_unref(script);
    m_userScripts.clear();
}

void PacificWebView::addUserStyleSheet(const QString& css, bool allFrames)
{
    if (!m_webView)
        return;
    WebKitUserStyleSheet* sheet = webkit_user_style_sheet_new(css.toUtf8().constData(),
        allFrames ? WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES : WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
        WEBKIT_USER_STYLE_LEVEL_USER, nullptr, nullptr);
    webkit_user_content_manager_add_style_sheet(webkit_web_view_get_user_content_manager(m_webView), sheet);
    webkit_user_style_sheet_unref(sheet);
}

void PacificWebView::removeUserContent()
{
    if (!m_webView)
        return;
    WebKitUserContentManager* ucm = webkit_web_view_get_user_content_manager(m_webView);
    webkit_user_content_manager_remove_all_scripts(ucm);
    webkit_user_content_manager_remove_all_style_sheets(ucm);
    dropUserScripts();
    // Pacific's own bridges go back in.
    installPageScripts();
}

bool PacificWebView::registerScriptMessageHandler(const QString& name, const QString& world)
{
    if (!m_webView || name.startsWith(QLatin1String("pacific")))
        return false;
    WebKitUserContentManager* ucm = webkit_web_view_get_user_content_manager(m_webView);
    const QByteArray n = name.toUtf8();
    const QByteArray w = world.toUtf8();
    if (!webkit_user_content_manager_register_script_message_handler(ucm, n.constData(),
            world.isEmpty() ? nullptr : w.constData()))
        return false;
    connectScriptMessage(ucm, this, n.constData());
    return true;
}

// --- scripts -----------------------------------------------------------------

void PacificWebView::evaluate(const QString& script, const char* world, const QJSValue& callback)
{
    if (!m_webView) {
        if (callback.isCallable())
            callback.call({ QJSValue(QJSValue::UndefinedValue), QJSValue(QStringLiteral("no web view")) });
        return;
    }
    const QByteArray utf8 = script.toUtf8();
    webkit_web_view_evaluate_javascript(m_webView, utf8.constData(), utf8.size(), world, nullptr, nullptr,
        [](GObject* object, GAsyncResult* result, gpointer data) {
            GError* error = nullptr;
            JSCValue* value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(object), result, &error);
            QVariant out;
            QString message;
            if (value) {
                out = jscToVariant(value);
                g_object_unref(value);
            } else {
                message = QString::fromUtf8(error ? error->message : "script failed");
                g_clear_error(&error);
            }
            deliver(static_cast<JsCallback*>(data), out, message);
        },
        new JsCallback { this, callback });
}

void PacificWebView::runJavaScript(const QString& script, const QJSValue& callback)
{
    evaluate(script, nullptr, callback);
}

void PacificWebView::runJavaScriptInWorld(const QString& script, const QString& world, const QJSValue& callback)
{
    const QByteArray w = world.toUtf8();
    evaluate(script, world.isEmpty() ? kWorld : w.constData(), callback);
}

// --- find, editing, selection, pickers ---------------------------------------

void PacificWebView::findText(const QString& text, bool caseSensitive)
{
    if (!m_webView)
        return;
    WebKitFindController* find = webkit_web_view_get_find_controller(m_webView);
    if (text.isEmpty()) {
        stopFind();
        return;
    }
    m_findText = text;
    const guint32 options = WEBKIT_FIND_OPTIONS_WRAP_AROUND | (caseSensitive ? 0 : WEBKIT_FIND_OPTIONS_CASE_INSENSITIVE);
    webkit_find_controller_count_matches(find, text.toUtf8().constData(), options, 1000);
    webkit_find_controller_search(find, text.toUtf8().constData(), options, 1000);
}

void PacificWebView::findNext()
{
    if (m_webView && !m_findText.isEmpty())
        webkit_find_controller_search_next(webkit_web_view_get_find_controller(m_webView));
}

void PacificWebView::findPrevious()
{
    if (m_webView && !m_findText.isEmpty())
        webkit_find_controller_search_previous(webkit_web_view_get_find_controller(m_webView));
}

void PacificWebView::stopFind()
{
    if (!m_webView)
        return;
    webkit_find_controller_search_finish(webkit_web_view_get_find_controller(m_webView));
    m_findText.clear();
    m_findMatchCount = 0;
    Q_EMIT findMatchCountChanged();
}

void PacificWebView::executeEditingCommand(EditingCommand command)
{
    if (!m_webView)
        return;
    const char* name = nullptr;
    switch (command) {
    case Cut:
        name = WEBKIT_EDITING_COMMAND_CUT;
        break;
    case Copy:
        name = WEBKIT_EDITING_COMMAND_COPY;
        break;
    case Paste:
        name = WEBKIT_EDITING_COMMAND_PASTE;
        break;
    case PasteAsPlainText:
        name = WEBKIT_EDITING_COMMAND_PASTE_AS_PLAIN_TEXT;
        break;
    case SelectAll:
        name = WEBKIT_EDITING_COMMAND_SELECT_ALL;
        break;
    case Undo:
        name = WEBKIT_EDITING_COMMAND_UNDO;
        break;
    case Redo:
        name = WEBKIT_EDITING_COMMAND_REDO;
        break;
    }
    // The engine's pasteboard is its own; paste from the system clipboard
    // as typed text instead.
    if (command == Paste || command == PasteAsPlainText) {
        insertText(QGuiApplication::clipboard()->text());
        return;
    }
    webkit_web_view_execute_editing_command(m_webView, name);
    if (command == Copy || command == Cut)
        copySelection();
}

void PacificWebView::insertText(const QString& text)
{
    if (m_webView && !text.isEmpty())
        webkit_web_view_execute_editing_command_with_argument(m_webView, "InsertText", text.toUtf8().constData());
}

void PacificWebView::copySelection()
{
    if (!m_selectedText.isEmpty())
        QGuiApplication::clipboard()->setText(m_selectedText);
}

void PacificWebView::clearSelection()
{
    evaluate(QStringLiteral("window.getSelection().removeAllRanges();"), kWorld, QJSValue());
}

bool PacificWebView::activateContextItem(WebKitContextMenuAction action, int index)
{
    if (!m_contextMenu)
        return false;
    int seen = 0;
    for (GList* l = webkit_context_menu_get_items(m_contextMenu); l; l = l->next) {
        auto* item = static_cast<WebKitContextMenuItem*>(l->data);
        if (webkit_context_menu_item_get_stock_action(item) != action)
            continue;
        if (seen++ != index)
            continue;
        GAction* gaction = webkit_context_menu_item_get_gaction(item);
        if (!gaction)
            return false;
        g_action_activate(gaction, webkit_context_menu_item_get_gaction_target(item));
        g_clear_object(&m_contextMenu);
        return true;
    }
    return false;
}

void PacificWebView::contextMenuAt(qreal cssX, qreal cssY)
{
    if (m_backend)
        m_backend->dispatchContextClick(cssToItem(cssX, cssY));
}

// Script used when WebKit's menu item has no action to activate (WPE
// builds its spelling items without one): select the word at the caret in
// the focused field and either return it or replace it as typed text, so the
// page gets beforeinput/input and the edit is undoable.
static QString wordAtCaretScript(const QString& replacementJson)
{
    return QStringLiteral(
        "(function(rep){"
        "var el=document.activeElement;while(el&&el.shadowRoot&&el.shadowRoot.activeElement)el=el.shadowRoot.activeElement;"
        "var isText=el&&(el.tagName==='TEXTAREA'||el.tagName==='INPUT');var word='';"
        "if(isText){var v=el.value,p=el.selectionStart,e=el.selectionEnd;"
        "if(p===e){var re=/[\\p{L}\\p{M}'\u2019-]/u;while(p>0&&re.test(v[p-1]))p--;while(e<v.length&&re.test(v[e]))e++;}"
        "word=v.slice(p,e);if(rep!==null){el.setSelectionRange(p,e);document.execCommand('insertText',false,rep);}}"
        "else{var s=getSelection();if(!s||!s.rangeCount)return '';"
        "if(s.isCollapsed){s.modify('move','backward','word');s.modify('extend','forward','word');}"
        "word=s.toString().trim();if(rep!==null)document.execCommand('insertText',false,rep);}"
        "return word;})(%1)").arg(replacementJson);
}

bool PacificWebView::applySpellingSuggestion(int index)
{
    // The guesses are copied when the menu arrives: WebKit empties its menu
    // object once the context-menu signal returns.
    if (index < 0 || index >= m_spellingSuggestions.size())
        return false;
    const QString suggestion = m_spellingSuggestions.at(index);
    m_spellingSuggestions.clear();
    m_misspelled = false;
    if (activateContextItem(WEBKIT_CONTEXT_MENU_ACTION_SPELLING_GUESS, index))
        return true;
    g_clear_object(&m_contextMenu);
    evaluate(wordAtCaretScript(jsonArgument(suggestion)), nullptr, QJSValue());
    return true;
}

bool PacificWebView::learnSpelling()
{
    if (activateContextItem(WEBKIT_CONTEXT_MENU_ACTION_LEARN_SPELLING, 0))
        return true;
    if (!m_misspelled)
        return false;
    m_misspelled = false;
    m_spellingSuggestions.clear();
    g_clear_object(&m_contextMenu);
    // enchant's personal word list: <ENCHANT_CONFIG_DIR>/<language>.dic, one
    // word per line, re-read when it changes.
    QPointer<PacificWebView> self(this);
    const QByteArray script = wordAtCaretScript(QStringLiteral("null")).toUtf8();
    webkit_web_view_evaluate_javascript(m_webView, script.constData(), script.size(), nullptr, nullptr, nullptr,
        [](GObject* object, GAsyncResult* result, gpointer) {
            JSCValue* value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(object), result, nullptr);
            const QString word = value ? jscToVariant(value).toString() : QString();
            if (value)
                g_object_unref(value);
            if (word.isEmpty() || word.contains(QLatin1Char('\n')))
                return;
            const QString dir = qEnvironmentVariable("ENCHANT_CONFIG_DIR");
            const auto languages = WebEngine::instance()->spellCheckingLanguages();
            for (const QString& language : languages) {
                QFile file(dir + QLatin1Char('/') + language + QStringLiteral(".dic"));
                if (file.open(QIODevice::Append | QIODevice::Text))
                    file.write(word.toUtf8() + '\n');
            }
        },
        nullptr);
    return true;
}

bool PacificWebView::ignoreSpelling()
{
    return activateContextItem(WEBKIT_CONTEXT_MENU_ACTION_IGNORE_SPELLING, 0);
}

void PacificWebView::selectMenuOption(int index)
{
    if (m_optionMenu) {
        webkit_option_menu_activate_item(m_optionMenu, static_cast<guint>(index));
        webkit_option_menu_close(m_optionMenu);
        return;
    }
    evaluate(QStringLiteral("window.__pacificPickers && __pacificPickers.resolveSelect(%1)").arg(index), kWorld, QJSValue());
}

void PacificWebView::closeSelectMenu()
{
    if (m_optionMenu) {
        webkit_option_menu_close(m_optionMenu);
        return;
    }
    evaluate(QStringLiteral("window.__pacificPickers && __pacificPickers.cancelSelect()"), kWorld, QJSValue());
}

void PacificWebView::resolveInputPicker(const QString& value)
{
    evaluate(QStringLiteral("window.__pacificPickers && __pacificPickers.resolveInput(%1)").arg(jsonArgument(value)),
        kWorld, QJSValue());
}

void PacificWebView::cancelInputPicker()
{
    evaluate(QStringLiteral("window.__pacificPickers && __pacificPickers.cancelInput()"), kWorld, QJSValue());
}

// --- tab lifecycle -----------------------------------------------------------

void PacificWebView::discard()
{
    if (m_webView && !m_terminated)
        webkit_web_view_terminate_web_process(m_webView);
}

QString PacificWebView::sessionState() const
{
    if (!m_webView)
        return {};
    WebKitWebViewSessionState* state = webkit_web_view_get_session_state(m_webView);
    GBytes* bytes = webkit_web_view_session_state_serialize(state);
    gsize size = 0;
    const auto* data = static_cast<const char*>(g_bytes_get_data(bytes, &size));
    const QString encoded = QString::fromLatin1(QByteArray(data, static_cast<qsizetype>(size)).toBase64());
    g_bytes_unref(bytes);
    webkit_web_view_session_state_unref(state);
    return encoded;
}

bool PacificWebView::restoreSessionState(const QString& base64)
{
    if (!m_webView)
        return false;
    const QByteArray raw = QByteArray::fromBase64(base64.toLatin1());
    GBytes* bytes = g_bytes_new(raw.constData(), raw.size());
    WebKitWebViewSessionState* state = webkit_web_view_session_state_new(bytes);
    g_bytes_unref(bytes);
    if (!state)
        return false;
    webkit_web_view_restore_session_state(m_webView, state);
    webkit_web_view_session_state_unref(state);
    WebKitBackForwardList* list = webkit_web_view_get_back_forward_list(m_webView);
    if (WebKitBackForwardListItem* current = list ? webkit_back_forward_list_get_current_item(list) : nullptr)
        webkit_web_view_go_to_back_forward_list_item(m_webView, current);
    return true;
}

struct ThumbnailCall {
    QPointer<PacificWebView> view;
    QString path;
    QSize max;
    QJSValue callback;
};

void PacificWebView::saveThumbnail(const QString& path, int maxWidth, int maxHeight, const QJSValue& callback)
{
    if (!m_webView || m_terminated) {
        if (callback.isCallable())
            callback.call({ QJSValue(false), QJSValue(path) });
        return;
    }
    webkit_web_view_get_snapshot(m_webView, WEBKIT_SNAPSHOT_REGION_VISIBLE, WEBKIT_SNAPSHOT_OPTIONS_NONE, nullptr,
        [](GObject* object, GAsyncResult* result, gpointer data) {
            std::shared_ptr<ThumbnailCall> call(static_cast<ThumbnailCall*>(data));
            GError* error = nullptr;
            WebKitImage* image = webkit_web_view_get_snapshot_finish(WEBKIT_WEB_VIEW(object), result, &error);
            if (!image) {
                qWarning("WebView.saveThumbnail: %s", error ? error->message : "no image");
                g_clear_error(&error);
                if (call->view && call->callback.isCallable())
                    call->callback.call({ QJSValue(false), QJSValue(call->path) });
                return;
            }
            // Scaling and encoding a screenful took a tenth of the GUI thread
            // at start: a pool thread does it, and the answer comes back here.
            QThreadPool::globalInstance()->start([call, image]() mutable {
                bool ok = false;
                GBytes* bytes = webkit_image_as_bytes(image);
                gsize size = 0;
                const auto* pixels = static_cast<const uchar*>(g_bytes_get_data(bytes, &size));
                const int w = static_cast<int>(webkit_image_get_width(image));
                const int h = static_cast<int>(webkit_image_get_height(image));
                const int stride = static_cast<int>(webkit_image_get_stride(image));
                if (pixels && w > 0 && h > 0 && size >= static_cast<gsize>(stride) * h) {
                    QImage frame(pixels, w, h, stride, QImage::Format_ARGB32_Premultiplied);
                    QImage scaled = frame.scaled(call->max.width() > 0 ? call->max.width() : w,
                        call->max.height() > 0 ? call->max.height() : h, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                    ok = scaled.save(call->path);
                }
                // The bytes belong to the image (transfer none): released with it.
                g_object_unref(image);
                // The call (its QJSValue) is used and released on the GUI
                // thread only.
                QMetaObject::invokeMethod(qApp, [call = std::move(call), ok] {
                    if (call->view && call->callback.isCallable())
                        call->callback.call({ QJSValue(ok), QJSValue(call->path) });
                }, Qt::QueuedConnection);
            });
        },
        new ThumbnailCall { this, path, QSize(maxWidth, maxHeight), callback });
}

// --- pictures of history entries ---------------------------------------------

namespace {
// The last pictures of pages left (captureHistoryPicture()), for every view
// in the process: half-resolution screenfuls, the 16 most recently used
// (about 2.3 MB each on the Jolla Phone). In memory only, so private tabs
// get them too and nothing is left on disk.
class HistoryPictures : public QQuickImageProvider {
public:
    HistoryPictures()
        : QQuickImageProvider(QQuickImageProvider::Image)
    {
    }
    static HistoryPictures* instance()
    {
        static auto* pictures = new HistoryPictures;
        return pictures;
    }
    void put(const QString& key, const QImage& image)
    {
        QMutexLocker lock(&m_mutex);
        m_order.removeAll(key);
        m_order.append(key);
        m_images.insert(key, image);
        while (m_order.size() > 16)
            m_images.remove(m_order.takeFirst());
    }
    bool has(const QString& key)
    {
        QMutexLocker lock(&m_mutex);
        return m_images.contains(key);
    }
    QImage requestImage(const QString& id, QSize* size, const QSize& requested) override
    {
        QMutexLocker lock(&m_mutex);
        QImage image = m_images.value(id);
        if (!image.isNull()) {
            m_order.removeAll(id);
            m_order.append(id);
        }
        if (size)
            *size = image.size();
        return requested.isValid() && !image.isNull() ? image.scaled(requested, Qt::KeepAspectRatio) : image;
    }

private:
    QMutex m_mutex;
    QHash<QString, QImage> m_images;
    QStringList m_order;
};

struct HistoryPictureCall {
    QPointer<PacificWebView> view;
    QString key;
};
}

bool PacificWebView::hasHistoryPicture(const QString& key) const
{
    return !key.isEmpty() && HistoryPictures::instance()->has(key);
}

void PacificWebView::captureHistoryPicture()
{
    const QString key = historyKey();
    if (!m_webView || m_terminated || key.isEmpty())
        return;
    if (QQmlEngine* engine = qmlEngine(this); engine && !engine->imageProvider(QStringLiteral("pacifichistory")))
        engine->addImageProvider(QStringLiteral("pacifichistory"), HistoryPictures::instance());
    webkit_web_view_get_snapshot(m_webView, WEBKIT_SNAPSHOT_REGION_VISIBLE, WEBKIT_SNAPSHOT_OPTIONS_NONE, nullptr,
        [](GObject* object, GAsyncResult* result, gpointer data) {
            std::shared_ptr<HistoryPictureCall> call(static_cast<HistoryPictureCall*>(data));
            WebKitImage* image = webkit_web_view_get_snapshot_finish(WEBKIT_WEB_VIEW(object), result, nullptr);
            if (!image)
                return;
            QThreadPool::globalInstance()->start([call, image]() mutable {
                GBytes* bytes = webkit_image_as_bytes(image);
                gsize size = 0;
                const auto* pixels = static_cast<const uchar*>(g_bytes_get_data(bytes, &size));
                const int w = static_cast<int>(webkit_image_get_width(image));
                const int h = static_cast<int>(webkit_image_get_height(image));
                const int stride = static_cast<int>(webkit_image_get_stride(image));
                QImage half;
                if (pixels && w > 1 && h > 1 && size >= static_cast<gsize>(stride) * h) {
                    // Opaque: the picture covers what is under it.
                    half = QImage(pixels, w, h, stride, QImage::Format_ARGB32_Premultiplied)
                               .scaled(w / 2, h / 2, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                               .convertToFormat(QImage::Format_RGB32);
                }
                g_object_unref(image);
                if (half.isNull())
                    return;
                HistoryPictures::instance()->put(call->key, half);
                QMetaObject::invokeMethod(qApp, [call = std::move(call)] {
                    if (call->view)
                        Q_EMIT call->view->historyPictureReady(call->key);
                }, Qt::QueuedConnection);
            });
        },
        new HistoryPictureCall { this, key });
}

// --- agent API ---------------------------------------------------------------

void PacificWebView::agentCall(const QString& expression, const QJSValue& callback)
{
    evaluate(QStringLiteral("(function(){var a=window.__pacificAgent;"
                            "if(!a)return {ok:false,error:'agent helpers not loaded on this page'};"
                            "try{return a.%1;}catch(e){return {ok:false,error:String(e)};}})()")
                 .arg(expression),
        kWorld, callback);
}

void PacificWebView::agentSnapshot(const QVariantMap& options, const QJSValue& callback)
{
    agentCall(QStringLiteral("snapshot(%1)").arg(jsonArgument(options)), callback);
}

void PacificWebView::tapAt(const QPointF& itemPoint)
{
    if (m_backend)
        m_backend->dispatchTap(itemPoint);
}

void PacificWebView::agentClick(const QString& id, const QJSValue& callback)
{
    if (!m_backend) {
        agentCall(QStringLiteral("click(%1)").arg(jsonArgument(id)), callback);
        return;
    }
    // Locate (scrolling the element into view), then tap natively: the page
    // gets trusted touch, pointer, mouse and click events, as from a finger.
    QPointer<PacificWebView> self(this);
    QJSValue cb = callback;
    const QString script = QStringLiteral("(function(){var a=window.__pacificAgent;"
                                          "return a?a.locate(%1):{ok:false,error:'agent helpers not loaded'};})()")
                               .arg(jsonArgument(id));
    const QByteArray utf8 = script.toUtf8();
    struct ClickCall {
        QPointer<PacificWebView> view;
        QJSValue callback;
    };
    webkit_web_view_evaluate_javascript(m_webView, utf8.constData(), utf8.size(), kWorld, nullptr, nullptr,
        [](GObject* object, GAsyncResult* result, gpointer data) {
            std::unique_ptr<ClickCall> call(static_cast<ClickCall*>(data));
            GError* error = nullptr;
            JSCValue* value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(object), result, &error);
            QVariantMap located = value ? jscToVariant(value).toMap() : QVariantMap();
            if (value)
                g_object_unref(value);
            g_clear_error(&error);
            PacificWebView* view = call->view;
            if (!view)
                return;
            if (!located.value(QStringLiteral("ok")).toBool()) {
                deliver(new JsCallback { view, call->callback }, located, QString());
                return;
            }
            const QVariantList center = located.value(QStringLiteral("center")).toList();
            const QPointF point = view->cssToItem(center.value(0).toReal(), center.value(1).toReal());
            // Let the scroll land before the tap.
            QJSValue cb2 = call->callback;
            QTimer::singleShot(60, view, [view, point, located, cb2]() mutable {
                view->tapAt(point);
                located.insert(QStringLiteral("method"), QStringLiteral("tap"));
                deliver(new JsCallback { view, cb2 }, located, QString());
            });
        },
        new ClickCall { self, cb });
}

void PacificWebView::agentFocus(const QString& id, const QJSValue& callback)
{
    agentCall(QStringLiteral("focus(%1)").arg(jsonArgument(id)), callback);
}

void PacificWebView::agentSetValue(const QString& id, const QVariant& value, const QJSValue& callback)
{
    agentCall(QStringLiteral("setValue(%1,%2)").arg(jsonArgument(id), jsonArgument(value)), callback);
}

void PacificWebView::agentType(const QString& id, const QString& text, const QJSValue& callback)
{
    QPointer<PacificWebView> self(this);
    // Focus through the agent (not a tap, which could open a picker), then
    // type through WebKit's editor: trusted beforeinput/input events.
    agentCall(QStringLiteral("focus(%1)").arg(jsonArgument(id)), QJSValue());
    QTimer::singleShot(80, this, [self, text, callback] {
        if (!self)
            return;
        self->insertText(text);
        QVariantMap result;
        result.insert(QStringLiteral("ok"), true);
        result.insert(QStringLiteral("method"), QStringLiteral("type"));
        deliver(new JsCallback { self, callback }, result, QString());
    });
}

void PacificWebView::agentSubmit(const QString& id, const QJSValue& callback)
{
    agentCall(QStringLiteral("submit(%1)").arg(jsonArgument(id)), callback);
}

void PacificWebView::agentScroll(int dx, int dy, const QJSValue& callback)
{
    agentCall(QStringLiteral("scrollBy(%1,%2)").arg(dx).arg(dy), callback);
}

void PacificWebView::pageText(int maxChars, const QJSValue& callback)
{
    agentCall(QStringLiteral("text(%1)").arg(maxChars), callback);
}

void PacificWebView::pageHtml(int maxChars, const QJSValue& callback)
{
    agentCall(QStringLiteral("html(%1)").arg(maxChars), callback);
}

void PacificWebView::readerContent(const QJSValue& callback)
{
    agentCall(QStringLiteral("reader()"), callback);
}

// --- input -------------------------------------------------------------------

QRectF PacificWebView::cursorRectangle() const
{
    if (!m_im.focused)
        return {};
    const QRect r = m_im.cursorRect;
    // WebKit reports the caret in view coordinates, CSS px at the backend's
    // device scale (zoom is applied inside WebKit).
    const qreal factor = (pageZoomScaling() ? 1.0 : effectiveContentScale()) / itemToPhysical();
    return { r.x() * factor, r.y() * factor, qMax(1, r.width()) * factor, r.height() * factor };
}

void PacificWebView::setImState(const ImState& state, bool focusChange)
{
    const bool wasFocused = m_im.focused;
    m_im = state;
    setFlag(ItemAcceptsInputMethod, state.focused);
    QInputMethod* im = QGuiApplication::inputMethod();
    if (focusChange) {
        m_preedit.clear();
        if (state.focused && m_active && !m_headless) {
            WebEngine::instance()->spellCheckingNeeded();
            if (!hasActiveFocus())
                forceActiveFocus(Qt::OtherFocusReason);
            im->update(Qt::ImQueryAll);
            if (!(state.hints & WEBKIT_INPUT_HINT_INHIBIT_OSK))
                im->show();
        } else if (wasFocused && hasActiveFocus()) {
            im->hide();
            im->update(Qt::ImQueryAll);
        }
    } else if (hasActiveFocus() && state.focused) {
        im->update(Qt::ImCursorRectangle | Qt::ImSurroundingText | Qt::ImCursorPosition | Qt::ImAnchorPosition);
    }
    Q_EMIT inputMethodStateChanged();
}

void PacificWebView::resetInputMethod()
{
    m_preedit.clear();
    if (hasActiveFocus())
        QGuiApplication::inputMethod()->reset();
}

QVariant PacificWebView::inputMethodQuery(Qt::InputMethodQuery query) const
{
    switch (query) {
    case Qt::ImEnabled:
        return m_im.focused;
    case Qt::ImCursorRectangle:
    case Qt::ImAnchorRectangle:
        return cursorRectangle();
    case Qt::ImInputItemClipRectangle:
        return boundingRect();
    case Qt::ImSurroundingText:
        return m_im.surrounding;
    case Qt::ImCursorPosition:
        return m_im.cursor;
    case Qt::ImAnchorPosition:
        return m_im.anchor;
    case Qt::ImCurrentSelection:
        return m_im.cursor != m_im.anchor
            ? m_im.surrounding.mid(qMin(m_im.cursor, m_im.anchor), qAbs(m_im.cursor - m_im.anchor))
            : QString();
    case Qt::ImHints: {
        Qt::InputMethodHints hints = Qt::ImhNone;
        switch (m_im.purpose) {
        case WEBKIT_INPUT_PURPOSE_DIGITS:
            hints |= Qt::ImhDigitsOnly;
            break;
        case WEBKIT_INPUT_PURPOSE_NUMBER:
            hints |= Qt::ImhFormattedNumbersOnly;
            break;
        case WEBKIT_INPUT_PURPOSE_PHONE:
            hints |= Qt::ImhDialableCharactersOnly;
            break;
        case WEBKIT_INPUT_PURPOSE_URL:
            hints |= Qt::ImhUrlCharactersOnly | Qt::ImhNoAutoUppercase | Qt::ImhNoPredictiveText;
            break;
        case WEBKIT_INPUT_PURPOSE_EMAIL:
            hints |= Qt::ImhEmailCharactersOnly | Qt::ImhNoAutoUppercase | Qt::ImhNoPredictiveText;
            break;
        case WEBKIT_INPUT_PURPOSE_PASSWORD:
            hints |= Qt::ImhHiddenText | Qt::ImhSensitiveData | Qt::ImhNoAutoUppercase | Qt::ImhNoPredictiveText;
            break;
        default:
            break;
        }
        if (m_im.hints & WEBKIT_INPUT_HINT_LOWERCASE)
            hints |= Qt::ImhPreferLowercase | Qt::ImhNoAutoUppercase;
        if (m_im.hints & WEBKIT_INPUT_HINT_UPPERCASE_CHARS)
            hints |= Qt::ImhPreferUppercase;
        if (!(m_im.hints & WEBKIT_INPUT_HINT_SPELLCHECK) && m_im.purpose != WEBKIT_INPUT_PURPOSE_FREE_FORM)
            hints |= Qt::ImhNoPredictiveText;
        return static_cast<int>(hints);
    }
    case Qt::ImEnterKeyType:
        return m_im.purpose == WEBKIT_INPUT_PURPOSE_SEARCH ? Qt::EnterKeySearch
            : m_im.purpose == WEBKIT_INPUT_PURPOSE_URL     ? Qt::EnterKeyGo
                                                           : Qt::EnterKeyDefault;
    default:
        return QQuickItem::inputMethodQuery(query);
    }
}

static void sendKey(PacificWebView* view, ViewBackend* backend, Qt::Key key, const QString& text)
{
    Q_UNUSED(view)
    QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier, text);
    backend->dispatchKey(&press, true);
    QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier, text);
    backend->dispatchKey(&release, false);
}

void PacificWebView::inputMethodEvent(QInputMethodEvent* event)
{
    if (!m_backend || !m_imContext) {
        QQuickItem::inputMethodEvent(event);
        return;
    }
    const QString commit = event->commitString();
    const QString preedit = event->preeditString();

    // Maliit may deliver Enter as a committed newline. Only a native key
    // gives the trusted keydown and the default action (form submission).
    if (commit == QLatin1String("\n") || commit == QLatin1String("\r")) {
        if (!m_preedit.isEmpty() && m_inputMode == NativeInput)
            ImContext::commit(m_imContext, m_preedit);
        m_preedit.clear();
        sendKey(this, m_backend, Qt::Key_Return, QStringLiteral("\r"));
        event->accept();
        return;
    }

    if (m_inputMode == NativeInput) {
        if (event->replacementLength() > 0)
            ImContext::deleteSurrounding(m_imContext, event->replacementStart(), event->replacementLength());
        if (!commit.isEmpty() || (preedit.isEmpty() && !m_preedit.isEmpty()))
            ImContext::commit(m_imContext, commit);
        if (!preedit.isEmpty()) {
            int cursor = static_cast<int>(preedit.size());
            const auto& attributes = event->attributes();
            for (const QInputMethodEvent::Attribute& a : attributes) {
                if (a.type == QInputMethodEvent::Cursor)
                    cursor = a.start;
            }
            ImContext::setPreedit(m_imContext, preedit, cursor);
        }
        m_preedit = preedit;
        event->accept();
        return;
    }

    // ScriptInput (Atlantic's path): the preedit is typed into the field as
    // literal text and replaced by each update.
    auto insert = [this](const QString& text, int replaceBefore) {
        evaluate(QStringLiteral("window.__pacificIme&&__pacificIme.insert(%1,%2)").arg(jsonArgument(text)).arg(replaceBefore),
            kWorld, QJSValue());
    };
    int replaceBefore = static_cast<int>(m_preedit.size());
    if (event->replacementLength() > 0 && event->replacementStart() + event->replacementLength() == 0)
        replaceBefore = qMax(replaceBefore, event->replacementLength());
    if (!commit.isEmpty()) {
        insert(commit, replaceBefore);
        m_preedit.clear();
    } else if (!preedit.isEmpty()) {
        insert(preedit, replaceBefore);
        m_preedit = preedit;
    } else if (!m_preedit.isEmpty()) {
        insert(QString(), replaceBefore);
        m_preedit.clear();
    }
    event->accept();
}

// Back and forward belong to the window (Escape, Alt+Left, Alt+Right), as on
// Marathon's other apps: the page never gets them.
static bool isNavigationKey(const QKeyEvent* event)
{
    if (event->key() == Qt::Key_Escape)
        return true;
    return (event->modifiers() & Qt::AltModifier)
        && (event->key() == Qt::Key_Left || event->key() == Qt::Key_Right);
}

void PacificWebView::keyPressEvent(QKeyEvent* event)
{
    if (isNavigationKey(event)) {
        event->ignore();
        return;
    }
    if (!m_backend)
        return;
    // Soft keys carry no scan code. In ScriptInput mode their text goes in by
    // script like the rest of the keyboard's text.
    const bool soft = event->nativeScanCode() == 0;
    if (m_inputMode == ScriptInput && soft && m_im.focused && event->key() != Qt::Key_Return
        && event->key() != Qt::Key_Enter) {
        if (event->key() == Qt::Key_Backspace)
            evaluate(QStringLiteral("window.__pacificIme&&__pacificIme.backspace()"), kWorld, QJSValue());
        else if (!event->text().isEmpty())
            evaluate(QStringLiteral("window.__pacificIme&&__pacificIme.insert(%1,0)").arg(jsonArgument(event->text())),
                kWorld, QJSValue());
        event->accept();
        return;
    }
    if ((event->key() == Qt::Key_Return || event->key() == Qt::Key_Enter) && !m_preedit.isEmpty()
        && m_inputMode == NativeInput) {
        ImContext::commit(m_imContext, m_preedit);
        m_preedit.clear();
    }
    m_backend->dispatchKey(event, true);
    event->accept();
}

void PacificWebView::keyReleaseEvent(QKeyEvent* event)
{
    if (isNavigationKey(event)) {
        event->ignore();
        return;
    }
    if (!m_backend)
        return;
    if (m_inputMode == ScriptInput && event->nativeScanCode() == 0 && m_im.focused && event->key() != Qt::Key_Return
        && event->key() != Qt::Key_Enter) {
        event->accept();
        return;
    }
    m_backend->dispatchKey(event, false);
    event->accept();
}

void PacificWebView::focusInEvent(QFocusEvent* event)
{
    QQuickItem::focusInEvent(event);
    if (m_im.focused)
        QGuiApplication::inputMethod()->update(Qt::ImQueryAll);
}

void PacificWebView::focusOutEvent(QFocusEvent* event)
{
    QQuickItem::focusOutEvent(event);
    if (!m_preedit.isEmpty() && m_imContext && m_inputMode == NativeInput)
        ImContext::commit(m_imContext, m_preedit);
    m_preedit.clear();
}

namespace {
// Hover only from a pointer that can hover (a mouse or touchpad plugged into
// the phone, or a desktop). Qt Quick also sends hover moves at the last touch
// point after every touch; given to WebKit they left :hover on the link where
// a flick began, highlighted until the next tap elsewhere.
bool canHover()
{
    const auto devices = QInputDevice::devices();
    return std::any_of(devices.begin(), devices.end(), [](const QInputDevice* d) {
        return d->type() == QInputDevice::DeviceType::Mouse || d->type() == QInputDevice::DeviceType::TouchPad;
    });
}
}

void PacificWebView::hoverMoveEvent(QHoverEvent* event)
{
    const auto* device = event->pointingDevice();
    if (device && device->type() == QInputDevice::DeviceType::TouchScreen)
        return;
    if (m_backend && canHover())
        m_backend->dispatchHoverMove(event);
}

void PacificWebView::hoverLeaveEvent(QHoverEvent*)
{
    if (m_backend)
        m_backend->dispatchHoverLeave();
}

void PacificWebView::mousePressEvent(QMouseEvent* event)
{
    forceActiveFocus(Qt::MouseFocusReason);
    if (m_backend)
        m_backend->dispatchMousePress(event);
    event->accept();
}

void PacificWebView::mouseMoveEvent(QMouseEvent* event)
{
    if (m_backend)
        m_backend->dispatchMouseMove(event);
}

void PacificWebView::mouseReleaseEvent(QMouseEvent* event)
{
    if (m_backend)
        m_backend->dispatchMouseRelease(event);
}

void PacificWebView::wheelEvent(QWheelEvent* event)
{
    if (m_backend)
        m_backend->dispatchWheel(event);
    event->accept();
}

namespace {
// pacific-boostd (engine/boost): CPU and GPU clock floors while a page is
// touched or scrolls, as Android's power HAL gives the app in front. A
// datagram of the duration in ms on its abstract socket, at most every
// 150 ms. PACIFIC_BOOST=0 sends none.
void requestBoost(uint32_t ms)
{
    static const bool enabled = qgetenv("PACIFIC_BOOST") != "0";
    static int fd = -1;
    static QElapsedTimer last;
    if (!enabled || (last.isValid() && last.elapsed() < 150))
        return;
    if (fd < 0)
        fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0)
        return;
    static const char name[] = "org.shipwright.pacific.boost";
    sockaddr_un addr {};
    addr.sun_family = AF_UNIX;
    memcpy(addr.sun_path + 1, name, sizeof name - 1);
    sendto(fd, &ms, sizeof ms, 0, reinterpret_cast<sockaddr*>(&addr),
        static_cast<socklen_t>(offsetof(sockaddr_un, sun_path) + sizeof name));
    last.start();
}
}

void PacificWebView::endRefreshPull()
{
    if (!m_refreshPull.active)
        return;
    m_refreshPull.active = false;
    Q_EMIT pullEnded(m_refreshPull.distance, m_refreshPull.velocity);
    m_refreshPull.distance = 0;
}

void PacificWebView::trackPull(QTouchEvent* event)
{
    const auto& points = event->points();
    // Pull to refresh: follows the finger once the page has said it is at
    // its top; a second finger, the page scrolling or taking the drag, or
    // the finger lifting ends it.
    if (event->type() == QEvent::TouchBegin) {
        m_refreshPull.verdict = points.size() == 1 ? PullVerdict::Unknown : PullVerdict::No;
        m_refreshPull.active = false;
        m_refreshPull.distance = 0;
        m_refreshPull.velocity = 0;
        if (!points.isEmpty()) {
            m_refreshPull.last = points.first().position();
            m_refreshPull.lastAt = static_cast<qint64>(event->timestamp());
        }
    } else if (event->type() == QEvent::TouchEnd || event->type() == QEvent::TouchCancel || points.size() != 1) {
        if (points.size() != 1)
            m_refreshPull.verdict = PullVerdict::No;
        endRefreshPull();
    } else if (!points.isEmpty()) {
        const QPointF at = points.first().position();
        const auto now = static_cast<qint64>(event->timestamp());
        if (now > m_refreshPull.lastAt) {
            const qreal v = (at.y() - m_refreshPull.last.y()) / static_cast<qreal>(now - m_refreshPull.lastAt);
            m_refreshPull.velocity = 0.6 * v + 0.4 * m_refreshPull.velocity;
        }
        m_refreshPull.last = at;
        m_refreshPull.lastAt = now;
        const QPointF moved = at - m_pullStart;
        if (m_refreshPull.verdict == PullVerdict::Yes
            && (m_refreshPull.active || (moved.y() > 0 && moved.y() > std::abs(moved.x())))) {
            m_refreshPull.active = true;
            m_refreshPull.distance = std::max<qreal>(0, moved.y());
            Q_EMIT pullMoved(m_refreshPull.distance);
        }
    }

    if (event->type() == QEvent::TouchBegin) {
        m_pullDone = points.size() != 1;
        if (!points.isEmpty())
            m_pullStart = points.first().position();
        return;
    }
    if (m_pullDone)
        return;
    if (points.size() != 1) {
        m_pullDone = true; // a second finger: a pinch, not a pull
        return;
    }
    const QPointF moved = points.first().position() - m_pullStart;
    if (moved.y() > m_pullDistance && moved.y() > std::abs(moved.x())) {
        m_pullDone = true;
        Q_EMIT pulledDown();
    }
}

QPointF PacificWebView::swipePoint(const QEventPoint& point) const
{
    return m_swipeFrame ? m_swipeFrame->mapFromScene(point.scenePosition()) : point.position();
}

bool PacificWebView::trackSwipeNav(QTouchEvent* event)
{
    // In swipeFrame's coordinates: the page follows the finger (the UI moves
    // the view), so in the view's own the finger hardly moved.
    const auto& points = event->points();
    const auto now = static_cast<qint64>(event->timestamp());
    if (event->type() == QEvent::TouchBegin) {
        m_swipeNav.state = points.size() == 1 && m_swipeNavEnabled && !pageZoomedIn()
                && (canGoBack() || canGoForward())
            ? SwipeState::Undecided : SwipeState::No;
        m_swipeNav.pageAnswered = false;
        m_swipeNav.back = m_swipeNav.forward = false;
        m_swipeNav.dx = m_swipeNav.velocity = 0;
        if (!points.isEmpty()) {
            m_swipeNav.start = swipePoint(points.first());
            m_swipeNav.lastX = m_swipeNav.start.x();
        }
        m_swipeNav.lastAt = now;
        return false;
    }
    const bool ending = event->type() == QEvent::TouchEnd || event->type() == QEvent::TouchCancel;
    if (m_swipeNav.state == SwipeState::Swiping) {
        if (ending || points.size() != 1) {
            m_swipeNav.state = SwipeState::No;
            Q_EMIT swipeNavEnded(m_swipeNav.dx, event->type() == QEvent::TouchCancel ? 0 : m_swipeNav.velocity);
            return true;
        }
        const qreal x = swipePoint(points.first()).x();
        if (now > m_swipeNav.lastAt) {
            const qreal v = (x - m_swipeNav.lastX) / static_cast<qreal>(now - m_swipeNav.lastAt);
            m_swipeNav.velocity = 0.6 * v + 0.4 * m_swipeNav.velocity;
        }
        m_swipeNav.lastX = x;
        m_swipeNav.lastAt = now;
        m_swipeNav.dx = x - m_swipeNav.startX;
        Q_EMIT swipeNavMoved(m_swipeNav.dx);
        return true;
    }
    if (m_swipeNav.state != SwipeState::Undecided)
        return false;
    if (ending || points.size() != 1) {
        m_swipeNav.state = SwipeState::No;
        return false;
    }
    // Decided once the finger has gone 12 dp (past WebKit's own 8 dp touch
    // slop, so the touch the page gets ends as a drag, never a tap): mostly
    // sideways, with the page's word that it cannot use the drag, is a
    // swipe; anything else is the page's.
    const QPointF moved = swipePoint(points.first()) - m_swipeNav.start;
    const qreal slop = 12 * qMax<qreal>(1, window() && window()->screen()
            ? window()->screen()->physicalDotsPerInch() / 160 : 1);
    if (std::abs(moved.x()) < slop && std::abs(moved.y()) < slop)
        return false;
    if (!m_swipeNav.pageAnswered)
        return false; // still waiting for scroll.js; the page has it meanwhile
    const bool sideways = std::abs(moved.x()) > 2 * std::abs(moved.y());
    const bool wanted = moved.x() > 0 ? m_swipeNav.back && canGoBack() : m_swipeNav.forward && canGoForward();
    if (!sideways || !wanted || m_refreshPull.active) {
        m_swipeNav.state = SwipeState::No;
        return false;
    }
    // The browser's from here: the page gets the end of its touch.
    m_swipeNav.state = SwipeState::Swiping;
    m_swipeNav.startX = m_swipeNav.start.x() + (moved.x() > 0 ? slop : -slop);
    m_swipeNav.lastX = swipePoint(points.first()).x();
    m_swipeNav.lastAt = now;
    m_swipeNav.dx = m_swipeNav.lastX - m_swipeNav.startX;
    if (m_backend) {
        QTouchEvent end(QEvent::TouchEnd, event->pointingDevice(), event->modifiers(), points);
        end.setTimestamp(event->timestamp());
        m_backend->dispatchTouch(&end);
    }
    Q_EMIT swipeNavMoved(m_swipeNav.dx);
    return true;
}

void PacificWebView::trackCatch(QTouchEvent* event)
{
    const auto& points = event->points();
    const auto at = static_cast<qint64>(event->timestamp());
    if (event->type() == QEvent::TouchBegin) {
        static const double friction = [] {
            const double v = qEnvironmentVariable("WEBKIT_KINETIC_DECEL_FRICTION").toDouble();
            return v >= 0.3 && v <= 8.0 ? v : 4.0;
        }();
        const double sinceLift = m_catch.lift.isValid() ? m_catch.lift.elapsed() / 1000.0 : 1e9;
        // Still moving by the model (a pixel a frame at 90 Hz), or frames
        // still coming within 4 s of a flick.
        const bool modelled = m_catch.liftSpeed * std::exp(-friction * sinceLift) > 0.09;
        const bool framesFlowing = m_catch.frame.isValid() && m_catch.frame.elapsed() < 40 && m_catch.liftSpeed > 0.3
            && sinceLift < 4.0;
        m_catch.caught = points.size() == 1 && (modelled || framesFlowing);
        static const bool debug = qEnvironmentVariableIsSet("PACIFIC_DEBUG_CATCH");
        if (debug)
            qInfo("Pacific catch: lift %.2f px/ms %.0f ms ago, frame %lld ms ago: %s", m_catch.liftSpeed, sinceLift * 1000,
                m_catch.frame.isValid() ? static_cast<long long>(m_catch.frame.elapsed()) : -1LL,
                m_catch.caught ? "caught" : "not caught");
        m_catch.down = true;
        m_catch.speed = 0;
        m_catch.liftSpeed = 0;
        if (!points.isEmpty())
            m_catch.lastPos = points.first().position();
        m_catch.lastAt = at;
        return;
    }
    if (points.size() != 1) {
        m_catch.speed = 0;
    } else if (event->type() == QEvent::TouchUpdate && at > m_catch.lastAt) {
        const QPointF pos = points.first().position();
        const qreal v = QLineF(m_catch.lastPos, pos).length() / static_cast<qreal>(at - m_catch.lastAt);
        // About the last 50 ms (a move every 8-11 ms).
        m_catch.speed = 0.7 * m_catch.speed + 0.3 * v;
        m_catch.lastPos = pos;
        m_catch.lastAt = at;
    }
    if (event->type() == QEvent::TouchEnd || event->type() == QEvent::TouchCancel) {
        m_catch.down = false;
        m_catch.up.start();
        // A finger that rested before lifting does not fling (patch 0018).
        m_catch.liftSpeed = at - m_catch.lastAt <= 40 ? m_catch.speed : 0;
        m_catch.lift.start();
    }
}

bool PacificWebView::catchActive() const
{
    return m_catch.caught && (m_catch.down || (m_catch.up.isValid() && m_catch.up.elapsed() < 600));
}

void PacificWebView::touchEvent(QTouchEvent* event)
{
    requestBoost(1000);
    if (event->type() == QEvent::TouchBegin)
        forceActiveFocus(Qt::MouseFocusReason);
    trackPull(event);
    trackCatch(event);
    if (trackSwipeNav(event)) {
        event->accept();
        return;
    }
    if (handlePinch(event)) {
        event->accept();
        return;
    }
    if (m_backend)
        m_backend->dispatchTouch(event);
    event->accept();
}

namespace {
using SetPageScaleFn = void (*)(WebKitWebView*, double, int, int);
using GetPageScaleFn = double (*)(WebKitWebView*);
// Atlantic's engine patch (webkit-wpe-page-scale-api); absent: no pinch.
SetPageScaleFn setPageScaleFn()
{
    static const auto fn = reinterpret_cast<SetPageScaleFn>(engineSymbol("wpe_sfos_set_page_scale"));
    return fn;
}
GetPageScaleFn getPageScaleFn()
{
    static const auto fn = reinterpret_cast<GetPageScaleFn>(engineSymbol("wpe_sfos_get_page_scale"));
    return fn;
}
constexpr double kMinPageScale = 1.0;
constexpr double kMaxPageScale = 5.0;
// The fingers must spread or close this much before the browser takes the
// gesture, so a page that handles two fingers (maps) can say so first.
constexpr qreal kPinchStart = 0.05;
constexpr qint64 kPinchWaitMs = 100;
}

// How far the fingers' midpoint moved during the pinch. Nothing at no
// scale change (a pinch held at the limit): there the page stays put, and
// the anchor below could not be placed.
QPointF PacificWebView::pinchPan() const
{
    const qreal v = m_pinch.visual;
    if (std::abs(v - 1) < 0.02)
        return {};
    QPointF pan = m_pinch.fingers - m_pinch.center;
    if (!m_pinch.haveBounds)
        return pan;
    // Where the document's edges land: c + (edge - c) * v + pan. WebKit
    // keeps them outside the view (the page covers it), and a page smaller
    // than the view at its top left; the preview does the same, so the
    // committed scale settles where the preview shows.
    const QPointF c = m_pinch.center;
    const QRectF& d = m_pinch.document;
    const QSizeF view = boundingRect().size();
    auto clampAxis = [v](qreal pan, qreal center, qreal lo, qreal hi, qreal extent) {
        const qreal loAt = center + (lo - center) * v; // without pan
        const qreal hiAt = center + (hi - center) * v;
        if (hiAt - loAt <= extent)
            return -loAt; // smaller than the view: pinned at the start
        return std::clamp(pan, extent - hiAt, -loAt);
    };
    pan.setX(clampAxis(pan.x(), c.x(), d.left(), d.right(), view.width()));
    pan.setY(clampAxis(pan.y(), c.y(), d.top(), d.bottom(), view.height()));
    return pan;
}

void PacificWebView::fetchPinchBounds()
{
    static const QByteArray script = QByteArrayLiteral(
        "(function(){var v=window.visualViewport,d=document.documentElement,b=document.body;"
        "return [v.pageLeft,v.pageTop,v.width,Math.max(d.scrollWidth,b?b.scrollWidth:0),"
        "Math.max(d.scrollHeight,b?b.scrollHeight:0)].join(',')})()");
    m_pinch.haveBounds = false;
    webkit_web_view_evaluate_javascript(m_webView, script.constData(), script.size(), kWorld, nullptr, nullptr,
        [](GObject* object, GAsyncResult* result, gpointer data) {
            auto* guard = static_cast<QPointer<PacificWebView>*>(data);
            QPointer<PacificWebView> self = *guard;
            delete guard;
            JSCValue* value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(object), result, nullptr);
            if (!value)
                return;
            gchar* text = jsc_value_to_string(value);
            const QStringList parts = QString::fromUtf8(text).split(QLatin1Char(','));
            g_free(text);
            g_object_unref(value);
            if (!self || parts.size() != 5 || !(self->m_pinch.active || self->m_pinch.committing))
                return;
            const qreal pageLeft = parts[0].toDouble(), pageTop = parts[1].toDouble();
            const qreal cssWidth = parts[2].toDouble(), docWidth = parts[3].toDouble(), docHeight = parts[4].toDouble();
            if (cssWidth <= 0)
                return;
            // Item px per CSS px at the scale the pinch began at.
            const qreal k = self->boundingRect().width() / cssWidth;
            self->m_pinch.document = QRectF(-pageLeft * k, -pageTop * k, docWidth * k, docHeight * k);
            self->m_pinch.haveBounds = true;
            self->update();
        },
        new QPointer<PacificWebView>(this));
}

void PacificWebView::finishPinch()
{
    m_pinch.active = false;
    m_pinch.swallow = false;
    // WebKit renders the final scale once, anchored where the preview was
    // (view coordinates, CSS-to-device); the preview stays until it arrives.
    if (!qFuzzyCompare(m_pinch.visual, 1.0)) {
        // WebKit keeps the point under the anchor where it is. The preview
        // scaled about `center` and then moved with the fingers by `pan`:
        // the one point that stayed put is center + pan / (1 - v), so the
        // page settles exactly where the preview left it.
        const qreal v = m_pinch.visual;
        const QPointF anchor = m_pinch.center + pinchPan() / (1 - v);
        const QPointF center = anchor * (itemToPhysical() / effectiveContentScale());
        setPageScaleFn()(m_webView, m_pinch.lastScale, qRound(center.x()), qRound(center.y()));
        m_pinch.committing = true;
        m_pinch.committed.start();
        m_pinch.showFinal = false;
        m_pinch.snapshotWanted = true;
        update();
        // Which frame shows the new scale: the page answers after three
        // animation frames, by when it has drawn at the scale (its message
        // came before this one) and that frame has reached us; the newest
        // frame then is at it, and on a still page no other may come. The
        // scale WebKit reports changes as soon as it is asked for, and the
        // first frame to arrive could be an older one: the page showed
        // unzoomed for a moment, then zoomed again.
        m_pinch.awaitSerial = std::numeric_limits<quint64>::max();
        static const char kTwoFrames[] =
            "await new Promise(function(r){requestAnimationFrame(function(){requestAnimationFrame(function()"
            "{requestAnimationFrame(r)})})});return 1;";
        webkit_web_view_call_async_javascript_function(m_webView, kTwoFrames, -1, nullptr, kWorld, nullptr, nullptr,
            [](GObject* object, GAsyncResult* result, gpointer data) {
                auto* guard = static_cast<QPointer<PacificWebView>*>(data);
                QPointer<PacificWebView> self = *guard;
                delete guard;
                if (JSCValue* value = webkit_web_view_call_async_javascript_function_finish(WEBKIT_WEB_VIEW(object), result, nullptr))
                    g_object_unref(value);
                if (!self || !self->m_pinch.committing || !self->m_backend)
                    return;
                self->m_pinch.awaitSerial = std::max<quint64>(1, self->m_backend->arrivedSerial());
                self->update();
            },
            new QPointer<PacificWebView>(this));
        // However WebKit takes, the preview ends.
        QTimer::singleShot(1500, this, [this] {
            if (m_pinch.committing)
                endPinchVisual();
        });
    } else {
        endPinchVisual();
    }
    // Scaling about the fingers can leave the page scrolled outside its
    // bounds; back at 1:1 it must line up with the view again.
    if (m_pinch.lastScale <= kMinPageScale + 0.01)
        evaluate(QStringLiteral("window.scrollTo(0, Math.max(0, window.scrollY))"), kWorld, QJSValue());
}

void PacificWebView::endPinchVisual()
{
    m_pinch.committing = false;
    m_pinch.showFinal = false;
    m_pinch.snapshotWanted = false;
    m_pinch.haveSnapshot = false;
    Q_EMIT zoomingChanged();
    m_pinch.visual = 1;
    setClip(false);
    update();
    updateDirect();
}

void PacificWebView::updateFrameFits()
{
    const bool fits = m_lastFrameSize.isEmpty() || ViewBackend::sizeFits(m_lastFrameSize, physicalSize());
    if (fits == m_frameFitsView)
        return;
    m_frameFitsView = fits;
    Q_EMIT frameFitsViewChanged();
}

void PacificWebView::endPageChangeOnNextFrame()
{
    if (!m_pageBlanked || m_paintedPending)
        return;
    m_paintedPending = true;
    QTimer::singleShot(1000, this, [this, serial = m_pageChangeSerial] {
        if (serial == m_pageChangeSerial && m_paintedPending) {
            m_loadTrace.mark("page change ended without a frame");
            setPageBlanked(false);
        }
    });
}

void PacificWebView::setPageBlanked(bool blanked)
{
    if (blanked == m_pageBlanked)
        return;
    m_pageBlanked = blanked;
    m_paintedPending = false;
    ++m_pageChangeSerial;
    Q_EMIT pageBlankedChanged();
}

void PacificWebView::webFrameArrived(QSize frameSize)
{
    if (m_paintedPending) {
        m_paintedPending = false;
        m_loadTrace.mark("painted frame");
        setPageBlanked(false);
    }
    if (m_loadTrace.committed && !m_loadTrace.painted && m_loadTrace.clock.isValid()) {
        m_loadTrace.painted = true;
        qInfo("Pacific load: first frame %lld ms", static_cast<long long>(m_loadTrace.clock.elapsed()));
    }
    m_catch.frame.start();
    m_lastFrameSize = frameSize;
    updateFrameFits();
}

// Returns true when the event belongs to a pinch and is not for the page.
bool PacificWebView::handlePinch(QTouchEvent* event)
{
    if (!m_webView || !m_backend || !setPageScaleFn() || !getPageScaleFn())
        return false;
    if (event->type() == QEvent::TouchBegin) {
        m_pinch.pageConsumes = false;
        m_pinch.active = false;
        m_pinch.swallow = false;
        m_pinch.startDistance = 0;
    }
    const bool ending = event->type() == QEvent::TouchEnd || event->type() == QEvent::TouchCancel;
    if (m_pinch.swallow) {
        if (ending)
            m_pinch.swallow = false;
        return true;
    }
    QList<QEventPoint> down;
    for (const QEventPoint& point : event->points()) {
        if (point.state() != QEventPoint::Released)
            down.append(point);
    }
    static const bool debugPinch = qEnvironmentVariableIsSet("PACIFIC_DEBUG_PINCH");
    if (debugPinch && down.size() >= 2)
        qInfo("Pacific pinch: %d fingers, page consumes %d, active %d", static_cast<int>(down.size()), m_pinch.pageConsumes, m_pinch.active);
    if (down.size() < 2 || m_pinch.pageConsumes) {
        if (m_pinch.active) {
            // A finger lifted: the pinch is over; the other finger must not
            // pan or tap the page.
            finishPinch();
            m_pinch.swallow = !ending;
            return true;
        }
        m_pinch.startDistance = 0;
        return false;
    }
    const QPointF a = down.at(0).position();
    const QPointF b = down.at(1).position();
    const qreal distance = QLineF(a, b).length();
    if (distance < 1)
        return m_pinch.active;
    if (!m_pinch.active) {
        if (m_pinch.startDistance <= 0) {
            m_pinch.startDistance = distance;
            m_pinch.since.start();
            return false;
        }
        // The page says whether it handles two fingers from its touchstart
        // handler, a few milliseconds later: wait for that before taking them.
        if (qAbs(distance / m_pinch.startDistance - 1) < kPinchStart || m_pinch.since.elapsed() < kPinchWaitMs)
            return false;
        // The browser's pinch: the page loses these fingers.
        QTouchEvent cancel(QEvent::TouchCancel, event->pointingDevice(), event->modifiers(), event->points());
        m_backend->dispatchTouch(&cancel);
        m_pinch.active = true;
        m_pinch.committing = false;
        Q_EMIT zoomingChanged();
        m_pinch.startScale = getPageScaleFn()(m_webView);
        m_pinch.center = (a + b) / 2;
        m_pinch.fingers = m_pinch.center;
        fetchPinchBounds();
        // Frames go through Qt while the preview is scaled.
        setClip(true);
        updateDirect();
    }
    const double scale = std::clamp(m_pinch.startScale * distance / m_pinch.startDistance, kMinPageScale, kMaxPageScale);
    m_pinch.lastScale = scale;
    m_pinch.visual = scale / m_pinch.startScale;
    m_pinch.fingers = (a + b) / 2;
    update();
    if (ending)
        finishPinch();
    return true;
}

bool PacificWebView::pageZoomedIn() const
{
    return m_webView && getPageScaleFn() && getPageScaleFn()(m_webView) > 1.01;
}
