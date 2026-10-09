// SPDX-FileCopyrightText: 2012 - 2022 Jolla Ltd
// SPDX-FileCopyrightText: 2019 - 2021 Open Mobile Platform LLC
// SPDX-FileCopyrightText: 2011 Robin Burchell
// SPDX-FileCopyrightText: 2012 Timur Kristóf
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-only
//
// Modified by Shipwright for Qt 6 (marked at the change).

// Copyright (c) 2012 - 2022 Jolla Ltd.
// Copyright (c) 2019 - 2021 Open Mobile Platform LLC.
//
// This file is part of lipstick, a QML desktop library
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License version 2.1 as published by the Free Software Foundation
// and appearing in the file LICENSE.LGPL included in the packaging
// of this file.
//
// This code is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// Copyright (c) 2011, Robin Burchell
// Copyright (c) 2012, Timur Kristóf <venemo@fedoraproject.org>

#include <QProcess>
#include <QFile>
#include <QDesktopServices>
#include <QDir>
#include <QSettings>
#include <QTimerEvent>
#include <QRegularExpression>
#include <QRegularExpressionMatch>
#include <QUrl>
#include <QDBusConnection>
#include <QDBusPendingCall>
#include <QDBusPendingReply>
#include <QDBusMetaType>

#include <mdesktopentry.h>
#include <mremoteaction.h>

#include "launcheritem.h"
#include "launchermodel.h"
#include "logging.h"

#ifdef HAVE_CONTENTACTION
#include <contentaction.h>
#else
#undef signals
#include <gio/gdesktopappinfo.h>
#include <gio/gio.h>
#include <glib.h>
#endif

#include <QDebug>

// TODO: These values should be in some header coming from sailjail
const auto SailjailService = QStringLiteral("org.sailfishos.sailjaild1");
const auto SailjailPath = QStringLiteral("/org/sailfishos/sailjaild1");
const auto SailjailInterface = QStringLiteral("org.sailfishos.sailjaild1");
const auto SailjailGetAppInfo = QStringLiteral("GetAppInfo");
const auto SailjailInvalidName = QStringLiteral("Invalid application name: ");
const auto SailjailInfoKeyMode = QStringLiteral("Mode");
const auto SailjailModeNone = QStringLiteral("None");
const auto DesktopEntryGroup = QStringLiteral("Desktop Entry");
const auto DBusActivatableKey = QStringLiteral("DBusActivatable");

typedef QMap<QString, QDBusVariant> PropertyMap;

LauncherItem::LauncherItem(const QString &filePath, QObject *parent)
    : QObject(parent)
    , m_isLaunching(false)
    , m_isUpdating(false)
    , m_isTemporary(false)
    , m_updatingProgress(-1)
    , m_serial(0)
    , m_isBlacklisted(false)
    , m_mimeTypesPopulated(false)
    , m_sandboxingInfoFetched(false)
    , m_sandboxed(false)
{
    if (!filePath.isEmpty()) {
        setFilePath(filePath);
        initializeSandboxingInfo();
    }

    // TODO: match the PID of the window thumbnails with the launcher processes
    // Launching animation will be disabled if the window of the launched app shows up
}

LauncherItem::LauncherItem(const QString &packageName, const QString &label,
                           const QString &iconPath, const QString &desktopFile, QObject *parent)
    : QObject(parent)
    , m_isLaunching(false)
    , m_isUpdating(false)
    , m_isTemporary(false)
    , m_packageName(packageName)
    , m_updatingProgress(-1)
    , m_customTitle(label)
    , m_customIconFilename(iconPath)
    , m_serial(0)
    , m_isBlacklisted(false)
    , m_mimeTypesPopulated(false)
    , m_sandboxingInfoFetched(false)
    , m_sandboxed(false)
{
    if (!desktopFile.isEmpty()) {
        setFilePath(desktopFile);
        initializeSandboxingInfo();
    }
}

LauncherItem::~LauncherItem()
{
}

LauncherModel::ItemType LauncherItem::type() const
{
    return LauncherModel::Application;
}

