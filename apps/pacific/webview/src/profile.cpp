// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "profile.h"

#include "bridges.h"
#include "requests.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLocale>
#include <QPointer>
#include <QScreen>
#include <QStandardPaths>

#include <dlfcn.h>
#include <memory>

namespace {

struct JsCall {
    QPointer<QObject> owner;
    QJSValue callback;
};

void callBack(JsCall* call, const QJSValueList& args)
{
    if (call->owner && call->callback.isCallable())
        call->callback.call(args);
    delete call;
}

QByteArrayList toUtf8List(const QStringList& list)
{
    QByteArrayList out;
    for (const QString& s : list)
        out.append(s.toUtf8());
    return out;
}

// NULL-terminated array view over a QByteArrayList that the caller keeps.
QList<const gchar*> toStrv(const QByteArrayList& list)
{
    QList<const gchar*> out;
    for (const QByteArray& s : list)
        out.append(s.constData());
    out.append(nullptr);
    return out;
}

} // namespace

WebProfile::WebProfile(QObject* parent)
    : QObject(parent)
{
    connect(WebEngine::instance(), &WebEngine::spellCheckingChanged, this, &WebProfile::spellCheckingChanged);
}

WebProfile::~WebProfile()
{
    for (WebKitUserContentFilter* filter : std::as_const(m_filters))
        webkit_user_content_filter_unref(filter);
    g_clear_object(&m_filterStore);
    if (m_session)
        g_signal_handlers_disconnect_by_data(m_session, this);
    g_clear_object(&m_session);
}

void WebProfile::setEphemeral(bool ephemeral)
{
    if (m_session || ephemeral == m_ephemeral)
        return;
    m_ephemeral = ephemeral;
    Q_EMIT changed();
}

void WebProfile::setDataDirectory(const QString& dir)
{
    if (m_session || dir == m_dataDirectory)
        return;
    m_dataDirectory = dir;
    Q_EMIT changed();
}

void WebProfile::setCacheDirectory(const QString& dir)
{
    if (m_session || dir == m_cacheDirectory)
        return;
    m_cacheDirectory = dir;
    Q_EMIT changed();
}

void WebProfile::setDownloadDirectory(const QString& dir)
{
    if (dir == m_downloadDirectory)
        return;
    m_downloadDirectory = dir;
    Q_EMIT changed();
}

void WebProfile::setTrackingPrevention(bool enabled)
{
    if (enabled == m_itp)
        return;
    m_itp = enabled;
    applySettings();
    Q_EMIT changed();
}

void WebProfile::setCookiePolicy(CookiePolicy policy)
{
    if (policy == m_cookiePolicy)
        return;
    m_cookiePolicy = policy;
    applySettings();
    Q_EMIT changed();
}

void WebProfile::setIgnoreTlsErrors(bool ignore)
{
    if (ignore == m_ignoreTlsErrors)
        return;
    m_ignoreTlsErrors = ignore;
    applySettings();
    Q_EMIT changed();
}

WebKitNetworkSession* WebProfile::session()
{
    if (m_session)
        return m_session;
    // The shared context goes first: its memory-pressure settings are
    // process-wide and must exist before any session or process.
    WebEngine::instance()->context();
    if (m_ephemeral) {
        m_session = webkit_network_session_new_ephemeral();
    } else {
        const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        const QString cacheBase = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
        // PACIFIC_WEB_DATA and PACIFIC_WEB_CACHE: the app's own directories
        // (in a Sailjail sandbox only those named after its organisation and
        // application persist).
        if (m_dataDirectory.isEmpty())
            m_dataDirectory = qEnvironmentVariable("PACIFIC_WEB_DATA", base + QStringLiteral("/web"));
        if (m_cacheDirectory.isEmpty())
            m_cacheDirectory = qEnvironmentVariable("PACIFIC_WEB_CACHE", cacheBase + QStringLiteral("/web"));
        QDir().mkpath(m_dataDirectory);
        QDir().mkpath(m_cacheDirectory);
        m_session = webkit_network_session_new(m_dataDirectory.toUtf8().constData(),
            m_cacheDirectory.toUtf8().constData());
        webkit_network_session_set_persistent_credential_storage_enabled(m_session, FALSE);
    }
    g_signal_connect(m_session, "download-started",
        G_CALLBACK(+[](WebKitNetworkSession*, WebKitDownload* download, WebProfile* self) {
            auto* item = new Download(download, self->m_downloadDirectory, self);
            QQmlEngine::setObjectOwnership(item, QQmlEngine::CppOwnership);
            Q_EMIT self->downloadStarted(item);
        }), this);
    applySettings();
    Q_EMIT createdChanged();
    return m_session;
}

