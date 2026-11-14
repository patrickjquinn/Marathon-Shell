// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 *
 * Contact: Sateesh Kavuri <sateesh.kavuri@nokia.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 *
 */

#include <QString>
#include <QDomDocument>
#include <ProfileManager.h>
#include <SyncProfile.h>
#include <SyncResults.h>
#include <SyncSchedule.h>
#include "SyncClientInterfacePrivate.h"
#include "SyncClientInterface.h"
#include "LogMacros.h"

using namespace Buteo;

static const QString SYNC_DBUS_OBJECT = "/synchronizer";
static const QString SYNC_DBUS_SERVICE = "com.meego.msyncd";

SyncClientInterfacePrivate::SyncClientInterfacePrivate(SyncClientInterface *aParent)
    : iParent(aParent)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    iServiceWatcher.addWatchedService(SYNC_DBUS_SERVICE);
    iServiceWatcher.setConnection(QDBusConnection::sessionBus());
    connect(&iServiceWatcher, &QDBusServiceWatcher::serviceOwnerChanged,
            this, &SyncClientInterfacePrivate::onServiceOwnerChanged);

    iSyncDaemon = new SyncDaemonProxy(SYNC_DBUS_SERVICE, SYNC_DBUS_OBJECT,
                                      QDBusConnection::sessionBus(), this);

    connect(iSyncDaemon, SIGNAL(signalProfileChanged(QString, int, QString)),
            this, SLOT(slotProfileChanged(QString, int, QString)));

    connect(iSyncDaemon, SIGNAL(resultsAvailable(QString, QString)), this,
            SLOT(resultsAvailable(QString, QString)));

    connect(this, SIGNAL(profileChanged(QString, int, QString)),
            iParent, SIGNAL(profileChanged(QString, int, QString)));

    connect(this, SIGNAL(resultsAvailable(QString, Buteo::SyncResults)),
            iParent, SIGNAL(resultsAvailable(QString, Buteo::SyncResults)));

    connect (iSyncDaemon, SIGNAL(syncStatus(QString, int, QString, int)),
             iParent, SIGNAL(syncStatus(QString, int, QString, int)));

    connect(iSyncDaemon, SIGNAL(transferProgress(QString, int, int, QString, int)),
            iParent, SIGNAL(transferProgress(QString, int, int, QString, int)));

    connect(iSyncDaemon, SIGNAL(backupInProgress()),
            iParent, SIGNAL(backupInProgress()));

    connect(iSyncDaemon, SIGNAL(backupDone()),
            iParent, SIGNAL(backupDone()));

    connect(iSyncDaemon, SIGNAL(restoreInProgress()),
            iParent, SIGNAL(restoreInProgress()));

    connect(iSyncDaemon, SIGNAL(restoreDone()),
            iParent, SIGNAL(restoreDone()));

    qRegisterMetaType<Buteo::Profile>("Buteo::Profile");
    qRegisterMetaType<Buteo::SyncResults>("Buteo::SyncResults");
}

SyncClientInterfacePrivate::~SyncClientInterfacePrivate()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    delete iSyncDaemon;
    iSyncDaemon = nullptr;
}

void SyncClientInterfacePrivate::onServiceOwnerChanged(const QString &serviceName, const QString &oldOwner, const QString &newOwner)
{
    Q_UNUSED(serviceName);
    Q_UNUSED(oldOwner);
    Q_UNUSED(newOwner);

    emit iParent->isValidChanged();
}

bool SyncClientInterfacePrivate::startSync(const QString &aProfileId) const
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    bool syncStatus = false;

    if (iSyncDaemon && !aProfileId.isEmpty()) {
        syncStatus = iSyncDaemon->startSync(aProfileId);
    }

    return syncStatus;
}

QDBusPendingCallWatcher* SyncClientInterfacePrivate::requestSync(const QString &aProfileId, QObject *aParent)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    return new QDBusPendingCallWatcher(iSyncDaemon->startSync(aProfileId), aParent ? aParent : this);
}

void SyncClientInterfacePrivate::abortSync(const QString &aProfileId) const
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    if (iSyncDaemon && !aProfileId.isEmpty()) {
        iSyncDaemon->abortSync(aProfileId);
    }
}

QStringList SyncClientInterfacePrivate::getRunningSyncList()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    QStringList runningSyncList;
    if (iSyncDaemon) {
        runningSyncList = iSyncDaemon->runningSyncs();
    }
    return runningSyncList;
}

QDBusPendingCallWatcher* SyncClientInterfacePrivate::requestRunningSyncList(QObject *aParent)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    return new QDBusPendingCallWatcher(iSyncDaemon->runningSyncs(), aParent ? aParent : this);
}

bool SyncClientInterfacePrivate::removeProfile(const QString &aProfileId)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    bool status = false;
    if (iSyncDaemon) {
        status = iSyncDaemon->removeProfile(aProfileId);
    }
    return status;
}

bool SyncClientInterfacePrivate::updateProfile(const Buteo::SyncProfile &aProfile)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    bool status = false;
    if (iSyncDaemon) {
        QString profileAsXmlString = aProfile.toString();
        status = iSyncDaemon->updateProfile(profileAsXmlString);
    }
    return status;
}