void LauncherItem::setFilePath(const QString &filePath)
{
    /* Note that sequences like:
     * - LauncherModel::updatingStarted()  (register non-existing file)
     * - LauncherModel::onFilesUpdated()   (re-evaluate now existing file)
     * - LauncherModel::updatingFinished()
     * require that this method:
     * - Must retain given filePath even if the file does not exist
     * - Must re-evaluate file content even if filePath does not change
     */
    m_serviceName.clear();
    m_desktopEntry.clear();

    if (!filePath.isEmpty()) {
        m_desktopEntry = QSharedPointer<MDesktopEntry>(new MDesktopEntry(filePath));
    }

    if (!m_desktopEntry.isNull() && m_desktopEntry->isValid()) {
        const QString organisation = m_desktopEntry->value(QStringLiteral("X-Sailjail"),
                                                           QStringLiteral("OrganizationName"));
        const QString application = m_desktopEntry->value(QStringLiteral("X-Sailjail"),
                                                          QStringLiteral("ApplicationName"));

        if (!organisation.isEmpty() && !application.isEmpty()) {
            m_serviceName = organisation + QLatin1Char('.') + application;
        } else {
            const int slash = filePath.lastIndexOf(QLatin1Char('/')) + 1;
            const int period = filePath.indexOf(QLatin1Char('.'), slash);

            m_serviceName = period > 0 && period < filePath.count() - 8 // strlen(".desktop")
                    ? filePath.mid(slash, filePath.count() - slash - 8)
                    : QString();
        }
    }

    emit this->itemChanged();
}

void LauncherItem::initializeSandboxingInfo()
{
    qDBusRegisterMetaType<PropertyMap>();
    auto bus = QDBusConnection::systemBus();
    bus.connect(SailjailService, SailjailPath, SailjailInterface, "ApplicationAdded",
                this, SLOT(sandboxingInfoChanged(QString)));
    bus.connect(SailjailService, SailjailPath, SailjailInterface, "ApplicationChanged",
                this, SLOT(sandboxingInfoChanged(QString)));
    fetchSandboxingInfo();
}

void LauncherItem::fetchSandboxingInfo()
{
    auto message = QDBusMessage::createMethodCall(SailjailService, SailjailPath, SailjailInterface,
                                                  SailjailGetAppInfo);
    message.setArguments({ sandboxingName() });
    QDBusPendingCall async = QDBusConnection::systemBus().asyncCall(message);
    QDBusPendingCallWatcher *call = new QDBusPendingCallWatcher(async, this);
    connect(call, &QDBusPendingCallWatcher::finished,
            this, [this](QDBusPendingCallWatcher *call) {
        QDBusPendingReply<PropertyMap> reply = *call;
        if (reply.isError()) {
            auto error = reply.error();
            if (error.type() == QDBusError::InvalidArgs && error.message().startsWith(SailjailInvalidName))
                qCDebug(lcLipstickAppLaunchLog) << "No sandboxing info for" << sandboxingName();
            else
                qCWarning(lcLipstickAppLaunchLog) << "Error fetching sandboxing info for"
                                                  << sandboxingName() << error.name() << error.message();
        } else {
            qCDebug(lcLipstickAppLaunchLog) << "Received sandboxing info for" << sandboxingName();
            const auto map = reply.argumentAt<0>();
            m_sandboxed = map[SailjailInfoKeyMode].variant().toString() != SailjailModeNone;
            m_sandboxingInfoFetched = true;
            emit itemChanged();
        }
        call->deleteLater();
    });
}

void LauncherItem::sandboxingInfoChanged(const QString &appname)
{
    if (appname == sandboxingName())
        fetchSandboxingInfo();
}

QString LauncherItem::sandboxingName() const
{
    return QFileInfo(filePath()).completeBaseName();
}

QString LauncherItem::filePath() const
{
    return !m_desktopEntry.isNull() ? m_desktopEntry->fileName() : QString();
}

QString LauncherItem::fileID() const
{
    if (m_desktopEntry.isNull()) {
        return QString();
    }

    // Retrieve the file ID according to
    // http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html
    QRegularExpression re(".*applications/(.*.desktop)");
    QRegularExpressionMatch match = re.match(m_desktopEntry->fileName());
    if (!match.hasMatch()) {
        return filename();
    }

    QString id = match.captured(1);
    id.replace('/', '-');
    return id;
}

QString LauncherItem::filename() const
{
    QString filename = filePath();
    int sep = filename.lastIndexOf('/');
    if (sep == -1)
        return QString();

    return filename.mid(sep+1);
}

QString LauncherItem::exec() const
{
    return !m_desktopEntry.isNull() ? m_desktopEntry->exec() : QString();
}

bool LauncherItem::dBusActivatable() const
{
    QString activatable = m_desktopEntry->value(DesktopEntryGroup, DBusActivatableKey);
    if (activatable.isEmpty())
        activatable = m_desktopEntry->value(DesktopEntryGroup, QStringLiteral("X-") + DBusActivatableKey);
    return activatable == QLatin1String("true");
}

bool LauncherItem::dBusActivated() const
{
    return !m_desktopEntry.isNull() && (!m_desktopEntry->xMaemoService().isEmpty() || dBusActivatable());
}

