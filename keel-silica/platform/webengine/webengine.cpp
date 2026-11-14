// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "webengine.h"

#include "permissionstore.h"
#include "security.h"

#include <QCoreApplication>
#include <QTranslator>

#include <QClipboard>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QLoggingCategory>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QScreen>
#include <QTimer>

#include <cmath>
#include <memory>

Q_LOGGING_CATEGORY(lcKeelWebEngine, "keel.webengine")

// ---------------------------------------------------------------------------
// WebEngine
// ---------------------------------------------------------------------------

namespace {

// Engineering English for the qsTrId()s of sailfish-components-webview's
// QML (Sailfish.WebView.Popups, .Pickers, .Controls), which Keel has no
// compiled catalogues for. Answers only those ids; an empty answer passes
// the question on to the next translator.
class WebViewFallbackTranslator : public QTranslator
{
public:
    using QTranslator::QTranslator;
    bool isEmpty() const override { return false; }
    QString translate(const char *context, const char *sourceText, const char *disambiguation,
                      int n) const override
    {
        Q_UNUSED(disambiguation)
        Q_UNUSED(n)
        if (context && *context)
            return {};
        struct Entry
        {
            const char *id;
            const char *text;
        };
        static const Entry strings[] = {
#include "webviewstrings.inc"
        };
        static const QHash<QByteArray, QString> table = [] {
            QHash<QByteArray, QString> t;
            for (const Entry &e : strings)
                t.insert(e.id, QString::fromUtf8(e.text));
            return t;
        }();
        return table.value(QByteArray(sourceText));
    }
};

void installWebViewTranslations()
{
    static bool installed = false;
    QCoreApplication *app = QCoreApplication::instance();
    if (installed || !app)
        return;
    installed = true;
    QCoreApplication::installTranslator(new WebViewFallbackTranslator(app));
}

QPointer<WebEngine> &latestInstance()
{
    static QPointer<WebEngine> instance;
    return instance;
}
} // namespace

WebEngine::WebEngine(QObject *parent)
    : QObject(parent)
    , m_permissions(std::make_unique<KeelPermissionStore>())
{
    latestInstance() = this;
    installWebViewTranslations();
}

WebEngine::~WebEngine()
{
    if (!m_contextDestroyed)
        emit contextDestroyed();
}

WebEngine *WebEngine::instance()
{
    return latestInstance();
}

int WebEngine::_keelPermission(const QString &host, const QString &type) const
{
    return m_permissions->capability(host, type);
}

void WebEngine::_keelRememberPermission(const QString &host, const QString &type, bool allow, bool session)
{
    m_permissions->add(host, type, allow ? KeelPermissionStore::Allow : KeelPermissionStore::Deny,
                       session ? KeelPermissionStore::Session : KeelPermissionStore::Never);
}

// Gecko's permission requests ("embedui:perms" with msg add, remove, get-all,
// get-all-for-uri) as Sailfish.WebView.Controls sends them; answered with
// "embed:perms:all" and "embed:perms:all-for-uri".
void WebEngine::handlePermissionRequest(const QVariantMap &request)
{
    const QString msg = request.value(QStringLiteral("msg")).toString();
    const QString uri = request.value(QStringLiteral("uri")).toString();
    const QString type = request.value(QStringLiteral("type")).toString();
    if (msg == QLatin1String("add")) {
        m_permissions->add(uri, type, request.value(QStringLiteral("permission")).toInt(),
                           request.value(QStringLiteral("expireType")).toInt());
    } else if (msg == QLatin1String("remove")) {
        m_permissions->remove(uri, type);
    } else if (msg == QLatin1String("get-all")) {
        reply(QStringLiteral("embed:perms:all"), m_permissions->all());
    } else if (msg == QLatin1String("get-all-for-uri")) {
        reply(QStringLiteral("embed:perms:all-for-uri"), m_permissions->allForUri(uri));
    }
}

// Answered whether or not the topic is observed: Sailfish.WebView.Controls'
// PermissionModel asks before (or without) a PermissionManager observing.
void WebEngine::reply(const QString &topic, const QVariant &value)
{
    QTimer::singleShot(0, this, [this, topic, value]() { emit recvObserve(topic, value); });
}

