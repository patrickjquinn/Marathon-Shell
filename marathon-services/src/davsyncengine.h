#ifndef DAVSYNCENGINE_H
#define DAVSYNCENGINE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QHash>
#include <QPointer>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QNetworkRequest>

class QNetworkAccessManager;
class QNetworkReply;
class ContactsManager;
class DavCalendarStore;

// One DAV account -- stored in QSettings under "dav/accounts/<id>".
struct DavAccount {
    QString           id;          // stable uuid
    QString           displayName; // user-facing
    QString           baseUrl;     // discovered or user-entered
    QString           username;
    QString           secret;              // password / app-password / bearer token
    QString           authKind;            // "basic" | "bearer"
    QString           homeUrlContacts;     // resolved CardDAV home
    QString           homeUrlCalendar;     // resolved CalDAV home
    QStringList       collectionsContacts; // resolved addressbook URLs
    QStringList       collectionsCalendar; // resolved calendar URLs
    bool              enabled = true;

    QVariantMap       toVariant() const;
    static DavAccount fromVariant(const QVariantMap &m);
};

// Sync state per collection -- etag/sync-token for incremental updates.
struct DavCollectionState {
    QString collectionUrl;
    QString syncToken;
    qint64  lastSyncMs = 0;
};

// CardDAV + CalDAV sync. Speaks DAV directly via QNetworkAccessManager --
// no KDAV / Akonadi dependency. RFC 6764 discovery, RFC 6578 sync-collection,
// RFC 6352 (CardDAV) + RFC 4791 (CalDAV). Validated against Nextcloud,
// Fastmail, iCloud (app-password) and Radicale.
class DavSyncEngine : public QObject {
    Q_OBJECT

    Q_PROPERTY(int accountCount READ accountCount NOTIFY accountsChanged)
    Q_PROPERTY(bool syncing READ syncing NOTIFY syncingChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(qint64 lastSyncMs READ lastSyncMs NOTIFY lastSyncMsChanged)

  public:
    explicit DavSyncEngine(ContactsManager *contacts, DavCalendarStore *calendarStore = nullptr,
                           QObject *parent = nullptr);

    int accountCount() const {
        return m_accounts.size();
    }
    bool syncing() const {
        return m_syncing;
    }
    QString lastError() const {
        return m_lastError;
    }
    qint64 lastSyncMs() const {
        return m_lastSyncMs;
    }

    // Account management -- exposed to QML so the Settings UI can add/edit/remove.
    Q_INVOKABLE QVariantList listAccounts() const;
    Q_INVOKABLE QString      addAccount(const QString &displayName, const QString &baseUrl,
                                        const QString &username, const QString &secret,
                                        const QString &authKind = QStringLiteral("basic"));
    Q_INVOKABLE bool         removeAccount(const QString &id);
    Q_INVOKABLE void         enableAccount(const QString &id, bool enabled);

    // Trigger discovery for one account -- finds principal + home + collections.
    // Idempotent. Re-runs are cheap (PROPFIND with cached etag).
    Q_INVOKABLE void discover(const QString &accountId);

    // Pull updates from server into the local store. Per-collection
    // sync-collection REPORT with stored sync-token.
    Q_INVOKABLE void syncNow();

    // Periodic sync timer -- defaults to 15 minutes. Disable by setting 0.
    Q_INVOKABLE void setSyncIntervalMs(int ms);
    Q_INVOKABLE int  syncIntervalMs() const;

  signals:
    void accountsChanged();
    void syncingChanged();
    void lastErrorChanged();
    void lastSyncMsChanged();
    void accountDiscovered(const QString &accountId);
    void accountDiscoveryFailed(const QString &accountId, const QString &reason);
    void syncFinished(const QString &accountId, int contactsAdded, int contactsUpdated,
                      int contactsRemoved);

  private:
    void           loadAccounts();
    void           saveAccounts() const;
    void           persistAccount(const DavAccount &a);
    void           erasePersistedAccount(const QString &id);

    QNetworkReply *propfind(const QString &url, int depth, const QString &xmlBody,
                            const DavAccount &acct);
    QNetworkReply *report(const QString &url, const QString &xmlBody, const DavAccount &acct);
    QNetworkReply *getResource(const QString &url, const DavAccount &acct);
    void           authenticateRequest(QNetworkRequest &req, const DavAccount &acct) const;

    void           runDiscoveryStep1(DavAccount &acct);
    void           runDiscoveryStep2(DavAccount &acct, const QString &principalUrl);
    void           runDiscoveryStep3(DavAccount &acct);

    void syncCollection(const DavAccount &acct, const QString &collectionUrl, bool isCalendar);

    static QString                     basicAuthHeader(const QString &user, const QString &secret);

    QPointer<ContactsManager>          m_contacts;
    QPointer<DavCalendarStore>         m_calendarStore;
    QNetworkAccessManager             *m_net;
    QHash<QString, DavAccount>         m_accounts;
    QHash<QString, DavCollectionState> m_collectionState;
    QTimer                            *m_syncTimer;

    bool                               m_syncing = false;
    QString                            m_lastError;
    qint64                             m_lastSyncMs     = 0;
    int                                m_syncIntervalMs = 15 * 60 * 1000;
};

#endif
