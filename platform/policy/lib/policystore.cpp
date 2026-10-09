// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// See policystore_p.h.

#include "policystore_p.h"

#include "policyvalue.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QFile>
#include <QFileInfo>
#include <QMetaEnum>
#include <QPointer>

Q_LOGGING_CATEGORY(lcSailfishPolicy, "sailfish.policy", QtWarningMsg)

namespace Sailfish {

namespace {

const QString PrivacyService = QStringLiteral("org.sailfishos.privacyswitch");
const QString PrivacyPath = QStringLiteral("/privacyswitch");
const QString PrivacyInterface = QStringLiteral("org.sailfishos.privacyswitch");

// Reads a GLib key file's [policy] group into values. False when the file
// is not a key file GLib would load: a line that is neither blank, a
// comment, a [group] header nor key=value.
bool parseKeyFile(const QByteArray &data, QHash<QString, QString> *values)
{
    QString group;
    const QList<QByteArray> lines = data.split('\n');
    for (const QByteArray &rawLine : lines) {
        const QString line = QString::fromUtf8(rawLine).trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        if (line.startsWith(QLatin1Char('['))) {
            if (!line.endsWith(QLatin1Char(']')))
                return false;
            group = line.mid(1, line.size() - 2);
            continue;
        }
        const qsizetype eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0 || group.isEmpty())
            return false;
        if (group == QLatin1String("policy"))
            values->insert(line.left(eq).trimmed(), line.mid(eq + 1).trimmed());
    }
    return true;
}

} // namespace

PolicyStore *PolicyStore::instance()
{
    static QPointer<PolicyStore> store;
    if (!store) {
        store = new PolicyStore;
        // Gone with the application, like the objects that use it.
        if (QCoreApplication *app = QCoreApplication::instance())
            store->setParent(app);
    }
    return store;
}

PolicyStore::PolicyStore(QObject *parent)
    : QObject(parent)
    , m_dir(qEnvironmentVariable("KEEL_POLICY_DIR", QStringLiteral("/var/lib/policy")))
    , m_plugin(qEnvironmentVariable("KEEL_POLICY_PLUGIN", QStringLiteral(KEEL_POLICY_PLUGIN_PATH)))
{
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &PolicyStore::reload);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &PolicyStore::reload);
    reload();
    followPrivacySwitch();
}

void PolicyStore::watch()
{
    const QStringList watched = m_watcher.files() + m_watcher.directories();
    if (!watched.isEmpty())
        m_watcher.removePaths(watched);
    // The directory, or its parent until it exists; the file once it does.
    const QFileInfo dir(m_dir);
    if (dir.isDir())
        m_watcher.addPath(m_dir);
    else if (QFileInfo(dir.absolutePath()).isDir())
        m_watcher.addPath(dir.absolutePath());
    const QString file = m_dir + QStringLiteral("/policy.conf");
    if (QFileInfo(file).isFile())
        m_watcher.addPath(file);
}

void PolicyStore::reload()
{
    watch();
    bool available = false;
    QHash<QString, QString> values;
    const QFileInfo dir(m_dir);
    const QFileInfo file(m_dir + QStringLiteral("/policy.conf"));
    if (QFileInfo::exists(m_plugin)) {
        qCWarning(lcSailfishPolicy) << "an access policy plugin is installed (" << m_plugin
                                    << "), which Keel cannot load: every policy is reported as unknown";
    } else if (!dir.isDir() || !dir.isReadable() || !dir.isExecutable()) {
        qCInfo(lcSailfishPolicy) << m_dir << "cannot be read: every policy is reported as unknown";
    } else if (!file.exists()) {
        available = true; // no MDM policy set
    } else {
        QFile f(file.filePath());
        if (!file.isFile() || !f.open(QIODevice::ReadOnly))
            qCWarning(lcSailfishPolicy) << file.filePath() << "cannot be read: every policy is reported as unknown";
        else if (!parseKeyFile(f.readAll(), &values))
            qCWarning(lcSailfishPolicy) << file.filePath() << "is not a key file: every policy is reported as unknown";
        else
            available = true;
    }
    if (!available)
        values.clear();
    if (available == m_available && values == m_values)
        return;
    m_available = available;
    m_values = values;
    emit changed();
}

QVariant PolicyStore::value(const QString &key) const
{
    if (!m_available || typeForKey(key) == PolicyValue::Unknown)
        return {};
    const auto it = m_values.constFind(key);
    if (it == m_values.constEnd())
        return true;
    // GLib's booleans; anything else is no value GLib would read as true.
    return it.value() == QLatin1String("true") || it.value() == QLatin1String("1");
}

bool PolicyStore::enabled(int type) const
{
    const QVariant v = value(keyForType(type));
    return v.isValid() && v.toBool();
}

QString PolicyStore::keyForType(int type)
{
    if (type == PolicyValue::Unknown)
        return {};
    const QMetaEnum e = QMetaEnum::fromType<PolicyValue::PolicyType>();
    return QString::fromLatin1(e.valueToKey(type));
}

int PolicyStore::typeForKey(const QString &key)
{
    if (key.isEmpty())
        return PolicyValue::Unknown;
    const QMetaEnum e = QMetaEnum::fromType<PolicyValue::PolicyType>();
    bool ok = false;
    const int type = e.keyToValue(key.toLatin1().constData(), &ok);
    return ok ? type : static_cast<int>(PolicyValue::Unknown);
}

// The analyzer cannot see QObject ownership: the watcher is a child of this
// store and deletes itself once the call finishes.
// NOLINTBEGIN(clang-analyzer-cplusplus.NewDeleteLeaks)
void PolicyStore::followPrivacySwitch()
{
    // privacyswitchd (on devices with a privacy switch) answers
    // privacyModeActive and signals privacyModeActiveChanged(bool active).
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;
    bus.connect(PrivacyService, PrivacyPath, PrivacyInterface, QStringLiteral("privacyModeActiveChanged"), this,
                SLOT(setPrivacyModeActive(bool)));
    const QDBusMessage call = QDBusMessage::createMethodCall(PrivacyService, PrivacyPath, PrivacyInterface,
                                                             QStringLiteral("privacyModeActive"));
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<bool> reply = *w;
        if (reply.isValid())
            setPrivacyModeActive(reply.value());
    });
}
// NOLINTEND(clang-analyzer-cplusplus.NewDeleteLeaks)

void PolicyStore::setPrivacyModeActive(bool active)
{
    if (m_privacyModeActive == active)
        return;
    m_privacyModeActive = active;
    emit privacyModeActiveChanged();
}

} // namespace Sailfish