void WebEngine::setKeelProfile(QObject *profile)
{
    if (m_profile == profile)
        return;
    m_profile = profile;
    // The singleton owns the shared profile (created by QML with no parent).
    if (profile) {
        profile->setParent(this);
        QQmlEngine::setObjectOwnership(profile, QQmlEngine::CppOwnership);
    }
    emit keelProfileChanged();
}

QString WebEngine::keelBackend() const
{
    QString forced = qEnvironmentVariable("KEEL_WEBVIEW_BACKEND");
    if (!forced.isEmpty())
        return forced;
    // Looked up rather than tried, so a missing Qt WebEngine is no QML error.
    if (const QQmlEngine *engine = qmlEngine(this)) {
        const QStringList paths = engine->importPathList();
        for (const QString &path : paths) {
            if (QFileInfo::exists(path + QStringLiteral("/QtWebEngine/qmldir")))
                return QStringLiteral("qtwebengine");
        }
    }
    return QStringLiteral("external");
}

void WebEngine::addComponentManifest(const QString &manifestPath)
{
    qCWarning(lcKeelWebEngine) << "addComponentManifest: Gecko JavaScript components are not supported on Keel;"
                               << manifestPath << "is not loaded";
}

namespace {

const QByteArray DisableGpu = QByteArrayLiteral("--disable-gpu");

QList<QByteArray> chromiumFlags()
{
    QList<QByteArray> flags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS").split(' ');
    flags.removeAll(QByteArray());
    return flags;
}

} // namespace

// Chromium renders with the GPU unless it is told not to (--disable-gpu) or
// Qt Quick itself renders in software.
bool WebEngine::isAccelerated() const
{
    if (chromiumFlags().contains(DisableGpu))
        return false;
    return QQuickWindow::graphicsApi() != QSGRendererInterface::Software;
}

// Chromium reads its flags when Qt WebEngine starts (the app's first
// WebView); a change after that applies from the next start.
void WebEngine::setIsAccelerated(bool accelerated)
{
    if (m_engineStarted) {
        qCWarning(lcKeelWebEngine) << "setIsAccelerated: Qt WebEngine has started; the change applies from the next app start";
        return;
    }
    m_accelerated = accelerated;
    QList<QByteArray> flags = chromiumFlags();
    flags.removeAll(DisableGpu);
    if (!m_accelerated)
        flags.append(DisableGpu);
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags.join(' '));
}

// The style sheet's text: read here for local files (a page may not load
// file: URLs), an @import for the others.
void WebEngine::addUserStyleSheet(const QUrl &url)
{
    if (!url.isValid() || url.isEmpty())
        return;
    for (const auto &sheet : std::as_const(m_styleSheets)) {
        if (sheet.first == url)
            return;
    }
    QString css = _keelReadText(url);
    if (css.isEmpty() && !url.isLocalFile() && url.scheme() != QLatin1String("qrc"))
        css = QStringLiteral("@import url(\"%1\");").arg(url.toString(QUrl::FullyEncoded));
    if (css.isEmpty()) {
        qCWarning(lcKeelWebEngine) << "addUserStyleSheet: cannot read" << url;
        return;
    }
    m_styleSheets.append({ url, css });
    emit keelUserStyleSheetsChanged();
}

void WebEngine::removeUserStyleSheet(const QUrl &url)
{
    if (m_styleSheets.removeIf([&](const QPair<QUrl, QString> &sheet) { return sheet.first == url; }) > 0)
        emit keelUserStyleSheetsChanged();
}

QStringList WebEngine::keelUserStyleSheets() const
{
    QStringList sheets;
    for (const auto &sheet : m_styleSheets)
        sheets.append(sheet.second);
    return sheets;
}

// Qt WebEngine starts with the first WebView; nothing to start here.
void WebEngine::runEmbedding(int aDelay)
{
    Q_UNUSED(aDelay)
    m_stopping = false;
}

// Reports contextDestroyed once the app's WebViews are gone (at once if
// there are none); Qt WebEngine itself stops with the application.
void WebEngine::stopEmbedding()
{
    m_stopping = true;
    if (m_views == 0) {
        QTimer::singleShot(0, this, [this]() {
            if (m_stopping && m_views == 0 && !m_contextDestroyed) {
                m_contextDestroyed = true;
                emit contextDestroyed();
            }
        });
    }
}

void WebEngine::notifyFirstUIInitialized()
{
    notifyObservers(QStringLiteral("final-ui-startup"), QVariant());
}

