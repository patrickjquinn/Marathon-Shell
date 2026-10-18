#ifndef DAVSECRETSTORE_H
#define DAVSECRETSTORE_H

#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QObject>
#include <QString>

#include <functional>

class QDBusMessage;

// Where DavSyncEngine keeps account secrets. Every call answers
// asynchronously; Unavailable means try again later (no keyring yet, or locked).
class DavSecretStore : public QObject {
    Q_OBJECT

  public:
    enum class Result : quint8 {
        Ok,
        NotFound,
        Unavailable
    };
    using Done = std::function<void(Result, const QString &secret)>;

    using QObject::QObject;

    virtual void store(const QString &accountId, const QString &label, const QString &secret,
                       const Done &done)                            = 0;
    virtual void load(const QString &accountId, const Done &done)   = 0;
    virtual void remove(const QString &accountId, const Done &done) = 0;
};

// org.freedesktop.secrets over QtDBus, plain session, default collection.
// Items carry { service: "marathon-dav", account_id: <id> }.
class SecretServiceStore : public DavSecretStore {
    Q_OBJECT

  public:
    explicit SecretServiceStore(const QDBusConnection &bus    = QDBusConnection::sessionBus(),
                                QObject               *parent = nullptr);

    void store(const QString &accountId, const QString &label, const QString &secret,
               const Done &done) override;
    void load(const QString &accountId, const Done &done) override;
    void remove(const QString &accountId, const Done &done) override;

  private:
    using Reply = std::function<void(const QDBusMessage &)>;
    void            call(const QString &path, const QString &interface, const QString &method,
                         const QVariantList &args, const Reply &onReply, const Done &done);
    void            withSession(const std::function<void()> &next, const Done &done);
    void            search(const QString                                             &accountId,
                           const std::function<void(const QList<QDBusObjectPath> &,
                                                    const QList<QDBusObjectPath> &)> &next,
                           const Done                                                &done);

    QDBusConnection m_bus;
    QDBusObjectPath m_session;
};

#endif
