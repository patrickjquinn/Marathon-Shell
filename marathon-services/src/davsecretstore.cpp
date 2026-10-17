#include "davsecretstore.h"

#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <QDebug>
#include <QMap>

#include <memory>

namespace {

    constexpr char kService[]     = "org.freedesktop.secrets";
    constexpr char kServicePath[] = "/org/freedesktop/secrets";
    constexpr char kServiceIf[]   = "org.freedesktop.Secret.Service";
    constexpr char kItemIf[]      = "org.freedesktop.Secret.Item";
    constexpr char kCollIf[]      = "org.freedesktop.Secret.Collection";

    using Attributes = QMap<QString, QString>;

    struct Secret {
        QDBusObjectPath session;
        QByteArray      parameters;
        QByteArray      value;
        QString         contentType;
    };

    QDBusArgument &operator<<(QDBusArgument &a, const Secret &s) {
        a.beginStructure();
        a << s.session << s.parameters << s.value << s.contentType;
        a.endStructure();
        return a;
    }

    const QDBusArgument &operator>>(const QDBusArgument &a, Secret &s) {
        a.beginStructure();
        a >> s.session >> s.parameters >> s.value >> s.contentType;
        a.endStructure();
        return a; // NOLINT(bugprone-return-const-ref-from-parameter)
    }

    Attributes attributesFor(const QString &accountId) {
        return {{QStringLiteral("service"), QStringLiteral("marathon-dav")},
                {QStringLiteral("account_id"), accountId}};
    }

    bool isNone(const QDBusObjectPath &p) {
        return p.path().isEmpty() || p.path() == QLatin1String("/");
    }

} // namespace

SecretServiceStore::SecretServiceStore(const QDBusConnection &bus, QObject *parent)
    : DavSecretStore(parent)
    , m_bus(bus) {
    qDBusRegisterMetaType<Secret>();
    qDBusRegisterMetaType<Attributes>();
}

void SecretServiceStore::call(const QString &path, const QString &interface, const QString &method,
                              const QVariantList &args, const Reply &onReply, const Done &done) {
    QDBusMessage msg = QDBusMessage::createMethodCall(kService, path, interface, method);
    msg.setArguments(args);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, onReply, done] {
        watcher->deleteLater();
        const QDBusMessage reply = watcher->reply();
        if (reply.type() != QDBusMessage::ReplyMessage) {
            qWarning() << "DavSecretStore:" << reply.errorName() << reply.errorMessage();
            m_session = {};
            done(Result::Unavailable, {});
            return;
        }
        onReply(reply);
    });
}

void SecretServiceStore::withSession(const std::function<void()> &next, const Done &done) {
    if (!isNone(m_session)) {
        next();
        return;
    }
    call(
        kServicePath, kServiceIf, QStringLiteral("OpenSession"),
        {QStringLiteral("plain"), QVariant::fromValue(QDBusVariant(QString()))},
        [this, next](const QDBusMessage &reply) {
            m_session = qdbus_cast<QDBusObjectPath>(reply.arguments().value(1));
            next();
        },
        done);
}

void SecretServiceStore::search(
    const QString &accountId,
    const std::function<void(const QList<QDBusObjectPath> &, const QList<QDBusObjectPath> &)> &next,
    const Done &done) {
    call(
        kServicePath, kServiceIf, QStringLiteral("SearchItems"),
        {QVariant::fromValue(attributesFor(accountId))},
        [next](const QDBusMessage &reply) {
            next(qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().value(0)),
                 qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().value(1)));
        },
        done);
}

void SecretServiceStore::store(const QString &accountId, const QString &label,
                               const QString &secret, const Done &done) {
    withSession(
        [this, accountId, label, secret, done] {
            call(
                kServicePath, kServiceIf, QStringLiteral("ReadAlias"), {QStringLiteral("default")},
                [this, accountId, label, secret, done](const QDBusMessage &reply) {
                    const auto collection = qdbus_cast<QDBusObjectPath>(reply.arguments().value(0));
                    if (isNone(collection)) {
                        done(Result::Unavailable, {});
                        return;
                    }
                    const QVariantMap props{
                        {QStringLiteral("org.freedesktop.Secret.Item.Label"), label},
                        {QStringLiteral("org.freedesktop.Secret.Item.Attributes"),
                         QVariant::fromValue(attributesFor(accountId))}};
                    const Secret s{m_session, {}, secret.toUtf8(), QStringLiteral("text/plain")};
                    call(
                        collection.path(), kCollIf, QStringLiteral("CreateItem"),
                        {props, QVariant::fromValue(s), true},
                        [done](const QDBusMessage &created) {
                            const auto prompt =
                                qdbus_cast<QDBusObjectPath>(created.arguments().value(1));
                            done(isNone(prompt) ? Result::Ok : Result::Unavailable, {});
                        },
                        done);
                },
                done);
        },
        done);
}

void SecretServiceStore::load(const QString &accountId, const Done &done) {
    withSession(
        [this, accountId, done] {
            search(
                accountId,
                [this, done](const QList<QDBusObjectPath> &unlocked,
                             const QList<QDBusObjectPath> &locked) {
                    if (unlocked.isEmpty()) {
                        done(locked.isEmpty() ? Result::NotFound : Result::Unavailable, {});
                        return;
                    }
                    call(
                        unlocked.first().path(), kItemIf, QStringLiteral("GetSecret"),
                        {QVariant::fromValue(m_session)},
                        [done](const QDBusMessage &reply) {
                            const auto s = qdbus_cast<Secret>(reply.arguments().value(0));
                            done(Result::Ok, QString::fromUtf8(s.value));
                        },
                        done);
                },
                done);
        },
        done);
}

void SecretServiceStore::remove(const QString &accountId, const Done &done) {
    search(
        accountId,
        [this, done](const QList<QDBusObjectPath> &unlocked, const QList<QDBusObjectPath> &locked) {
            if (!locked.isEmpty()) {
                done(Result::Unavailable, {});
                return;
            }
            if (unlocked.isEmpty()) {
                done(Result::NotFound, {});
                return;
            }
            struct Pending {
                qsizetype left;
                bool      failed = false;
            };
            auto       pending = std::make_shared<Pending>(Pending{unlocked.size()});
            const auto step    = [pending, done](bool ok) {
                pending->failed |= !ok;
                if (--pending->left == 0)
                    done(pending->failed ? Result::Unavailable : Result::Ok, {});
            };
            for (const QDBusObjectPath &item : unlocked) {
                call(
                    item.path(), kItemIf, QStringLiteral("Delete"), {},
                    [step](const QDBusMessage &reply) {
                        step(isNone(qdbus_cast<QDBusObjectPath>(reply.arguments().value(0))));
                    },
                    [step](Result, const QString &) { step(false); });
            }
        },
        done);
}