void WebEngine::_keelViewCreated()
{
    ++m_views;
    m_engineStarted = true;
}

void WebEngine::_keelViewDestroyed()
{
    if (m_views == 0)
        return;
    --m_views;
    if (m_views > 0)
        return;
    emit lastWindowDestroyed();
    if (m_stopping)
        stopEmbedding();
}

QString WebEngine::_keelReadText(const QUrl &url) const
{
    QString path;
    if (url.isLocalFile())
        path = url.toLocalFile();
    else if (url.scheme() == QLatin1String("qrc"))
        path = QLatin1Char(':') + url.path();
    else if (url.isRelative() && !url.path().isEmpty())
        path = url.path();
    if (path.isEmpty())
        return {};
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(file.readAll());
}

// Gecko's "clipboard:setdata": { data, private }. Qt WebEngine has put the
// text on the system clipboard by the time the page's copy event is over.
void WebEngine::_keelClipboardSet(bool privateMode)
{
    QTimer::singleShot(50, this, [this, privateMode]() {
        const QClipboard *clipboard = QGuiApplication::clipboard();
        if (!clipboard)
            return;
        QVariantMap data;
        data.insert(QStringLiteral("data"), clipboard->text());
        data.insert(QStringLiteral("private"), privateMode);
        notifyObservers(QStringLiteral("clipboard:setdata"), data);
    });
}

QObject *WebEngine::_keelCreateSecurity(QObject *parent)
{
    auto *security = new KeelSecurity(parent);
    QQmlEngine::setObjectOwnership(security, QQmlEngine::CppOwnership);
    return security;
}

void WebEngine::addObserver(const QString &aTopic)
{
    ++m_topics[aTopic];
}

void WebEngine::removeObserver(const QString &aTopic)
{
    auto it = m_topics.find(aTopic);
    if (it != m_topics.end() && --it.value() <= 0)
        m_topics.erase(it);
}

void WebEngine::notifyObservers(const QString &topic, const QVariant &value)
{
    if (topic == QLatin1String("embedui:perms")) {
        handlePermissionRequest(value.toMap());
        return;
    }
    if (topic == QLatin1String("embedui:download")) {
        const QVariantMap download = value.toMap();
        if (download.value(QStringLiteral("msg")).toString() == QLatin1String("addDownload"))
            emit _keelDownloadRequested(download);
    }
    if (!m_topics.contains(topic))
        return;
    // Asynchronous, as a notification through the engine would be.
    QTimer::singleShot(0, this, [this, topic, value]() {
        if (m_topics.contains(topic))
            emit recvObserve(topic, value);
    });
}

// ---------------------------------------------------------------------------
// WebEngineSettings
// ---------------------------------------------------------------------------

namespace {

// Sets `member` and emits `changed` if the value differs.
template<typename T>
void assign(WebEngineSettings *self, T &member, const T &v, void (WebEngineSettings::*changed)())
{
    if (member == v)
        return;
    member = v;
    emit(self->*changed)();
}

} // namespace

void WebEngineSettings::setAutoLoadImages(bool v)
{
    assign(this, m_autoLoadImages, v, &WebEngineSettings::autoLoadImagesChanged);
}

void WebEngineSettings::setColorScheme(int v)
{
    assign(this, m_colorScheme, v, &WebEngineSettings::colorSchemeChanged);
}

void WebEngineSettings::setCookieBehavior(CookieBehavior v)
{
    assign(this, m_cookieBehavior, v, &WebEngineSettings::cookieBehaviorChanged);
}

void WebEngineSettings::setDoNotTrack(bool v)
{
    assign(this, m_doNotTrack, v, &WebEngineSettings::doNotTrackChanged);
}

void WebEngineSettings::setDownloadDir(const QString &v)
{
    assign(this, m_downloadDir, v, &WebEngineSettings::downloadDirChanged);
}

void WebEngineSettings::setJavascriptEnabled(bool v)
{
    assign(this, m_javascriptEnabled, v, &WebEngineSettings::javascriptEnabledChanged);
}

