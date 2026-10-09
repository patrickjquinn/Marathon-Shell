// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Policy 1.0 on Keel: PolicyValue (creatable) and the AccessPolicy
// singleton, as Sailfish's QML module registers them (its plugins.qmltypes;
// jolla-camera reads AccessPolicy.cameraEnabled and .microphoneEnabled).

#include <accesspolicy.h>
#include <policyvalue.h>

#include <QQmlEngine>
#include <QQmlExtensionPlugin>

class SailfishPolicyPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override
    {
        Q_ASSERT(QLatin1String(uri) == QLatin1String("Sailfish.Policy"));
        qmlRegisterType<Sailfish::PolicyValue>(uri, 1, 0, "PolicyValue");
        qmlRegisterSingletonType<Sailfish::AccessPolicy>(uri, 1, 0, "AccessPolicy",
                                                         [](QQmlEngine *, QJSEngine *) -> QObject * {
                                                             return new Sailfish::AccessPolicy;
                                                         });
    }
};

#include "plugin.moc"
