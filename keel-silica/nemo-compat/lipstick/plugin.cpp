// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// org.nemomobile.lipstick 0.1 for Keel apps: lipstick's launcher types
// (upstream/, LGPL-2.1-only, built for Qt 6) as lipstick's own plugin
// registers them: LauncherItem, LauncherModel, LauncherWatcherModel,
// LauncherFolderModel and LauncherFolderItem. The home screen's types
// (compositor, windows, notifications list, volume, USB mode, shutdown and
// screenshot) belong to Lipstick's process and are not provided to apps.

#include "components/launcherfolderitem.h"
#include "components/launcherfoldermodel.h"
#include "components/launcheritem.h"
#include "components/launchermodel.h"
#include "components/launcherwatchermodel.h"

#include <QQmlExtensionPlugin>
#include <QQmlParserStatus>
#include <QtQml/qqml.h>

namespace {

// The models start reading .desktop files once QML has set their
// properties (lipstick's plugin does the same).
class KeelLauncherModel : public LauncherModel, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
public:
    explicit KeelLauncherModel(QObject *parent = nullptr)
        : LauncherModel(DeferInitialization, parent)
    {
    }
    void classBegin() override { }
    void componentComplete() override { initialize(); }
};

class KeelLauncherFolderModel : public LauncherFolderModel, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
public:
    explicit KeelLauncherFolderModel(QObject *parent = nullptr)
        : LauncherFolderModel(DeferInitialization, parent)
    {
    }
    void classBegin() override { }
    void componentComplete() override { initialize(); }
};

} // namespace

class KeelLipstickPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.nemomobile.lipstick")

public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterType<KeelLauncherModel>(uri, 0, 1, "LauncherModel");
        qmlRegisterType<LauncherWatcherModel>(uri, 0, 1, "LauncherWatcherModel");
        qmlRegisterType<LauncherItem>(uri, 0, 1, "LauncherItem");
        qmlRegisterType<KeelLauncherFolderModel>(uri, 0, 1, "LauncherFolderModel");
        qmlRegisterType<LauncherFolderItem>(uri, 0, 1, "LauncherFolderItem");
    }
};

#include "plugin.moc"