MRemoteAction LauncherItem::remoteAction(const QStringList &arguments) const
{
    if (m_desktopEntry) {
        const QString service = m_desktopEntry->xMaemoService();
        const QString method = m_desktopEntry->value(QStringLiteral("Desktop Entry/X-Maemo-Method"));

        const int period = method.lastIndexOf(QLatin1Char('.'));

        if (!service.isEmpty() && !method.isEmpty() && period != -1) {
            const QString path = m_desktopEntry->value(QStringLiteral("Desktop Entry/X-Maemo-Object-Path"));
            // similar to libcontentaction / dbus.cpp, assuming we want the fixed parameters first
            const QString fixedArgs = m_desktopEntry->value(QStringLiteral("Desktop Entry/X-Maemo-Fixed-Args"));
            QStringList totalArguments = fixedArgs.split(';', Qt::SkipEmptyParts) + arguments; // Modified by Shipwright for Qt 6: Qt::SkipEmptyParts

            return MRemoteAction(
                        service,
                        path.isEmpty() ? QStringLiteral("/") : path,
                        method.left(period),
                        method.mid(period + 1),
                        { QVariant::fromValue(totalArguments) });
        } else if (!m_serviceName.isEmpty() && dBusActivatable()) {
            const QString path = QLatin1Char('/') + (QString(m_serviceName)
                                                     .replace(QLatin1Char('.'), QLatin1Char('/'))
                                                     .replace(QLatin1Char('-'), QLatin1Char('_')));
            const QString interface = QStringLiteral("org.freedesktop.Application");

            QVariantList dBusArguments;
            if (!arguments.isEmpty())
                dBusArguments.append(QVariant::fromValue(arguments));
            // platform-data, currently unpopulated
            dBusArguments.append(QVariant::fromValue(QVariantMap()));

            return MRemoteAction(
                        m_serviceName,
                        path,
                        interface,
                        arguments.isEmpty() ? QStringLiteral("Activate") : QStringLiteral("Open"),
                        dBusArguments);
        }
    }

    return MRemoteAction();
}

QString LauncherItem::title() const
{
    if (m_isTemporary) {
        return m_customTitle;
    }

    return !m_desktopEntry.isNull() ? m_desktopEntry->name() : QString();
}

QString LauncherItem::entryType() const
{
    return !m_desktopEntry.isNull() ? m_desktopEntry->type() : QString();
}

QString LauncherItem::iconId() const
{
    if (!m_customIconFilename.isEmpty()) {
        return QString("%1#serial=%2").arg(m_customIconFilename).arg(m_serial);
    }

    return getOriginalIconId();
}

QStringList LauncherItem::desktopCategories() const
{
    return !m_desktopEntry.isNull() ? m_desktopEntry->categories() : QStringList();
}

QStringList LauncherItem::mimeType() const
{
    return !m_desktopEntry.isNull() ? m_desktopEntry->mimeType() : QStringList();
}

QString LauncherItem::titleUnlocalized() const
{
    if (m_isTemporary) {
        return m_customTitle;
    }

    return !m_desktopEntry.isNull() ? m_desktopEntry->nameUnlocalized() : QString();
}

bool LauncherItem::shouldDisplay() const
{
    if (m_desktopEntry.isNull()) {
        return m_isTemporary;
    }

    return !m_desktopEntry->noDisplay() && !m_desktopEntry->notShowIn().contains(QStringLiteral("X-MeeGo"));
}

bool LauncherItem::isSandboxed() const
{
    if (m_sandboxingInfoFetched) {
        return m_sandboxed;
    }

    return !m_desktopEntry.isNull() && m_desktopEntry->isSandboxed();
}

bool LauncherItem::isValid() const
{
    return !m_desktopEntry.isNull() ? m_desktopEntry->isValid() : m_isTemporary;
}

bool LauncherItem::isLaunching() const
{
    return m_isLaunching;
}

void LauncherItem::setIsLaunching(bool isLaunching)
{
    if (isLaunching) {
        // This is a failsafe to allow launching again after 5 seconds in case the
        // application crashes on startup and no window is ever created
        m_launchingTimeout.start(5000, this);
    } else {
        m_launchingTimeout.stop();
    }
    if (m_isLaunching != isLaunching) {
        m_isLaunching = isLaunching;
        emit this->isLaunchingChanged();
    }
}

void LauncherItem::setIsUpdating(bool isUpdating)
{
    if (m_isUpdating != isUpdating) {
        m_isUpdating = isUpdating;
        emit isUpdatingChanged();
    }
}

void LauncherItem::setIsTemporary(bool isTemporary)
{
    if (m_isTemporary != isTemporary) {
        m_isTemporary = isTemporary;
        emit isTemporaryChanged();
    }
}

QString LauncherItem::dBusServiceName() const
{
    return m_serviceName;
}

void LauncherItem::launchApplication()
{
    launchWithArguments(QStringList());
}

