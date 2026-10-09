// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebEngine 1.0 for Keel: the WebEngine and WebEngineSettings
// singletons, clean-room. Names, enums and documented defaults from the
// public Sailfish WebView documentation (sailfishos.org/develop/docs/
// sailfish-components-webview/, "WebEngine QML Type" and "WebEngineSettings
// QML Type"). Sailfish's engine is Gecko (EmbedLite); Keel's WebView
// renders with Qt WebEngine (Chromium) where it is installed, so:
//   - WebEngine's observer API is an in-process message bus: an app's
//     notifyObservers() reaches its own addObserver() topics. Of Gecko's own
//     topics, Keel sends "clipboard:setdata" (a page copied text),
//     "final-ui-startup" (notifyFirstUIInitialized()) and answers the site
//     permission requests of Sailfish.WebView.Controls ("embedui:perms").
//     addComponentManifest() (Gecko JavaScript components, no longer in
//     the documentation) does nothing.
//   - isAccelerated()/setIsAccelerated(): Chromium's GPU rendering
//     (--disable-gpu), read when Qt WebEngine starts.
//   - addUserStyleSheet()/removeUserStyleSheet(): the style sheets are
//     injected into every page of the app's WebViews.
//   - runEmbedding(), stopEmbedding(), notifyFirstUIInitialized(),
//     lastWindowDestroyed: Qt WebEngine starts with the first WebView and
//     stops with the application; stopEmbedding() reports contextDestroyed
//     once the app's WebViews are gone.
//   - WebEngineSettings keeps every value; Keel's WebView applies the ones
//     Qt WebEngine has (javascriptEnabled, autoLoadImages, popupEnabled,
//     downloadDir, and the Gecko preferences listed in
//     WebEngineSettings::setPreference()). PROVENANCE.md has the table.
#ifndef KEEL_WEBENGINE_H
#define KEEL_WEBENGINE_H

#include <QHash>
#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QPointer>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <memory>

class KeelPermissionStore;

class WebEngine : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool initialized READ isInitialized CONSTANT)
    // Keel: the shared persistent WebEngineProfile Keel's WebView creates
    // on first use; setting it makes this singleton its owner.
    Q_PROPERTY(QObject *_keelProfile READ keelProfile WRITE setKeelProfile NOTIFY keelProfileChanged)
    // Keel: the backend Keel's WebView uses: KEEL_WEBVIEW_BACKEND if set
    // ("qtwebengine" or "external"), else "qtwebengine" when Qt WebEngine's
    // QML module is on the engine's import path, else "external".
    Q_PROPERTY(QString _keelBackend READ keelBackend CONSTANT)
    // Keel: addUserStyleSheet()'s style sheets (CSS text) for the WebViews.
    Q_PROPERTY(QStringList _keelUserStyleSheets READ keelUserStyleSheets NOTIFY keelUserStyleSheetsChanged)
    // Keel: Qt WebEngine's own user agent of the shared profile, kept
    // before Keel's WebView sets its own on it.
    Q_PROPERTY(QString _keelEngineUserAgent MEMBER m_engineUserAgent NOTIFY keelEngineUserAgentChanged)
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit WebEngine(QObject *parent = nullptr);
    ~WebEngine() override;

    // The latest WebEngine singleton (C++ code that Sailfish reaches through
    // SailfishOS::WebEngine::instance(), e.g. the permission models).
    static WebEngine *instance();

    static bool isInitialized() { return true; }
    QObject *keelProfile() const { return m_profile; }
    void setKeelProfile(QObject *profile);
    QString keelBackend() const;

    Q_INVOKABLE void addComponentManifest(const QString &manifestPath);
    Q_INVOKABLE bool isAccelerated() const;
    Q_INVOKABLE void setIsAccelerated(bool accelerated);
    Q_INVOKABLE void addUserStyleSheet(const QUrl &url);
    Q_INVOKABLE void removeUserStyleSheet(const QUrl &url);
    Q_INVOKABLE void runEmbedding(int aDelay = -1);
    Q_INVOKABLE void stopEmbedding();
    Q_INVOKABLE void notifyFirstUIInitialized();
    Q_INVOKABLE void addObserver(const QString &aTopic);
    Q_INVOKABLE void removeObserver(const QString &aTopic);
    Q_INVOKABLE void notifyObservers(const QString &topic, const QVariant &value);

    // Keel: a remembered site permission (KeelPermissionStore::Capability:
    // 0 unknown, 1 allow, 2 deny) and remembering one, for Keel's popup
    // bridge.
    Q_INVOKABLE int _keelPermission(const QString &host, const QString &type) const;
    Q_INVOKABLE void _keelRememberPermission(const QString &host, const QString &type, bool allow, bool session);

    // Keel: the user style sheets as CSS text, in the order added.
    QStringList keelUserStyleSheets() const;
    // Keel: Keel's WebViews report themselves (lastWindowDestroyed,
    // stopEmbedding, and when Qt WebEngine has started).
    Q_INVOKABLE void _keelViewCreated();
    Q_INVOKABLE void _keelViewDestroyed();
    // Keel: a local (file: or qrc:) text file, for frame scripts; empty if
    // it cannot be read.
    Q_INVOKABLE QString _keelReadText(const QUrl &url) const;
    // Keel: a page copied text (WebView's clipboard bridge): sends Gecko's
    // "clipboard:setdata" with the clipboard's text.
    Q_INVOKABLE void _keelClipboardSet(bool privateMode);
    // Keel: a WebView's `security` object (KeelSecurity), owned by parent.
    Q_INVOKABLE QObject *_keelCreateSecurity(QObject *parent);