void SyncClientInterfacePrivate::slotProfileChanged(QString aProfileId, int aChangeType,
                                                    QString aProfileAsXml)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    emit profileChanged(aProfileId, aChangeType, aProfileAsXml);
}

void SyncClientInterfacePrivate::resultsAvailable(QString aProfileId,
                                                  QString aLastResultsAsXml)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    QDomDocument doc;
    if (doc.setContent(aLastResultsAsXml, true)) {
        Buteo::SyncResults results(doc.documentElement());
        emit resultsAvailable(aProfileId, results);
    } else {
        qCDebug(lcButeoCore) << "Invalid Profile Xml Received from msyncd";
    }
}

bool SyncClientInterfacePrivate::setSyncSchedule(const QString &aProfileId,
                                                 const SyncSchedule &aSchedule)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    bool status = false;
    if (iSyncDaemon) {
        QString scheduleAsXmlString = aSchedule.toString();
        if (!scheduleAsXmlString.isEmpty()) {
            status = iSyncDaemon->setSyncSchedule(aProfileId,
                                                  scheduleAsXmlString);
        }
    }
    return status;
}

bool SyncClientInterfacePrivate::saveSyncResults(const QString &aProfileId,
                                                 const Buteo::SyncResults &aSyncResults)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    bool status = false;
    if (iSyncDaemon) {
        QString resultsAsXmlString = aSyncResults.toString();
        if (!resultsAsXmlString.isEmpty()) {
            status = iSyncDaemon->saveSyncResults(aProfileId, resultsAsXmlString);
        }
    }
    return status;
}

bool  SyncClientInterfacePrivate::getBackUpRestoreState()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    bool status = false;
    if (iSyncDaemon) {
        status = iSyncDaemon->getBackUpRestoreState();
    }
    return status;
}

bool SyncClientInterfacePrivate::isValid()
{
    return (iSyncDaemon && iSyncDaemon->isValid());
}

Buteo::SyncResults SyncClientInterfacePrivate::getLastSyncResult(const QString &aProfileId)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    if (iSyncDaemon) {
        QString resultASXmlString = iSyncDaemon->getLastSyncResult(aProfileId);
        QDomDocument doc;

        if (doc.setContent(resultASXmlString, true)) {
            Buteo::SyncResults result(doc.documentElement());
            return result;
        } else {
            qCCritical(lcButeoCore) << "Invalid Profile Xml Received from msyncd";
        }
    }
    return SyncResults(QDateTime(),
                       SyncResults::SYNC_RESULT_INVALID, SyncResults::NO_ERROR);
}

QList<QString /*profilesAsXml*/> SyncClientInterfacePrivate::allVisibleSyncProfiles()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    QList <QString> profilesAsXml;
    if (iSyncDaemon) {
        QStringList profilesList = iSyncDaemon->allVisibleSyncProfiles();
        if (!profilesList.isEmpty()) {
            foreach (QString profileAsXml, profilesList) {
                profilesAsXml.append(profileAsXml);
            }
        }
    }
    qCDebug(lcButeoCore) << "allVisibleSyncProfiles " << profilesAsXml;
    return profilesAsXml;
}

QDBusPendingCallWatcher* SyncClientInterfacePrivate::requestAllVisibleSyncProfiles(QObject *aParent)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    return new QDBusPendingCallWatcher(iSyncDaemon->allVisibleSyncProfiles(), aParent ? aParent : this);
}

QString SyncClientInterfacePrivate::syncProfile(const QString &aProfileId)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    QString profileAsXml;

    if (iSyncDaemon) {
        profileAsXml = iSyncDaemon->syncProfile(aProfileId);
    }

    qCDebug(lcButeoCore) << "syncProfile " << profileAsXml;
    return profileAsXml;
}

QStringList SyncClientInterfacePrivate::syncProfilesByKey(const QString &aKey, const QString &aValue)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    QStringList profileAsXml;

    if (iSyncDaemon) {
        profileAsXml = iSyncDaemon->syncProfilesByKey(aKey, aValue);
    }

    return profileAsXml;
}

QDBusPendingCallWatcher* SyncClientInterfacePrivate::requestSyncProfilesByKey(const QString &aKey, const QString &aValue, QObject *aParent)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    return new QDBusPendingCallWatcher(iSyncDaemon->syncProfilesByKey(aKey, aValue), aParent ? aParent : this);
}

QStringList SyncClientInterfacePrivate::syncProfilesByType(const QString &aType)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    QStringList profileIds;

    if (iSyncDaemon) {
        profileIds = iSyncDaemon->syncProfilesByType(aType);
    }

    return profileIds;
}

QStringList SyncClientInterfacePrivate::profilesByType(const QString &aType)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    QStringList profileIds;

    if (iSyncDaemon) {
        profileIds = iSyncDaemon->profilesByType(aType);
    }

    return profileIds;
}

QDBusPendingCallWatcher* SyncClientInterfacePrivate::requestProfilesByType(const QString &aType, QObject *aParent)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    return new QDBusPendingCallWatcher(iSyncDaemon->profilesByType(aType), aParent ? aParent : this);
}
