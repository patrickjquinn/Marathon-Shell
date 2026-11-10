// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's Sailfish Policy API for Qt 6: the interface of an access policy
// plugin (as in Sailfish's libsailfishpolicy 0.4.26), for code that
// implements one. Keel's library does not load such plugins: Sailfish's
// plugin is a Qt 5 library. While one is installed, Keel reports every
// policy as unknown (see accesspolicy.h).

#ifndef SAILFISH_ACCESSPOLICYPLUGIN_H
#define SAILFISH_ACCESSPOLICYPLUGIN_H

#include <QObject>
#include <QVariant>

namespace Sailfish {

class Q_DECL_EXPORT AccessPolicyPlugin : public QObject
{
    Q_OBJECT
public:
    ~AccessPolicyPlugin() override = default;

    virtual QVariant keyValue(const QString &key) = 0;
    virtual void setKeyValue(const QString &key, const QVariant &value) = 0;

Q_SIGNALS:
    // moc writes the definition (parameters _t1, _t2).
    // NOLINTNEXTLINE(readability-inconsistent-declaration-parameter-name)
    void keyValueChanged(const QString &key, const QVariant &value);
};

} // namespace Sailfish

Q_DECLARE_INTERFACE(Sailfish::AccessPolicyPlugin, "org.sailfishos.AccessPolicyPlugin/1.0")

#endif // SAILFISH_ACCESSPOLICYPLUGIN_H