signals:
    void contextDestroyed();
    void lastWindowDestroyed();
    void keelUserStyleSheetsChanged();
    void keelEngineUserAgentChanged();
    // Keel: a download Sailfish.WebView.Popups asked for ("embedui:download"
    // addDownload: from, to, contentType, viewId), for the view viewId.
    void _keelDownloadRequested(const QVariantMap &download);
    void recvObserve(const QString &message, const QVariant &data);
    void keelProfileChanged();

private:
    void handlePermissionRequest(const QVariantMap &request);
    void reply(const QString &topic, const QVariant &value);

    QHash<QString, int> m_topics;
    QList<QPair<QUrl, QString>> m_styleSheets;
    QString m_engineUserAgent;
    int m_views = 0;
    bool m_engineStarted = false;
    bool m_accelerated = true;
    bool m_stopping = false;
    bool m_contextDestroyed = false;
    std::unique_ptr<KeelPermissionStore> m_permissions;
    QObject *m_profile = nullptr;
};

class WebEngineSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool autoLoadImages READ autoLoadImages WRITE setAutoLoadImages NOTIFY autoLoadImagesChanged)
    Q_PROPERTY(int colorScheme READ colorScheme WRITE setColorScheme NOTIFY colorSchemeChanged)
    Q_PROPERTY(CookieBehavior cookieBehavior READ cookieBehavior WRITE setCookieBehavior NOTIFY cookieBehaviorChanged)
    Q_PROPERTY(bool doNotTrack READ doNotTrack WRITE setDoNotTrack NOTIFY doNotTrackChanged)
    Q_PROPERTY(QString downloadDir READ downloadDir WRITE setDownloadDir NOTIFY downloadDirChanged)
    Q_PROPERTY(bool initialized READ isInitialized CONSTANT)
    Q_PROPERTY(bool javascriptEnabled READ javascriptEnabled WRITE setJavascriptEnabled NOTIFY javascriptEnabledChanged)
    Q_PROPERTY(qreal pixelRatio READ pixelRatio WRITE setPixelRatio NOTIFY pixelRatioChanged)
    Q_PROPERTY(bool popupEnabled READ popupEnabled WRITE setPopupEnabled NOTIFY popupEnabledChanged)
    Q_PROPERTY(bool useDownloadDir READ useDownloadDir WRITE setUseDownloadDir NOTIFY useDownloadDirChanged)
    // Keel: what the Gecko preferences set through setPreference() mean for
    // Qt WebEngine (WebView binds these).
    Q_PROPERTY(bool _keelLocalContentCanAccessRemoteUrls READ localContentCanAccessRemoteUrls NOTIFY preferencesChanged)
    Q_PROPERTY(bool _keelLocalContentCanAccessFileUrls READ localContentCanAccessFileUrls NOTIFY preferencesChanged)
    Q_PROPERTY(QString _keelUserAgentOverride READ userAgentOverride NOTIFY preferencesChanged)
    QML_ELEMENT
    QML_SINGLETON

