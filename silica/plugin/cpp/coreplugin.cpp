// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Plugin class for Keel.SilicaCore: Sailfish.Silica's Theme singleton, in
// a module of its own that Sailfish.Silica re-exports (its qmldir imports
// this one). Sailfish.Silica.private's QML reads Theme too, and is compiled
// before Sailfish.Silica: with the type here, qmlcachegen knows it when it
// compiles both modules' QML to C++. (Screen stays in Sailfish.Silica: which
// `Screen` a document gets depends on its import order, screen.h.)

#include <QQmlEngine>
#include <QQmlEngineExtensionPlugin>

extern void qml_register_types_Keel_SilicaCore();

class KeelSilicaCorePlugin : public QQmlEngineExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlEngineExtensionInterface_iid)

public:
    explicit KeelSilicaCorePlugin(QObject *parent = nullptr)
        : QQmlEngineExtensionPlugin(parent)
    {
        volatile auto registration = &qml_register_types_Keel_SilicaCore;
        Q_UNUSED(registration)
    }
};

#include "coreplugin.moc"
