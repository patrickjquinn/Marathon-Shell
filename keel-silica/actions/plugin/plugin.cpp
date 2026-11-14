// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// QML plugin for `Keel.Actions 1.0` (ADR-0018). The types are registered by
// qmltyperegistrar (QML_ELEMENT); loading the plugin also creates the app's
// action registry, so that an app whose actions are all native (Rust) only
// needs the import.

#include "keelregistry.h"

#include <QQmlEngine>
#include <QQmlEngineExtensionPlugin>

extern void qml_register_types_Keel_Actions();

class KeelActionsPlugin : public QQmlEngineExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlEngineExtensionInterface_iid)

public:
    explicit KeelActionsPlugin(QObject *parent = nullptr)
        : QQmlEngineExtensionPlugin(parent)
    {
        volatile auto registration = &qml_register_types_Keel_Actions;
        Q_UNUSED(registration)
    }

    void initializeEngine(QQmlEngine *engine, const char *uri) override
    {
        Q_UNUSED(engine)
        Q_UNUSED(uri)
        KeelActionRegistry::instance()->serve();
    }
};

#include "plugin.moc"