public:
    // network.cookie.cookieBehavior values.
    enum CookieBehavior { AcceptAll = 0, BlockThirdParty = 1, BlockAll = 2 };
    Q_ENUM(CookieBehavior)
    enum ColorScheme { PrefersLightMode = 0, PrefersDarkMode = 1, FollowsAmbience = 2 };
    Q_ENUM(ColorScheme)
    enum PreferenceType { UnknownPref = 0, StringPref = 1, IntPref = 2, BoolPref = 3 };
    Q_ENUM(PreferenceType)

    using QObject::QObject;

    bool autoLoadImages() const { return m_autoLoadImages; }
    void setAutoLoadImages(bool v);
    int colorScheme() const { return m_colorScheme; }
    void setColorScheme(int v);
    CookieBehavior cookieBehavior() const { return m_cookieBehavior; }
    void setCookieBehavior(CookieBehavior v);
    bool doNotTrack() const { return m_doNotTrack; }
    void setDoNotTrack(bool v);
    QString downloadDir() const { return m_downloadDir; }
    void setDownloadDir(const QString &v);
    static bool isInitialized() { return true; }
    bool javascriptEnabled() const { return m_javascriptEnabled; }
    void setJavascriptEnabled(bool v);
    // Sailfish's default until set: 1.5 times Silica's Theme.pixelRatio,
    // rounded as Sailfish rounds it. Keel's WebView zooms pages by it
    // (Keel apps run at a devicePixelRatio of 1).
    qreal pixelRatio() const;
    void setPixelRatio(qreal v);
    bool popupEnabled() const { return m_popupEnabled; }
    void setPopupEnabled(bool v);
    bool useDownloadDir() const { return m_useDownloadDir; }
    void setUseDownloadDir(bool v);

    bool localContentCanAccessRemoteUrls() const;
    bool localContentCanAccessFileUrls() const;
    QString userAgentOverride() const;

    // Sets a Gecko preference. The documented high-level ones update their
    // property ("javascript.enabled", "permissions.default.image",
    // "dom.disable_open_during_load", "network.cookie.cookieBehavior",
    // "privacy.donottrackheader.enabled", "browser.download.dir",
    // "browser.download.useDownloadDir", "layout.css.devPixelsPerPx");
    // "security.disable_cors_checks", "security.fileuri.strict_origin_policy"
    // and "general.useragent.override" map to Qt WebEngine settings; the rest
    // are kept (preference()) without effect.
    Q_INVOKABLE void setPreference(const QString &key, const QVariant &value, int type = UnknownPref);
    Q_INVOKABLE QVariant preference(const QString &key) const { return m_preferences.value(key); }

signals:
    void autoLoadImagesChanged();
    void colorSchemeChanged();
    void cookieBehaviorChanged();
    void doNotTrackChanged();
    void downloadDirChanged();
    void javascriptEnabledChanged();
    void pixelRatioChanged();
    void popupEnabledChanged();
    void useDownloadDirChanged();
    void preferencesChanged();

private:
    bool m_autoLoadImages = true;
    int m_colorScheme = FollowsAmbience;
    CookieBehavior m_cookieBehavior = AcceptAll;
    bool m_doNotTrack = false;
    QString m_downloadDir;
    bool m_javascriptEnabled = true;
    qreal m_pixelRatio = 0; // 0: not set, the default applies
    mutable qreal m_defaultPixelRatio = 0;
    bool m_popupEnabled = false;
    bool m_useDownloadDir = true;
    QVariantMap m_preferences;
};

#endif // KEEL_WEBENGINE_H
