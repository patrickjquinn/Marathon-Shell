#include "waketimers.h"

#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QRegularExpression>

namespace {
    QDBusMessage managerCall(const QString &method) {
        return QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.systemd1"), QStringLiteral("/org/freedesktop/systemd1"),
            QStringLiteral("org.freedesktop.systemd1.Manager"), method);
    }

    SystemdProperty unitProperty(const QString &name, const QVariant &value) {
        return {name, QDBusVariant(value)};
    }
}

QDBusArgument &operator<<(QDBusArgument &arg, const SystemdProperty &p) {
    arg.beginStructure();
    arg << p.name << p.value;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, SystemdProperty &p) {
    arg.beginStructure();
    arg >> p.name >> p.value;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter)
}

QDBusArgument &operator<<(QDBusArgument &arg, const SystemdAuxUnit &u) {
    arg.beginStructure();
    arg << u.name << u.properties;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, SystemdAuxUnit &u) {
    arg.beginStructure();
    arg >> u.name >> u.properties;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter)
}

QDBusArgument &operator<<(QDBusArgument &arg, const SystemdExecCommand &c) {
    arg.beginStructure();
    arg << c.path << c.argv << c.ignoreFailure;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, SystemdExecCommand &c) {
    arg.beginStructure();
    arg >> c.path >> c.argv >> c.ignoreFailure;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter)
}

WakeTimers::WakeTimers(const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
    , m_bus(bus) {
    registerTypes();
}

void WakeTimers::registerTypes() {
    qDBusRegisterMetaType<SystemdProperty>();
    qDBusRegisterMetaType<SystemdProperties>();
    qDBusRegisterMetaType<SystemdAuxUnit>();
    qDBusRegisterMetaType<QList<SystemdAuxUnit>>();
    qDBusRegisterMetaType<SystemdExecCommand>();
    qDBusRegisterMetaType<QList<SystemdExecCommand>>();
}

QString WakeTimers::unitName(const QString &key, qint64 epochSecs) {
    return QStringLiteral("marathon-wake-%1-%2.timer").arg(key, QString::number(epochSecs));
}

void WakeTimers::set(const QString &key, qint64 epochSecs, const std::function<void(bool)> &done) {
    static const QRegularExpression validKey(QStringLiteral("^[A-Za-z0-9_.-]+$"));
    if (!validKey.match(key).hasMatch()) {
        qWarning() << "[WakeTimers] Refusing wake-up key" << key;
        if (done)
            done(false);
        return;
    }

    // The time is in the name: a stopped transient unit can linger for a
    // moment, so reusing one name would race its garbage collection.
    const QString unit = epochSecs > 0 ? unitName(key, epochSecs) : QString();
    const QString old  = m_units.value(key);
    if (unit == old) {
        if (done)
            done(true);
        return;
    }
    if (!old.isEmpty())
        stop(old);
    if (unit.isEmpty()) {
        m_units.remove(key);
        if (done)
            done(true);
        return;
    }
    m_units.insert(key, unit);

    QString service = unit;
    service.replace(service.size() - 6, 6, QStringLiteral(".service"));
    const SystemdProperties timer{
        unitProperty(QStringLiteral("Description"),
                     QStringLiteral("Marathon wake-up: %1").arg(key)),
        unitProperty(QStringLiteral("OnCalendar"), QStringLiteral("@%1").arg(epochSecs)),
        unitProperty(QStringLiteral("RemainAfterElapse"), false),
    };
    // arm-wake only needs the timer's next elapse; the service it starts
    // does nothing.
    const QList<SystemdAuxUnit> aux{
        {service,
         {unitProperty(
             QStringLiteral("ExecStart"),
             QVariant::fromValue(QList<SystemdExecCommand>{
                 {QStringLiteral("/bin/true"), {QStringLiteral("/bin/true")}, false}}))}}};

    QDBusMessage call = managerCall(QStringLiteral("StartTransientUnit"));
    call << unit << QStringLiteral("fail") << QVariant::fromValue(timer)
         << QVariant::fromValue(aux);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, key, unit, done](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                const QDBusPendingReply<QDBusObjectPath> reply = *w;
                // A previous shell left the same wake-up behind.
                const bool ok = !reply.isError() ||
                    reply.error().name() == QLatin1String("org.freedesktop.systemd1.UnitExists");
                if (!ok) {
                    qWarning() << "[WakeTimers] Could not start" << unit << ":"
                               << reply.error().message();
                    if (m_units.value(key) == unit)
                        m_units.remove(key);
                }
                if (done)
                    done(ok);
            });
}

void WakeTimers::stop(const QString &unit) {
    QDBusMessage call = managerCall(QStringLiteral("StopUnit"));
    call << unit << QStringLiteral("replace");
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [unit](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<QDBusObjectPath> reply = *w;
        // An elapsed timer has already unloaded itself.
        if (reply.isError() &&
            reply.error().name() != QLatin1String("org.freedesktop.systemd1.NoSuchUnit"))
            qWarning() << "[WakeTimers] Could not stop" << unit << ":" << reply.error().message();
    });
}