#if !defined(HAVE_CONTENTACTION)
static void setupProcessIds(gpointer)
{
    const gid_t gid = getgid();
    const uid_t uid = getuid();

    if (setregid(gid, gid) < 0 || setreuid(uid, uid) < 0) {
        ::_exit(EXIT_FAILURE);
    }
}
#endif

void LauncherItem::launchWithArguments(const QStringList &arguments)
{
    if (m_isUpdating) {
        LauncherModel *model = static_cast<LauncherModel *>(parent());
        model->requestLaunch(m_packageName);
        return;
    }

    if (m_desktopEntry.isNull())
        return;

    if (m_desktopEntry->type() == QLatin1String("Link")) {
        QString url = m_desktopEntry->url();

        if (!url.isEmpty()) {
            QDesktopServices::openUrl(QUrl(QStringLiteral("file:///")).resolved(url));
        }
        return;
    }

#if defined(HAVE_CONTENTACTION)
    LAUNCHER_DEBUG("launching content action for" << m_desktopEntry->name());
    ContentAction::Action action = ContentAction::Action::launcherAction(m_desktopEntry, arguments);
    action.trigger();
#else
    LAUNCHER_DEBUG("launching exec line for" << m_desktopEntry->name());

    if (GDesktopAppInfo *appInfo = g_desktop_app_info_new_from_filename(
                m_desktopEntry->fileName().toUtf8().constData())) {
        GError *error = 0;
        GList *uris = NULL;

        for (const QString &argument : arguments) {
            uris = g_list_append(uris, g_strdup(argument.toUtf8().constData()));
        }

        g_desktop_app_info_launch_uris_as_manager(
                    appInfo,
                    uris,
                    NULL,
                    G_SPAWN_SEARCH_PATH,
                    setupProcessIds,
                    NULL,
                    NULL,
                    NULL,
                    &error);

        if (error != NULL) {
            qCWarning(lcLipstickAppLaunchLog) << "Failed to execute" << filename() << error->message;
            g_error_free(error);
        }
        g_list_foreach(uris, (GFunc)g_free, NULL);
        g_list_free(uris);

        g_object_unref(appInfo);
    }
#endif

    setIsLaunching(true);
}

bool LauncherItem::isStillValid()
{
    if (m_isTemporary) {
        return true;
    }

    // Force a reload of m_desktopEntry
    setFilePath(filePath());
    return isValid();
}

QString LauncherItem::getOriginalIconId() const
{
    return !m_desktopEntry.isNull() ? m_desktopEntry->icon() : QString();
}

void LauncherItem::setIconFilename(const QString &path)
{
    m_customIconFilename = path;
    if (!path.isEmpty()) {
        m_serial++;
    }
    emit itemChanged();
}

QString LauncherItem::iconFilename() const
{
    return m_customIconFilename;
}

void LauncherItem::setPackageName(QString packageName)
{
    if (m_packageName != packageName) {
        m_packageName = packageName;
        emit packageNameChanged();
    }
}

void LauncherItem::setUpdatingProgress(int updatingProgress)
{
    if (m_updatingProgress != updatingProgress) {
        m_updatingProgress = updatingProgress;
        emit updatingProgressChanged();
    }
}

bool LauncherItem::isBlacklisted() const
{
    return m_isBlacklisted;
}

void LauncherItem::setIsBlacklisted(bool isBlacklisted)
{
    if (m_isBlacklisted != isBlacklisted) {
        m_isBlacklisted = isBlacklisted;
        emit isBlacklistedChanged();
    }
}

void LauncherItem::setCustomTitle(QString customTitle)
{
    if (m_customTitle != customTitle) {
        m_customTitle = customTitle;
        emit itemChanged();
    }
}

QString LauncherItem::readValue(const QString &key) const
{
    if (m_desktopEntry.isNull())
        return QString();

    return m_desktopEntry->value("Desktop Entry", key);
}

bool LauncherItem::canOpenMimeType(const QString &mimeType)
{
    if (!m_mimeTypesPopulated && m_desktopEntry) {
        m_mimeTypesPopulated = true;

        for (QString mimeType : m_desktopEntry->mimeType()) {
            m_mimeTypes.append(QRegularExpression(mimeType.replace("*", ".*"),
                                                  QRegularExpression::CaseInsensitiveOption));
        }
    }

    for (const QRegularExpression &candidate : m_mimeTypes) {
        QRegularExpressionMatch match = candidate.match(mimeType);

        if (match.captured().length() == mimeType.length()) {
            return true;
        }
    }

    return false;
}

void LauncherItem::invalidateCaches()
{
    m_mimeTypes.clear();
    m_mimeTypesPopulated = false;
    m_sandboxingInfoFetched = false;
}

void LauncherItem::timerEvent(QTimerEvent *event)
{
    if (event->timerId() == m_launchingTimeout.timerId()) {
        setIsLaunching(false);
    } else {
        QObject::timerEvent(event);
    }
}
