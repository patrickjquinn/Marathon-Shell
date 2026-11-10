// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: the policy store PolicyValue and AccessPolicy read (see
// accesspolicy.h): /var/lib/policy/policy.conf, followed for changes, and the
// privacy switch daemon. One per process, in the main thread.
// KEEL_POLICY_DIR and KEEL_POLICY_PLUGIN replace the directory and the
// plugin path (tests).

#ifndef SAILFISH_POLICYSTORE_P_H
#define SAILFISH_POLICYSTORE_P_H

#include <QFileSystemWatcher>
#include <QHash>
#include <QLoggingCategory>
#include <QObject>
#include <QString>
#include <QVariant>

Q_DECLARE_LOGGING_CATEGORY(lcSailfishPolicy)

namespace Sailfish {

class PolicyStore : public QObject
{
    Q_OBJECT
public:
    static PolicyStore *instance();

    // Whether the store could be read.
    bool available() const { return m_available; }
    // A policy's value: true or false, or invalid while the store cannot be
    // read. A policy policy.conf does not mention is true.
    QVariant value(const QString &key) const;
    // value() as a bool, false unless true.
    bool enabled(int type) const;
    bool privacyModeActive() const { return m_privacyModeActive; }

    static QString keyForType(int type);
    static int typeForKey(const QString &key);

signals:
    void changed();
    void privacyModeActiveChanged();

private slots:
    void reload();
    void setPrivacyModeActive(bool active);

private:
    explicit PolicyStore(QObject *parent = nullptr);
    void watch();
    void followPrivacySwitch();

    QString m_dir;
    QString m_plugin;
    QFileSystemWatcher m_watcher;
    bool m_available = false;
    QHash<QString, QString> m_values;
    bool m_privacyModeActive = false;
};

} // namespace Sailfish

#endif // SAILFISH_POLICYSTORE_P_H
