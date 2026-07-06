// Copyright (C) 2018 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
// Qt-Security score:significant reason:default

#include <QtWaylandCompositor/private/qwlclientbufferintegrationfactory_p.h>
#include <QtWaylandCompositor/private/qwlclientbufferintegrationplugin_p.h>
#include "linuxdmabufclientbufferintegration.h"

QT_BEGIN_NAMESPACE

class QWaylandDmabufClientBufferIntegrationPlugin : public QtWayland::ClientBufferIntegrationPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QtWaylandClientBufferIntegrationFactoryInterface_iid FILE "linux-dmabuf-v1.json")
public:
    QtWayland::ClientBufferIntegration *create(const QString& key, const QStringList& paramList) override;
};

QtWayland::ClientBufferIntegration *QWaylandDmabufClientBufferIntegrationPlugin::create(const QString& key, const QStringList& paramList)
{
    Q_UNUSED(paramList);
    Q_UNUSED(key);
    return new LinuxDmabufClientBufferIntegration();
}

QT_END_NAMESPACE

#include "main.moc"
