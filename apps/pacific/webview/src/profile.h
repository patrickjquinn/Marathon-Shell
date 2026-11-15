// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// WebEngine (QML singleton): process-wide engine settings and the shared
// WebKitWebContext (cache model, memory-pressure limits, languages, spell
// checking), plus the two standard profiles.
//
// WebProfile: one WebKitNetworkSession, persistent (cookies, cache, storage
// under dataDirectory/cacheDirectory) or ephemeral (in memory only; private
// tabs and Pilot's background browsing). Views pick a profile before their
// web view is created; it cannot change afterwards.

#pragma once

#include <QHash>
#include <QJSValue>
#include <QObject>
#include <QQmlEngine>
#include <QStringList>

#include <wpe/webkit.h>

#include "requests.h"

class WebProfile : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool ephemeral READ ephemeral WRITE setEphemeral NOTIFY changed)
    Q_PROPERTY(QString dataDirectory READ dataDirectory WRITE setDataDirectory NOTIFY changed)
    Q_PROPERTY(QString cacheDirectory READ cacheDirectory WRITE setCacheDirectory NOTIFY changed)
    Q_PROPERTY(QString downloadDirectory READ downloadDirectory WRITE setDownloadDirectory NOTIFY changed)
    Q_PROPERTY(bool trackingPrevention READ trackingPrevention WRITE setTrackingPrevention NOTIFY changed)
    Q_PROPERTY(CookiePolicy cookiePolicy READ cookiePolicy WRITE setCookiePolicy NOTIFY changed)
    Q_PROPERTY(bool ignoreTlsErrors READ ignoreTlsErrors WRITE setIgnoreTlsErrors NOTIFY changed)
    // Global Privacy Control: Sec-GPC: 1 on every request and
    // navigator.globalPrivacyControl for this profile's views. On by default.
    Q_PROPERTY(bool globalPrivacyControl READ globalPrivacyControl WRITE setGlobalPrivacyControl NOTIFY globalPrivacyControlChanged)
    Q_PROPERTY(bool created READ created NOTIFY createdChanged)
    Q_PROPERTY(QStringList contentFilters READ contentFilters NOTIFY contentFiltersChanged)
    // Spell checking. WebKit's checker (enchant + hunspell) is one per
    // process, so these are the WebEngine settings of the same name: every
    // profile shows and changes the same values.
    Q_PROPERTY(bool spellChecking READ spellChecking WRITE setSpellChecking NOTIFY spellCheckingChanged)
    Q_PROPERTY(QStringList spellCheckingLanguages READ spellCheckingLanguages WRITE setSpellCheckingLanguages NOTIFY spellCheckingChanged)

