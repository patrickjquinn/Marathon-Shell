#pragma once

#include <QDBusContext>
#include <QDBusUnixFileDescriptor>
#include <QList>
#include <QObject>
#include <QStringList>
#include <QVariantMap>

#include <functional>

class MarathonAppRegistry;

// The share sheet's service, org.sailfishos.share on the session bus, as
// Keel's ShareAction calls it. A request opens the sheet with the apps whose
// manifest's shareMethods take its type, and the clipboard for text; the
// chosen app is brought to the front and handed the request on its
// org.marathonos.<id> name at /share/<method>.
class ShareService : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sailfishos.share")

  public:
    // The Marathon app a process belongs to, "" if none.
    using AppForPid = std::function<QString(qint64)>;
    // Brings an app to the front, starting it if it is not running.
    using Raise = std::function<void(const QString &)>;

    // sharedFolders: the folders apps with storage see, at the same paths.
    ShareService(MarathonAppRegistry *apps, QStringList sharedFolders, AppForPid appForPid,
                 Raise raise, QObject *parent = nullptr);

    bool             registerOnSessionBus();

    Q_INVOKABLE void choose(const QString &targetId);
    Q_INVOKABLE void cancel();

    static bool      mimeMatches(const QString &accepted, const QString &mimeType);
    // An fd for path as process pid sees it, only if it is a regular file in
    // one of the shared folders on the host as well; -1 otherwise.
    static int       openShared(qint64 pid, const QString &path, const QStringList &sharedFolders,
                                QString *hostPath);

  public slots:
    Q_SCRIPTABLE void share(const QVariantMap &configuration);

  signals:
    // title, mimeType, text, image (a local URL), count, targets: [{id, name, icon, glyph}]
    void requested(const QVariantMap &request);
    // Android's targets (deckardd), after the request: [{id, name, icon}]
    void targetsAdded(const QVariantList &targets);
    void delivered(const QString &targetId);
    void failed(const QString &targetId, const QString &reason);

  private:
    struct Item {
        QString                 name;
        QString                 text;
        QString                 hostPath;
        QString                 mimeType;
        QDBusUnixFileDescriptor file;
    };
    struct Target {
        QString id;
        QString appId;
        // The Marathon app's share method, or the Android activity.
        QString method;
        bool    android = false;
    };

    QVariantList targetsFor(const QString &mimeType, const QStringList &leftOut, bool textOnly);
    void         askAndroid(const QString &mimeType, const QString &source, int files);
    void         shareToAndroid(const QString &targetId, const QString &activity,
                                const QVariantMap &configuration);
    void         deliver(const QString &targetId, const QString &appId, const QString &method,
                         const QVariantMap &configuration, int tries);

    MarathonAppRegistry *m_apps;
    QStringList          m_sharedFolders;
    AppForPid            m_appForPid;
    Raise                m_raise;
    QString              m_title;
    QString              m_mimeType;
    QList<Item>          m_items;
    QList<Target>        m_targets;
    int                  m_request = 0;
};
