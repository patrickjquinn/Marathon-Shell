#ifndef WAKETIMERS_H
#define WAKETIMERS_H

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusVariant>
#include <QHash>
#include <QObject>
#include <QStringList>
#include <functional>

// org.freedesktop.systemd1.Manager.StartTransientUnit's a(sv), a(sa(sv)) and
// ExecStart's a(sasb).
struct SystemdProperty {
    QString      name;
    QDBusVariant value;
};
using SystemdProperties = QList<SystemdProperty>;

struct SystemdAuxUnit {
    QString           name;
    SystemdProperties properties;
};

struct SystemdExecCommand {
    QString     path;
    QStringList argv;
    bool        ignoreFailure = false;
};

Q_DECLARE_METATYPE(SystemdProperty)
Q_DECLARE_METATYPE(SystemdAuxUnit)
Q_DECLARE_METATYPE(SystemdExecCommand)

QDBusArgument       &operator<<(QDBusArgument &arg, const SystemdProperty &p);
const QDBusArgument &operator>>(const QDBusArgument &arg, SystemdProperty &p);
QDBusArgument       &operator<<(QDBusArgument &arg, const SystemdAuxUnit &u);
const QDBusArgument &operator>>(const QDBusArgument &arg, SystemdAuxUnit &u);
QDBusArgument       &operator<<(QDBusArgument &arg, const SystemdExecCommand &c);
const QDBusArgument &operator>>(const QDBusArgument &arg, SystemdExecCommand &c);

// Transient systemd user timers named marathon-wake-*. marathon-background
// arm-wake reads them before a suspend and has the system wake for the
// earliest (docs/BACKGROUND_WORK.md).
class WakeTimers : public QObject {
    Q_OBJECT

  public:
    explicit WakeTimers(const QDBusConnection &bus, QObject *parent = nullptr);

    static void    registerTypes();
    static QString unitName(const QString &key, qint64 epochSecs);

    // Replaces key's timer with one elapsing at epochSecs, or removes it for
    // epochSecs <= 0. done says whether systemd holds the new timer.
    void set(const QString &key, qint64 epochSecs, const std::function<void(bool)> &done = {});

  private:
    void                    stop(const QString &unit);

    QDBusConnection         m_bus;
    QHash<QString, QString> m_units;
};

#endif