public:
    enum CookiePolicy { AcceptAll, AcceptNone, NoThirdParty };
    Q_ENUM(CookiePolicy)
    enum DataType {
        Cookies = WEBKIT_WEBSITE_DATA_COOKIES,
        Cache = WEBKIT_WEBSITE_DATA_DISK_CACHE | WEBKIT_WEBSITE_DATA_MEMORY_CACHE,
        LocalStorage = WEBKIT_WEBSITE_DATA_LOCAL_STORAGE | WEBKIT_WEBSITE_DATA_SESSION_STORAGE,
        IndexedDb = WEBKIT_WEBSITE_DATA_INDEXEDDB_DATABASES,
        ServiceWorkers = WEBKIT_WEBSITE_DATA_SERVICE_WORKER_REGISTRATIONS,
        AllData = WEBKIT_WEBSITE_DATA_ALL
    };
    Q_ENUM(DataType)

    explicit WebProfile(QObject* parent = nullptr);
    ~WebProfile() override;

    bool ephemeral() const { return m_ephemeral; }
    void setEphemeral(bool ephemeral);
    QString dataDirectory() const { return m_dataDirectory; }
    void setDataDirectory(const QString& dir);
    QString cacheDirectory() const { return m_cacheDirectory; }
    void setCacheDirectory(const QString& dir);
    QString downloadDirectory() const { return m_downloadDirectory; }
    void setDownloadDirectory(const QString& dir);
    bool trackingPrevention() const { return m_itp; }
    void setTrackingPrevention(bool enabled);
    CookiePolicy cookiePolicy() const { return m_cookiePolicy; }
    void setCookiePolicy(CookiePolicy policy);
    bool ignoreTlsErrors() const { return m_ignoreTlsErrors; }
    bool globalPrivacyControl() const { return m_gpc; }
    void setGlobalPrivacyControl(bool enabled);
    void setIgnoreTlsErrors(bool ignore);
    bool created() const { return m_session != nullptr; }
    QStringList contentFilters() const { return m_filters.keys(); }
    bool spellChecking() const;
    void setSpellChecking(bool enabled);
    QStringList spellCheckingLanguages() const;
    void setSpellCheckingLanguages(const QStringList& languages);

    // Creates the session on first use (then the settings above that are
    // construct-only are fixed).
    WebKitNetworkSession* session();
    QHash<QString, WebKitUserContentFilter*> filters() const { return m_filters; }
    // Completion of an asynchronous filter compile or load: false (and the
    // filter dropped) when it was removed or asked for again meanwhile.
    bool filterFinishedPublic(const QString& identifier, int generation, WebKitUserContentFilter* filter);

    // Clears website data of the given DataType flags, optionally only data
    // modified since sinceSeconds ago (0 = all time). callback(ok).
    Q_INVOKABLE void clearData(int types = AllData, int sinceSeconds = 0, const QJSValue& callback = QJSValue());
    Q_INVOKABLE void prefetchDns(const QString& host);
    // Starts a download not tied to a page (shows up in downloadStarted).
    Q_INVOKABLE void download(const QUrl& url);
    // Lets a host's otherwise invalid certificate through, for this session
    // (after the user accepted WebView.certificateError).
    Q_INVOKABLE void allowCertificate(const QString& host, const QString& pem);
    // Compiles WebKit content-blocker JSON (Safari format) once into a DFA
    // shared by every WebProcess, stored under dataDirectory/content-filters;
    // every view of this profile applies all compiled filters. callback(ok, error)
    Q_INVOKABLE void compileContentFilter(const QString& identifier, const QString& json,
        const QJSValue& callback = QJSValue());
    // Applies a filter compiled in this or an earlier run, from the store.
    // callback(ok, error): false when the store does not have it (compile
    // it again).
    Q_INVOKABLE void loadContentFilter(const QString& identifier, const QJSValue& callback = QJSValue());
    // The same as loadContentFilter: applies a disabled filter again.
    Q_INVOKABLE void enableContentFilter(const QString& identifier, const QJSValue& callback = QJSValue());
    // Stops applying a filter on every view of the profile, current and
    // future (from the next page load; reload to unblock a page now). It
    // leaves contentFilters but stays in the store for enableContentFilter.
    Q_INVOKABLE void disableContentFilter(const QString& identifier);
    Q_INVOKABLE void disableAllContentFilters();
    // Deletes a filter: disables it and removes the compiled filter from the
    // store (a list removed or replaced). callback(ok, error).
    Q_INVOKABLE void removeContentFilter(const QString& identifier, const QJSValue& callback = QJSValue());
    // The identifiers compiled in the store. callback(list).
    Q_INVOKABLE void storedContentFilters(const QJSValue& callback);

Q_SIGNALS:
    void changed();
    void createdChanged();
    void downloadStarted(Download* download);
    void contentFiltersChanged();
    void globalPrivacyControlChanged();
    void spellCheckingChanged();
    void contentFilterAdded(const QString& identifier);
    void contentFilterRemoved(const QString& identifier);

private:
    void applySettings();
    WebKitUserContentFilterStore* filterStore();
    void filterReady(const QString& identifier, WebKitUserContentFilter* filter);
    int nextFilterGeneration(const QString& identifier);

    WebKitNetworkSession* m_session = nullptr;
    WebKitUserContentFilterStore* m_filterStore = nullptr;
    QHash<QString, WebKitUserContentFilter*> m_filters;
    QHash<QString, int> m_filterGeneration;
    bool m_ephemeral = false;
    QString m_dataDirectory;
    QString m_cacheDirectory;
    QString m_downloadDirectory;
    bool m_itp = true;
    CookiePolicy m_cookiePolicy = NoThirdParty;
    bool m_ignoreTlsErrors = false;
    bool m_gpc = true;
};