void WebProfile::applySettings()
{
    if (!m_session)
        return;
    webkit_network_session_set_itp_enabled(m_session, m_itp);
    WebKitCookieManager* cookies = webkit_network_session_get_cookie_manager(m_session);
    switch (m_cookiePolicy) {
    case AcceptAll:
        webkit_cookie_manager_set_accept_policy(cookies, WEBKIT_COOKIE_POLICY_ACCEPT_ALWAYS);
        break;
    case AcceptNone:
        webkit_cookie_manager_set_accept_policy(cookies, WEBKIT_COOKIE_POLICY_ACCEPT_NEVER);
        break;
    case NoThirdParty:
        webkit_cookie_manager_set_accept_policy(cookies, WEBKIT_COOKIE_POLICY_ACCEPT_NO_THIRD_PARTY);
        break;
    }
    if (!m_ephemeral) {
        const QString cookieFile = m_dataDirectory + QStringLiteral("/cookies.sqlite");
        webkit_cookie_manager_set_persistent_storage(cookies, cookieFile.toUtf8().constData(),
            WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE);
    }
    webkit_network_session_set_tls_errors_policy(m_session,
        m_ignoreTlsErrors ? WEBKIT_TLS_ERRORS_POLICY_IGNORE : WEBKIT_TLS_ERRORS_POLICY_FAIL);
}

void WebProfile::clearData(int types, int sinceSeconds, const QJSValue& callback)
{
    WebKitWebsiteDataManager* manager = webkit_network_session_get_website_data_manager(session());
    const GTimeSpan span = sinceSeconds > 0 ? static_cast<GTimeSpan>(sinceSeconds) * G_TIME_SPAN_SECOND : 0;
    webkit_website_data_manager_clear(manager, static_cast<WebKitWebsiteDataTypes>(types), span, nullptr,
        [](GObject* source, GAsyncResult* result, gpointer data) {
            GError* error = nullptr;
            const bool ok = webkit_website_data_manager_clear_finish(WEBKIT_WEBSITE_DATA_MANAGER(source), result, &error);
            g_clear_error(&error);
            callBack(static_cast<JsCall*>(data), { QJSValue(ok) });
        },
        new JsCall { this, callback });
}

void WebProfile::setGlobalPrivacyControl(bool enabled)
{
    if (enabled == m_gpc)
        return;
    m_gpc = enabled;
    Q_EMIT globalPrivacyControlChanged();
}

bool WebProfile::spellChecking() const
{
    return WebEngine::instance()->spellChecking();
}

void WebProfile::setSpellChecking(bool enabled)
{
    WebEngine::instance()->setSpellChecking(enabled);
}

QStringList WebProfile::spellCheckingLanguages() const
{
    return WebEngine::instance()->spellCheckingLanguages();
}

void WebProfile::setSpellCheckingLanguages(const QStringList& languages)
{
    WebEngine::instance()->setSpellCheckingLanguages(languages);
}

void WebProfile::prefetchDns(const QString& host)
{
    webkit_network_session_prefetch_dns(session(), host.toUtf8().constData());
}

void WebProfile::download(const QUrl& url)
{
    WebKitDownload* download = webkit_network_session_download_uri(session(), url.toString().toUtf8().constData());
    g_clear_object(&download); // the session keeps it; download-started wraps it
}

