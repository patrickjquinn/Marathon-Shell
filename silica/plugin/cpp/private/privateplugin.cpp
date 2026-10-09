// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Plugin class for Sailfish.Silica.private: Keel's clean-room native types
// that Silica's BSD QML uses (names inferred from that QML; see
// keel/silica/PROVENANCE.md, "Native types").

#include <QQmlEngineExtensionPlugin>

extern void qml_register_types_Sailfish_Silica_private();

class SailfishSilicaPrivatePlugin : public QQmlEngineExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlEngineExtensionInterface_iid)

public:
    explicit SailfishSilicaPrivatePlugin(QObject *parent = nullptr)
        : QQmlEngineExtensionPlugin(parent)
    {
        volatile auto registration = &qml_register_types_Sailfish_Silica_private;
        Q_UNUSED(registration)
    }
};

#include "privateplugin.moc"