namespace {

// Whether the primary screen is a whole number of CSS pixels wide and high
// at this ratio.
bool wholeCssPixels(const QScreen *screen, qreal ratio)
{
    const QSize size = screen->size();
    return std::fmod(size.width() / ratio, 1.0) == 0 && std::fmod(size.height() / ratio, 1.0) == 0;
}

// Silica's Theme.pixelRatio, read through the engine (1.0 without Silica).
qreal themePixelRatio(QQmlEngine *engine)
{
    if (!engine)
        return 1.0;
    QQmlComponent component(engine);
    component.setData("import QtQml 2.0\nimport Sailfish.Silica 1.0\n"
                      "QtObject { readonly property real ratio: Theme.pixelRatio }",
                      QUrl());
    const std::unique_ptr<QObject> object(component.create());
    const qreal ratio = object ? object->property("ratio").toReal() : 0;
    return ratio > 0 ? ratio : 1.0;
}

} // namespace

qreal WebEngineSettings::pixelRatio() const
{
    if (m_pixelRatio > 0)
        return m_pixelRatio;
    if (m_defaultPixelRatio <= 0) {
        // Sailfish's documented behaviour (pixelRatio follows the theme),
        // with its rounding: 0.5 steps; whole steps where the screen would
        // not be a whole number of CSS pixels at 2 or more, or on screens
        // 1080 pixels wide and wider.
        qreal ratio = qRound(1.5 * themePixelRatio(qmlEngine(this)) / 0.5) * 0.5;
        if (const QScreen *screen = QGuiApplication::primaryScreen()) {
            if (ratio >= 2.0 && !wholeCssPixels(screen, ratio)) {
                if (wholeCssPixels(screen, std::floor(ratio)))
                    ratio = std::floor(ratio);
            } else if (screen->size().width() >= 1080) {
                ratio = qRound(ratio);
            }
        }
        m_defaultPixelRatio = ratio;
    }
    return m_defaultPixelRatio;
}

void WebEngineSettings::setPixelRatio(qreal v)
{
    if (v <= 0 || qFuzzyCompare(pixelRatio(), v))
        return;
    m_pixelRatio = v;
    emit pixelRatioChanged();
}

void WebEngineSettings::setPopupEnabled(bool v)
{
    assign(this, m_popupEnabled, v, &WebEngineSettings::popupEnabledChanged);
}

void WebEngineSettings::setUseDownloadDir(bool v)
{
    assign(this, m_useDownloadDir, v, &WebEngineSettings::useDownloadDirChanged);
}

bool WebEngineSettings::localContentCanAccessRemoteUrls() const
{
    return m_preferences.value(QStringLiteral("security.disable_cors_checks")).toBool();
}

bool WebEngineSettings::localContentCanAccessFileUrls() const
{
    // Qt WebEngine's default is true; Gecko's strict file origin policy
    // (the default) is closer to false, but Keel keeps Qt's default unless
    // the app sets the preference.
    const QVariant strict = m_preferences.value(QStringLiteral("security.fileuri.strict_origin_policy"));
    return !strict.isValid() || !strict.toBool() || localContentCanAccessRemoteUrls();
}

QString WebEngineSettings::userAgentOverride() const
{
    return m_preferences.value(QStringLiteral("general.useragent.override")).toString();
}

void WebEngineSettings::setPreference(const QString &key, const QVariant &value, int type)
{
    QVariant v = value;
    switch (type) {
    case StringPref:
        v = value.toString();
        break;
    case IntPref:
        v = value.toInt();
        break;
    case BoolPref:
        v = value.toBool();
        break;
    default:
        break;
    }
    m_preferences.insert(key, v);
    if (key == QLatin1String("javascript.enabled"))
        setJavascriptEnabled(v.toBool());
    else if (key == QLatin1String("permissions.default.image"))
        setAutoLoadImages(v.toInt() != 2); // 2: block
    else if (key == QLatin1String("dom.disable_open_during_load"))
        setPopupEnabled(!v.toBool());
    else if (key == QLatin1String("network.cookie.cookieBehavior"))
        setCookieBehavior(static_cast<CookieBehavior>(qBound(0, v.toInt(), 2)));
    else if (key == QLatin1String("privacy.donottrackheader.enabled"))
        setDoNotTrack(v.toBool());
    else if (key == QLatin1String("browser.download.dir"))
        setDownloadDir(v.toString());
    else if (key == QLatin1String("browser.download.useDownloadDir"))
        setUseDownloadDir(v.toBool());
    else if (key == QLatin1String("layout.css.devPixelsPerPx"))
        setPixelRatio(v.toReal());
    emit preferencesChanged();
}