void WebProfile::allowCertificate(const QString& host, const QString& pem)
{
    GError* error = nullptr;
    GTlsCertificate* certificate = g_tls_certificate_new_from_pem(pem.toUtf8().constData(), -1, &error);
    if (!certificate) {
        qWarning("WebProfile.allowCertificate: %s", error ? error->message : "bad certificate");
        g_clear_error(&error);
        return;
    }
    webkit_network_session_allow_tls_certificate_for_host(session(), certificate, host.toUtf8().constData());
    g_object_unref(certificate);
}

WebKitUserContentFilterStore* WebProfile::filterStore()
{
    if (!m_filterStore) {
        // The private profile's store is with the web cache: the compiled
        // filters are no browsing data, and under the application name
        // (QStandardPaths) a Sailjail sandbox keeps them in memory only, so
        // every filter was compiled again at every start.
        QString dir = m_dataDirectory;
        if (m_ephemeral || dir.isEmpty())
            dir = qEnvironmentVariable("PACIFIC_WEB_CACHE",
                QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/web"));
        dir += QStringLiteral("/content-filters");
        QDir().mkpath(dir);
        m_filterStore = webkit_user_content_filter_store_new(dir.toUtf8().constData());
    }
    return m_filterStore;
}

void WebProfile::filterReady(const QString& identifier, WebKitUserContentFilter* filter)
{
    if (WebKitUserContentFilter* old = m_filters.take(identifier))
        webkit_user_content_filter_unref(old);
    m_filters.insert(identifier, filter);
    Q_EMIT contentFiltersChanged();
    Q_EMIT contentFilterAdded(identifier);
}

struct FilterCall {
    QPointer<WebProfile> profile;
    QString identifier;
    int generation;
    QJSValue callback;
};

static void filterFinished(GObject* source, GAsyncResult* result, gpointer data, bool load)
{
    std::unique_ptr<FilterCall> call(static_cast<FilterCall*>(data));
    GError* error = nullptr;
    auto* store = WEBKIT_USER_CONTENT_FILTER_STORE(source);
    WebKitUserContentFilter* filter = load ? webkit_user_content_filter_store_load_finish(store, result, &error)
                                           : webkit_user_content_filter_store_save_finish(store, result, &error);
    const QString message = error ? QString::fromUtf8(error->message) : QString();
    g_clear_error(&error);
    if (!call->profile) {
        if (filter)
            webkit_user_content_filter_unref(filter);
        return;
    }
    bool ok = filter != nullptr;
    QString why = message;
    if (filter && !call->profile->filterFinishedPublic(call->identifier, call->generation, filter)) {
        // Removed (or asked for again) while it was compiling or loading.
        ok = false;
        why = QStringLiteral("removed before it was ready");
    }
    if (call->callback.isCallable())
        call->callback.call({ QJSValue(ok), QJSValue(why) });
}

bool WebProfile::filterFinishedPublic(const QString& identifier, int generation, WebKitUserContentFilter* filter)
{
    if (m_filterGeneration.value(identifier) != generation) {
        webkit_user_content_filter_unref(filter);
        return false;
    }
    filterReady(identifier, filter);
    return true;
}

int WebProfile::nextFilterGeneration(const QString& identifier)
{
    const int generation = m_filterGeneration.value(identifier) + 1;
    m_filterGeneration.insert(identifier, generation);
    return generation;
}

void WebProfile::compileContentFilter(const QString& identifier, const QString& json, const QJSValue& callback)
{
    const QByteArray source = json.toUtf8();
    GBytes* bytes = g_bytes_new(source.constData(), source.size());
    webkit_user_content_filter_store_save(filterStore(), identifier.toUtf8().constData(), bytes, nullptr,
        [](GObject* s, GAsyncResult* r, gpointer d) { filterFinished(s, r, d, false); },
        new FilterCall { this, identifier, nextFilterGeneration(identifier), callback });
    g_bytes_unref(bytes);
}

void WebProfile::loadContentFilter(const QString& identifier, const QJSValue& callback)
{
    webkit_user_content_filter_store_load(filterStore(), identifier.toUtf8().constData(), nullptr,
        [](GObject* s, GAsyncResult* r, gpointer d) { filterFinished(s, r, d, true); },
        new FilterCall { this, identifier, nextFilterGeneration(identifier), callback });
}

void WebProfile::disableContentFilter(const QString& identifier)
{
    // A compile or load still running for it is dropped when it finishes.
    nextFilterGeneration(identifier);
    if (WebKitUserContentFilter* filter = m_filters.take(identifier)) {
        webkit_user_content_filter_unref(filter);
        Q_EMIT contentFilterRemoved(identifier);
        Q_EMIT contentFiltersChanged();
    }
}

void WebProfile::disableAllContentFilters()
{
    const QStringList ids = m_filters.keys();
    for (const QString& id : ids)
        disableContentFilter(id);
    for (auto it = m_filterGeneration.begin(); it != m_filterGeneration.end(); ++it)
        ++it.value();
}

struct DeleteCall {
    QPointer<WebProfile> profile;
    QJSValue callback;
};

void WebProfile::enableContentFilter(const QString& identifier, const QJSValue& callback)
{
    loadContentFilter(identifier, callback);
}

void WebProfile::removeContentFilter(const QString& identifier, const QJSValue& callback)
{
    disableContentFilter(identifier);
    webkit_user_content_filter_store_remove(filterStore(), identifier.toUtf8().constData(), nullptr,
        [](GObject* source, GAsyncResult* result, gpointer data) {
            std::unique_ptr<DeleteCall> call(static_cast<DeleteCall*>(data));
            GError* error = nullptr;
            const bool ok = webkit_user_content_filter_store_remove_finish(WEBKIT_USER_CONTENT_FILTER_STORE(source), result, &error);
            const QString message = error ? QString::fromUtf8(error->message) : QString();
            g_clear_error(&error);
            if (call->profile && call->callback.isCallable())
                call->callback.call({ QJSValue(ok), QJSValue(message) });
        },
        new DeleteCall { this, callback });
}

struct ListCall {
    QPointer<WebProfile> profile;
    QJSValue callback;
};

void WebProfile::storedContentFilters(const QJSValue& callback)
{
    webkit_user_content_filter_store_fetch_identifiers(filterStore(), nullptr,
        [](GObject* source, GAsyncResult* result, gpointer data) {
            std::unique_ptr<ListCall> call(static_cast<ListCall*>(data));
            gchar** ids = webkit_user_content_filter_store_fetch_identifiers_finish(WEBKIT_USER_CONTENT_FILTER_STORE(source), result);
            QStringList list;
            for (gchar** id = ids; id && *id; ++id)
                list.append(QString::fromUtf8(*id));
            g_strfreev(ids);
            if (call->profile && call->callback.isCallable()) {
                QJSEngine* engine = qjsEngine(call->profile);
                call->callback.call({ engine ? engine->toScriptValue(list) : QJSValue() });
            }
        },
        new ListCall { this, callback });
}

WebEngine::WebEngine(QObject* parent)
    : QObject(parent)
    , m_languages(QStringList { QLocale().name().replace(QLatin1Char('_'), QLatin1Char('-')), QStringLiteral("en") })
{
    QString lang = dictionaryForLocale(QLocale::system().name());
    if (lang.isEmpty())
        lang = dictionaryForLocale(QStringLiteral("en_GB"));
    m_spellLanguages = QStringList { lang.isEmpty() ? QStringLiteral("en_GB") : lang };
}

WebEngine* WebEngine::instance()
{
    static auto* s_instance = new WebEngine(qApp);
    return s_instance;
}

WebEngine* WebEngine::create(QQmlEngine*, QJSEngine*)
{
    WebEngine* engine = instance();
    QQmlEngine::setObjectOwnership(engine, QQmlEngine::CppOwnership);
    return engine;
}

QString WebEngine::version() const
{
    return QStringLiteral("%1.%2.%3").arg(webkit_get_major_version()).arg(webkit_get_minor_version()).arg(webkit_get_micro_version());
}

WebProfile* WebEngine::defaultProfile()
{
    if (!m_defaultProfile)
        m_defaultProfile = new WebProfile(this);
    return m_defaultProfile;
}

WebProfile* WebEngine::privateProfile()
{
    if (!m_privateProfile) {
        m_privateProfile = new WebProfile(this);
        m_privateProfile->setEphemeral(true);
    }
    return m_privateProfile;
}

void WebEngine::setCacheModel(CacheModel model)
{
    if (model == m_cacheModel)
        return;
    m_cacheModel = model;
    applyContextSettings();
    Q_EMIT changed();
}

void WebEngine::setPreferredLanguages(const QStringList& languages)
{
    if (languages == m_languages)
        return;
    m_languages = languages;
    applyContextSettings();
    Q_EMIT changed();
}

void WebEngine::setSpellCheckingLanguages(const QStringList& languages)
{
    if (languages == m_spellLanguages)
        return;
    m_spellLanguages = languages;
    applyContextSettings();
    Q_EMIT spellCheckingChanged();
}

void WebEngine::setSpellChecking(bool enabled)
{
    if (enabled == m_spellChecking)
        return;
    m_spellChecking = enabled;
    applyContextSettings();
    Q_EMIT spellCheckingChanged();
}

// The legacy WPE API hardwires prefers-color-scheme to light; Atlantic's
// engine patch (webkit-wpe-dark-mode-runtime) exports this switch, which also
// updates pages already open.
void WebEngine::setDarkMode(bool dark)
{
    if (dark == m_darkMode)
        return;
    m_darkMode = dark;
    using SetDarkModeFn = void (*)(int);
    static const auto setDarkMode = reinterpret_cast<SetDarkModeFn>(engineSymbol("wpe_sfos_set_dark_mode"));
    if (setDarkMode)
        setDarkMode(dark ? 1 : 0);
    Q_EMIT darkModeChanged();
}

static QString dictionaryDirectory()
{
    const QString dir = qEnvironmentVariable("PACIFIC_DICTIONARY_DIR");
    return dir.isEmpty() ? QStringLiteral("/opt/pacific/share/hunspell") : dir;
}

QStringList WebEngine::availableSpellCheckingLanguages() const
{
    QStringList names;
    const QStringList files = QDir(dictionaryDirectory()).entryList({ QStringLiteral("*.dic") }, QDir::Files, QDir::Name);
    for (const QString& f : files)
        names.append(f.chopped(4));
    // Finnish comes from Voikko (enchant's voikko provider), not hunspell:
    // enchant offers it as "fi", and "fi_FI" falls back to it.
    QString voikko = qEnvironmentVariable("VOIKKO_DICTIONARY_PATH");
    if (voikko.isEmpty())
        voikko = QStringLiteral("/opt/pacific/share/voikko");
    if (QFileInfo::exists(voikko + QStringLiteral("/5/mor-standard/index.txt")) && !names.contains(QStringLiteral("fi_FI"))) {
        names.append(QStringLiteral("fi_FI"));
        names.sort();
    }
    return names;
}

QString WebEngine::dictionaryForLocale(const QString& locale) const
{
    const QStringList available = availableSpellCheckingLanguages();
    QString name = QString(locale).replace(QLatin1Char('-'), QLatin1Char('_')).section(QLatin1Char('.'), 0, 0);
    if (available.contains(name))
        return name;
    const QString language = name.section(QLatin1Char('_'), 0, 0);
    if (language.isEmpty())
        return {};
    // The language's home variant first (de_DE for de_AT), then any.
    QString home = language + QLatin1Char('_') + language.toUpper();
    if (available.contains(home))
        return home;
    for (const QString& a : available) {
        if (a.section(QLatin1Char('_'), 0, 0) == language)
            return a;
    }
    return {};
}

void WebEngine::prepareSpellChecker()
{
    // enchant keeps the personal word list in ENCHANT_CONFIG_DIR and looks for
    // hunspell dictionaries in its hunspell/ subdirectory first. Point that at
    // Pacific's dictionaries, so they win over any the system has, and keep
    // the word list in the app's own data directory. Must happen before
    // WebKit creates the enchant broker (first spell-checking call).
    QString config = qEnvironmentVariable("ENCHANT_CONFIG_DIR");
    if (config.isEmpty()) {
        config = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/enchant");
        qputenv("ENCHANT_CONFIG_DIR", QFile::encodeName(config));
    }
    QDir().mkpath(config);
    const QString link = config + QStringLiteral("/hunspell");
    const QFileInfo info(link);
    if (!info.exists() && !info.isSymLink())
        QFile::link(dictionaryDirectory(), link);
}

// Memory-pressure settings are construct-only on the shared context.
void WebEngine::setMemoryLimitMB(int mb)
{
    if (m_context || mb == m_memoryLimitMB)
        return;
    m_memoryLimitMB = mb;
    Q_EMIT changed();
}

void WebEngine::setConservativeThreshold(qreal value)
{
    if (m_context || qFuzzyCompare(value, m_conservative))
        return;
    m_conservative = value;
    Q_EMIT changed();
}

void WebEngine::setStrictThreshold(qreal value)
{
    if (m_context || qFuzzyCompare(value, m_strict))
        return;
    m_strict = value;
    Q_EMIT changed();
}

void WebEngine::setKillThreshold(qreal value)
{
    if (m_context || qFuzzyCompare(value, m_kill))
        return;
    m_kill = value;
    Q_EMIT changed();
}

void WebEngine::setMemoryPollInterval(qreal seconds)
{
    if (m_context || qFuzzyCompare(seconds, m_pollInterval))
        return;
    m_pollInterval = seconds;
    Q_EMIT changed();
}

QString WebEngine::gpuMode() const
{
    const QString mode = qEnvironmentVariable("PACIFIC_GPU_MODE");
    return mode.isEmpty() ? QStringLiteral("default") : mode;
}

// WebKit has no vblank source here and paces requestAnimationFrame, CSS
// animations and rendering updates with a timer at 60 Hz unless told the
// panel's rate (Atlantic's display-refresh-rate patch); the scrolling
// thread's own tick defaults to 16 ms. On the Jolla Phone's 90 Hz panel both
// ran out of step with the display. The UI process reads the rate when the
// context starts and the WebProcess inherits it, so set both before that.
static void applyDisplayRate()
{
    const QScreen* screen = QGuiApplication::primaryScreen();
    const int rate = screen ? qRound(screen->refreshRate()) : 0;
    if (rate < 30 || rate > 240)
        return;
    if (qEnvironmentVariableIsEmpty("WEBKIT_DISPLAY_REFRESH_RATE"))
        qputenv("WEBKIT_DISPLAY_REFRESH_RATE", QByteArray::number(rate));
    if (qEnvironmentVariableIsEmpty("WEBKIT_INDEPENDENT_SCROLL_TICK_MS"))
        qputenv("WEBKIT_INDEPENDENT_SCROLL_TICK_MS", QByteArray::number(1000.0 / rate, 'f', 2));
}

// The distance a finger moves before a touch becomes a scroll (engine patch
// 0010): 8 dp, Android's touch slop, in the touch points' physical pixels
// (a dp is 1/160 inch). WebKit's own 40 px is 16 dp on the Jolla Phone: the
// page stayed put for the first 40 px of a drag and then jumped by all of it.
static void applyTouchSlop()
{
    if (!qEnvironmentVariableIsEmpty("PACIFIC_TOUCH_SLOP_PX"))
        return;
    const QScreen* screen = QGuiApplication::primaryScreen();
    const qreal dpi = screen ? screen->physicalDotsPerInch() : 0;
    if (dpi < 100 || dpi > 1000)
        return;
    qputenv("PACIFIC_TOUCH_SLOP_PX", QByteArray::number(qRound(8 * dpi / 160)));
}

WebKitWebContext* WebEngine::context()
{
    if (m_context)
        return m_context;
    applyDisplayRate();
    applyTouchSlop();
    WebKitMemoryPressureSettings* memory = nullptr;
    if (m_memoryLimitMB > 0 || m_conservative > 0 || m_strict > 0 || m_kill > 0 || m_pollInterval > 0) {
        memory = webkit_memory_pressure_settings_new();
        if (m_memoryLimitMB > 0)
            webkit_memory_pressure_settings_set_memory_limit(memory, static_cast<guint>(m_memoryLimitMB));
        if (m_conservative > 0)
            webkit_memory_pressure_settings_set_conservative_threshold(memory, m_conservative);
        if (m_strict > 0)
            webkit_memory_pressure_settings_set_strict_threshold(memory, m_strict);
        if (m_kill > 0)
            webkit_memory_pressure_settings_set_kill_threshold(memory, m_kill);
        if (m_pollInterval > 0)
            webkit_memory_pressure_settings_set_poll_interval(memory, m_pollInterval);
        webkit_network_session_set_memory_pressure_settings(memory);
    }
    m_context = memory
        ? WEBKIT_WEB_CONTEXT(g_object_new(WEBKIT_TYPE_WEB_CONTEXT, "memory-pressure-settings", memory, nullptr))
        : webkit_web_context_new();
    if (memory)
        webkit_memory_pressure_settings_free(memory);
    // Geolocation from Qt Positioning: SFOS has no GeoClue2, WebKit's own
    // provider. Attached once, for the context's lifetime.
    GeolocationBridge::attach(m_context);
    // Pacific's WebProcess extension (blocked-request reports).
    QByteArray extensions = qgetenv("PACIFIC_WEB_EXTENSIONS_DIR");
#ifdef PACIFIC_WEB_EXTENSIONS_DIR
    if (extensions.isEmpty())
        extensions = PACIFIC_WEB_EXTENSIONS_DIR;
#endif
    if (!extensions.isEmpty())
        webkit_web_context_set_web_process_extensions_directory(m_context, extensions.constData());
    prepareSpellChecker();
    applyContextSettings();
    return m_context;
}

void WebEngine::spellCheckingNeeded()
{
    if (m_spellNeeded)
        return;
    m_spellNeeded = true;
    if (m_context)
        applyContextSettings();
}

void WebEngine::applyContextSettings()
{
    if (!m_context)
        return;
    switch (m_cacheModel) {
    case DocumentViewer:
        webkit_web_context_set_cache_model(m_context, WEBKIT_CACHE_MODEL_DOCUMENT_VIEWER);
        break;
    case WebBrowser:
        webkit_web_context_set_cache_model(m_context, WEBKIT_CACHE_MODEL_WEB_BROWSER);
        break;
    case DocumentBrowser:
        webkit_web_context_set_cache_model(m_context, WEBKIT_CACHE_MODEL_DOCUMENT_BROWSER);
        break;
    }
    const QByteArrayList languages = toUtf8List(m_languages);
    QList<const gchar*> languageStrv = toStrv(languages);
    webkit_web_context_set_preferred_languages(m_context, languageStrv.data());
    const bool spell = m_spellNeeded && m_spellChecking && !m_spellLanguages.isEmpty();
    webkit_web_context_set_spell_checking_enabled(m_context, spell);
    if (spell) {
        const QByteArrayList spell = toUtf8List(m_spellLanguages);
        QList<const gchar*> spellStrv = toStrv(spell);
        webkit_web_context_set_spell_checking_languages(m_context, spellStrv.data());
    }
}