class WebEngine : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(WebProfile* defaultProfile READ defaultProfile CONSTANT)
    Q_PROPERTY(WebProfile* privateProfile READ privateProfile CONSTANT)
    Q_PROPERTY(CacheModel cacheModel READ cacheModel WRITE setCacheModel NOTIFY changed)
    Q_PROPERTY(QStringList preferredLanguages READ preferredLanguages WRITE setPreferredLanguages NOTIFY changed)
    // Spell checking, on by default in the phone's language (the closest
    // packaged dictionary; en_GB when none fits). Languages are dictionary
    // names such as "en_GB" or "de_DE"; availableSpellCheckingLanguages lists
    // the installed ones.
    Q_PROPERTY(bool spellChecking READ spellChecking WRITE setSpellChecking NOTIFY spellCheckingChanged)
    Q_PROPERTY(QStringList spellCheckingLanguages READ spellCheckingLanguages WRITE setSpellCheckingLanguages NOTIFY spellCheckingChanged)
    Q_PROPERTY(QStringList availableSpellCheckingLanguages READ availableSpellCheckingLanguages CONSTANT)
    // Memory pressure (WebKitMemoryPressureSettings), fixed when the shared
    // context is created (the first web view): the WebProcess limit in MB and
    // the fractions of it at which WebKit frees caches (conservative, strict)
    // and kills the process (kill; 0 = never).
    Q_PROPERTY(int memoryLimitMB READ memoryLimitMB WRITE setMemoryLimitMB NOTIFY changed)
    Q_PROPERTY(qreal conservativeThreshold READ conservativeThreshold WRITE setConservativeThreshold NOTIFY changed)
    Q_PROPERTY(qreal strictThreshold READ strictThreshold WRITE setStrictThreshold NOTIFY changed)
    Q_PROPERTY(qreal killThreshold READ killThreshold WRITE setKillThreshold NOTIFY changed)
    Q_PROPERTY(qreal memoryPollInterval READ memoryPollInterval WRITE setMemoryPollInterval NOTIFY changed)
    // What websites see as the preferred colour scheme (prefers-color-scheme);
    // live pages follow a change without reloading (the engine's
    // wpe_sfos_set_dark_mode; without it this does nothing).
    Q_PROPERTY(bool darkMode READ darkMode WRITE setDarkMode NOTIFY darkModeChanged)
    // The GPU workaround mode chosen by the launcher (PACIFIC_GPU_MODE).
    Q_PROPERTY(QString gpuMode READ gpuMode CONSTANT)

public:
    enum CacheModel { DocumentViewer, WebBrowser, DocumentBrowser };
    Q_ENUM(CacheModel)

    static WebEngine* instance();
    static WebEngine* create(QQmlEngine*, QJSEngine*);

    QString version() const;
    WebProfile* defaultProfile();
    WebProfile* privateProfile();
    CacheModel cacheModel() const { return m_cacheModel; }
    void setCacheModel(CacheModel model);
    QStringList preferredLanguages() const { return m_languages; }
    void setPreferredLanguages(const QStringList& languages);
    QStringList spellCheckingLanguages() const { return m_spellLanguages; }
    void setSpellCheckingLanguages(const QStringList& languages);
    bool spellChecking() const { return m_spellChecking; }
    void setSpellChecking(bool enabled);
    QStringList availableSpellCheckingLanguages() const;
    // The dictionary for a locale name ("de_AT" -> "de_DE"), or empty.
    QString dictionaryForLocale(const QString& locale) const;
    int memoryLimitMB() const { return m_memoryLimitMB; }
    void setMemoryLimitMB(int mb);
    qreal conservativeThreshold() const { return m_conservative; }
    void setConservativeThreshold(qreal value);
    qreal strictThreshold() const { return m_strict; }
    void setStrictThreshold(qreal value);
    qreal killThreshold() const { return m_kill; }
    void setKillThreshold(qreal value);
    qreal memoryPollInterval() const { return m_pollInterval; }
    void setMemoryPollInterval(qreal seconds);
    QString gpuMode() const;
    bool darkMode() const { return m_darkMode; }
    void setDarkMode(bool dark);
    // A text field has focus: the spelling dictionaries load now, not when
    // the first page does (parsing one took ~5% of the GUI thread at start).
    void spellCheckingNeeded();

    WebKitWebContext* context();

Q_SIGNALS:
    void changed();
    void spellCheckingChanged();
    void darkModeChanged();

private:
    explicit WebEngine(QObject* parent = nullptr);
    void applyContextSettings();
    void prepareSpellChecker();

    WebKitWebContext* m_context = nullptr;
    WebProfile* m_defaultProfile = nullptr;
    WebProfile* m_privateProfile = nullptr;
    CacheModel m_cacheModel = WebBrowser;
    QStringList m_languages;
    QStringList m_spellLanguages;
    bool m_spellChecking = true;
    bool m_spellNeeded = false;
    bool m_darkMode = false;
    int m_memoryLimitMB = 0;
    qreal m_conservative = 0;
    qreal m_strict = 0;
    qreal m_kill = 0;
    qreal m_pollInterval = 0;
};
