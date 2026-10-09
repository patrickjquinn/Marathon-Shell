// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2014-2015 Jolla Ltd
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 * Copyright (C) 2014-2015 Jolla Ltd.
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

#include "SyncProfile.h"
#include "ProfileEngineDefs.h"
#include "LogMacros.h"

#include <QDomDocument>

namespace Buteo {

// Private implementation class for SyncProfile.
class SyncProfilePrivate
{
public:
    SyncProfilePrivate();
    SyncProfilePrivate(const SyncProfilePrivate &aSource);
    ~SyncProfilePrivate();

    SyncLog *iLog;

    SyncSchedule iSchedule;

    struct SyncRetriesInfo {
        QList<quint32> iRetryIntervals;
        quint32 iIntervalIndex;

        void init()
        {
            iIntervalIndex = 0;
        }

        void addInterval(quint32 interval)
        {
            iRetryIntervals.append(interval);
        }

        quint32 retries()
        {
            return iRetryIntervals.count();
        }

        qint32 nextInterval()
        {
            qint32 next = -1;
            if (iIntervalIndex < retries()) {
                next = iRetryIntervals.at(iIntervalIndex);
                ++iIntervalIndex;
            }
            return next;
        }

        QList<quint32> intervals()
        {
            return iRetryIntervals;
        }

        SyncRetriesInfo &operator=(const SyncRetriesInfo &rhs)
        {
            if (this != &rhs) {
                iIntervalIndex = rhs.iIntervalIndex;
                iRetryIntervals = rhs.iRetryIntervals;
            }
            return *this;
        }
    } iSyncRetriesInfo;
};

}

using namespace Buteo;

const quint32 DEFAULT_SOC_AFTER_TIME(5 * 60);

SyncProfilePrivate::SyncProfilePrivate()
    : iLog(nullptr)
{
    iSyncRetriesInfo.init();
}

SyncProfilePrivate::SyncProfilePrivate(const SyncProfilePrivate &aSource)
    : iLog(nullptr)
    , iSchedule(aSource.iSchedule)
{
    if (aSource.iLog != nullptr) {
        iLog = new SyncLog(*aSource.iLog);
    }
    iSyncRetriesInfo = aSource.iSyncRetriesInfo;
}

SyncProfilePrivate::~SyncProfilePrivate()
{
    delete iLog;
    iLog = nullptr;
}

SyncProfile::SyncProfile(const QString &aName)
    : Profile(aName, Profile::TYPE_SYNC)
    , d_ptr(new SyncProfilePrivate())
{
}

SyncProfile::SyncProfile(const QDomElement &aRoot)
    : Profile(aRoot)
    , d_ptr(new SyncProfilePrivate())
{
    QDomElement schedule = aRoot.firstChildElement(TAG_SCHEDULE);
    if (!schedule.isNull()) {
        d_ptr->iSchedule = SyncSchedule(schedule);
    }
    QDomElement retriesElement = aRoot.firstChildElement(TAG_ERROR_ATTEMPTS);
    if (!retriesElement.isNull()) {
        QDomElement timeElement  = retriesElement.firstChildElement(TAG_ATTEMPT_DELAY);
        while (!timeElement.isNull()) {
            bool ok = false;
            int parsedTime = timeElement.attribute(ATTR_VALUE, "-1").toUInt(&ok);
            if (ok && parsedTime > 0) {
                d_ptr->iSyncRetriesInfo.addInterval(parsedTime);
            }
            timeElement = timeElement.nextSiblingElement(TAG_ATTEMPT_DELAY);
        }
    }
}

SyncProfile::SyncProfile(const SyncProfile &aSource)
    : Profile(aSource)
    , d_ptr(new SyncProfilePrivate(*aSource.d_ptr))
{
}

SyncProfile::~SyncProfile()
{
    delete d_ptr;
    d_ptr = nullptr;
}

SyncProfile *SyncProfile::clone() const
{
    return new SyncProfile(*this);
}

QDomElement SyncProfile::toXml(QDomDocument &aDoc, bool aLocalOnly) const
{
    QDomElement root = Profile::toXml(aDoc, aLocalOnly);
    QDomElement schedule = d_ptr->iSchedule.toXml(aDoc);
    if (!schedule.isNull()) {
        root.appendChild(schedule);
    }
    if (d_ptr->iSyncRetriesInfo.retries()) {
        QDomElement retries = aDoc.createElement(TAG_ERROR_ATTEMPTS);
        for (quint32 i = 0;  i < d_ptr->iSyncRetriesInfo.retries(); ++i) {
            QDomElement retryInterval = aDoc.createElement(TAG_ATTEMPT_DELAY);
            qint32 nextInt = d_ptr->iSyncRetriesInfo.nextInterval();
            if (-1 != nextInt) {
                retryInterval.setAttribute(ATTR_VALUE, nextInt);
                retries.appendChild(retryInterval);
            }
        }
        root.appendChild(retries);
        d_ptr->iSyncRetriesInfo.init();
    }
    return root;
}

void SyncProfile::setName(const QString &aName)
{
    // sets the name in the super class Profile.
    Profile::setName(aName);
    // Here we also must set name for the log associated to this profile,
    // as that is only set during log construction. Changing SyncProfile name does not
    // reflect there
    if (d_ptr->iLog)
        d_ptr->iLog->setProfileName(aName);
}

void SyncProfile::setName(const QStringList &aKeys)
{
    // sets the name in the super class Profile.

    Profile::setName(aKeys);
    // Here we also must set name for the log associated to this profile,
    // as that is only set during log construction. Changing SyncProfile name does not
    // reflect there
    if (d_ptr->iLog)
        d_ptr->iLog->setProfileName(Profile::name());
}

bool SyncProfile::syncExternallyEnabled() const
{
    return boolKey(KEY_SYNC_EXTERNALLY, false);
}

bool SyncProfile::rushEnabled() const
{
    return d_ptr->iSchedule.rushEnabled() && d_ptr->iSchedule.scheduleEnabled();
}

bool SyncProfile::syncExternallyDuringRush() const
{
    return d_ptr->iSchedule.scheduleEnabled() && d_ptr->iSchedule.rushEnabled()
           && d_ptr->iSchedule.syncExternallyDuringRush();
}

bool SyncProfile::inExternalSyncRushPeriod(QDateTime aDateTime) const
{
    return d_ptr->iSchedule.inExternalSyncRushPeriod(aDateTime);
}

QDateTime SyncProfile::lastSyncTime() const
{
    QDateTime lastSync;

    if (d_ptr->iLog && d_ptr->iLog->lastResults() != nullptr) {
        lastSync = d_ptr->iLog->lastResults()->syncTime();
    }

    qCDebug(lcButeoCore) << "lastSync:" << lastSync;
    return lastSync;
}

QDateTime SyncProfile::lastSuccessfulSyncTime () const
{
    QDateTime lastSuccessSyncTime;
    if (d_ptr->iLog) {
        const SyncResults *success = d_ptr->iLog->lastSuccessfulResults();
        if (success)
            lastSuccessSyncTime = success->syncTime();
    }
    return lastSuccessSyncTime;
}

QDateTime SyncProfile::nextSyncTime(QDateTime aDateTime) const
{
    QDateTime nextSync;
    if (syncType() == SYNC_SCHEDULED) {
        if (aDateTime.isValid()) {
            nextSync = d_ptr->iSchedule.nextSyncTime(aDateTime);
        } else {
            nextSync = d_ptr->iSchedule.nextSyncTime(lastSyncTime());
        }

    }
    return nextSync;
}

QDateTime SyncProfile::nextRushSwitchTime(const QDateTime &aFromTime) const
{
    QDateTime nextSwitch;
    if (syncType() == SYNC_SCHEDULED) {
        nextSwitch = d_ptr->iSchedule.nextRushSwitchTime(aFromTime);
    }
    return nextSwitch;
}

const SyncResults *SyncProfile::lastResults() const
{
    if (d_ptr->iLog) {
        return d_ptr->iLog->lastResults();
    } else {
        return nullptr;
    }
}

SyncLog *SyncProfile::log() const
{
    return d_ptr->iLog;
}

void SyncProfile::setLog(SyncLog *aLog)
{
    delete d_ptr->iLog;
    d_ptr->iLog = aLog;
}

void SyncProfile::addResults(const SyncResults &aResults)
{
    if (!d_ptr->iLog) {
        d_ptr->iLog = new SyncLog(name());
    }

    d_ptr->iLog->addResults(aResults);
}

SyncProfile::SyncType SyncProfile::syncType() const
{
    // Sync schedule is enabled for peak or manual -> it is scheduled type.
    return !syncExternallyEnabled() && (d_ptr->iSchedule.scheduleEnabled()
                                        || d_ptr->iSchedule.rushEnabled()) ? SYNC_SCHEDULED : SYNC_MANUAL;
}

// TODO: seems effectless since d6d974e (Added functions to enable/disable normal scheduling.)
void SyncProfile::setSyncType(SyncType aType)
{
    setBoolKey(KEY_SYNC_SCHEDULED, aType == SYNC_SCHEDULED);
}

SyncSchedule SyncProfile::syncSchedule() const
{
    return d_ptr->iSchedule;
}

void SyncProfile::setSyncSchedule(const SyncSchedule &aSchedule)
{
    d_ptr->iSchedule = aSchedule;
}

QList<Sync::InternetConnectionType> SyncProfile::internetConnectionTypes() const
{
    QSet<Sync::InternetConnectionType> types;
    const QStringList typeStrings = key(KEY_INTERNET_CONNECTION_TYPES).split(',');
    foreach (QString typeString, typeStrings) {
        bool ok = false;
        int typeInt = typeString.toInt(&ok);
        if (!ok || typeInt < Sync::INTERNET_CONNECTION_UNKNOWN || typeInt > Sync::INTERNET_CONNECTION_LTE) {
            continue;
        }
        types.insert(Sync::InternetConnectionType(typeInt));
    }
    return types.values(); // Modified by Shipwright for Qt 6: QSet::values()
}

void SyncProfile::setInternetConnectionTypes(const QList<Sync::InternetConnectionType> &aTypes)
{
    QStringList typeStrings;
    foreach (Sync::InternetConnectionType type, aTypes) {
        typeStrings.append(QString::number(int(type)));
    }
    setKey(KEY_INTERNET_CONNECTION_TYPES, typeStrings.join(','));
}

QStringList SyncProfile::storageBackendNames() const
{
    QStringList enabledStorageBackends;
    QStringList storageNames = subProfileNames(Profile::TYPE_STORAGE);

    foreach (QString storage, storageNames) {
        const Profile *p = subProfile(storage, Profile::TYPE_STORAGE);
        if (p->isEnabled()) {
            // Get backend name from the storage profile. If the backend name
            // is not defined, use profile name as the backend name.
            enabledStorageBackends.append(p->key(KEY_BACKEND, p->name()));
        }
    }

    return enabledStorageBackends;
}

/*
QString SyncProfile::serviceName() const
{
    QStringList serviceNameList = subProfileNames(Profile::TYPE_SERVICE);

    if (serviceNameList.isEmpty())
        return QString();

    return serviceNameList.first();
}

const Profile *SyncProfile::serviceProfile() const
{
    QList<const Profile*> subProfiles = allSubProfiles();
    foreach (const Profile *p, subProfiles) {
        if (p->type() == TYPE_SERVICE) {
            return p;
        }
    }

    return 0;
}

Profile *SyncProfile::serviceProfile()
{
    QList<Profile*> subProfiles = allSubProfiles();
    foreach (Profile *p, subProfiles) {
        if (p->type() == TYPE_SERVICE) {
            return p;
        }
    }

    return 0;
}
*/

const Profile *SyncProfile::clientProfile() const
{
    QList<const Profile *> subProfiles = allSubProfiles();
    foreach (const Profile *p, subProfiles) {
        if (p->type() == TYPE_CLIENT) {
            return p;
        }
    }

    return nullptr;
}

Profile *SyncProfile::clientProfile()
{
    QList<Profile *> subProfiles = allSubProfiles();
    foreach (Profile *p, subProfiles) {
        if (p->type() == TYPE_CLIENT) {
            return p;
        }
    }

    return nullptr;
}

const Profile *SyncProfile::serverProfile() const
{
    QList<const Profile *> subProfiles = allSubProfiles();
    foreach (const Profile *p, subProfiles) {
        if (p->type() == TYPE_SERVER) {
            return p;
        }
    }

    return nullptr;
}

Profile *SyncProfile::serverProfile()
{
    QList<Profile *> subProfiles = allSubProfiles();
    foreach (Profile *p, subProfiles) {
        if (p->type() == TYPE_SERVER) {
            return p;
        }
    }

    return nullptr;
}

QList<const Profile *> SyncProfile::storageProfiles() const
{
    QList<const Profile *> storages;
    QList<const Profile *> subProfiles = allSubProfiles();
    foreach (const Profile *p, subProfiles) {
        if (p->type() == TYPE_STORAGE) {
            storages.append(p);
        }
    }

    return storages;
}

QList<Profile *> SyncProfile::storageProfilesNonConst()
{
    QList<Profile *> storages;
    QList<Profile *> subProfiles = allSubProfiles();
    foreach (Profile *p, subProfiles) {
        if (p->type() == TYPE_STORAGE) {
            storages.append(p);
        }
    }

    return storages;
}

SyncProfile::DestinationType SyncProfile::destinationType() const
{
    DestinationType type = DESTINATION_TYPE_UNDEFINED;
    QString typeStr;
    typeStr = this->key(KEY_DESTINATION_TYPE);

    if (typeStr == VALUE_ONLINE) {
        type = DESTINATION_TYPE_ONLINE;
    } else if (typeStr == VALUE_DEVICE) {
        type = DESTINATION_TYPE_DEVICE;
    } else {
        type = DESTINATION_TYPE_UNDEFINED;
    }

    return type;
}

SyncProfile::SyncDirection SyncProfile::syncDirection() const
{
    SyncDirection dir = SYNC_DIRECTION_UNDEFINED;
    QString dirStr;

    const Profile *client = clientProfile();
    if (client) {
        dirStr = client->key(KEY_SYNC_DIRECTION);
    }

    if (dirStr == VALUE_TWO_WAY) {
        dir = SYNC_DIRECTION_TWO_WAY;
    } else if (dirStr == VALUE_FROM_REMOTE) {
        dir = SYNC_DIRECTION_FROM_REMOTE;
    } else if (dirStr == VALUE_TO_REMOTE) {
        dir = SYNC_DIRECTION_TO_REMOTE;
    } else {
        dir = SYNC_DIRECTION_UNDEFINED;
    }

    return dir;
}

bool SyncProfile::isSOCProfile() const
{
    bool aSOCProfile = false;
    QString enabled = this->key(KEY_SOC);
    enabled = enabled.trimmed();
    if ("true" == enabled) {
        aSOCProfile = true;
    }
    return aSOCProfile;
}

quint32 SyncProfile::syncOnChangeAfter() const
{
    quint32 syncOnChangeAfterTime = DEFAULT_SOC_AFTER_TIME;

    QString time = this->key(KEY_SOC_AFTER);
    if (!time.isEmpty()) {
        bool ok = false;
        syncOnChangeAfterTime = time.toUInt(&ok);
        if (false == ok) {
            syncOnChangeAfterTime = DEFAULT_SOC_AFTER_TIME;
        }
    }
    qCDebug(lcButeoCore) << "Sync on change after time from profile :" << syncOnChangeAfterTime;
    return syncOnChangeAfterTime;
}

void SyncProfile::setSyncDirection(SyncDirection aDirection)
{
    QString dirStr;

    switch (aDirection) {
    case SYNC_DIRECTION_TWO_WAY:
        dirStr = VALUE_TWO_WAY;
        break;

    case SYNC_DIRECTION_FROM_REMOTE:
        dirStr = VALUE_FROM_REMOTE;
        break;

    case SYNC_DIRECTION_TO_REMOTE:
        dirStr = VALUE_TO_REMOTE;
        break;

    case SYNC_DIRECTION_UNDEFINED:
    default:
        // Value string is left as null. Key gets deleted when the value is set.
        break;
    }

    Profile *client = clientProfile();
    if (client) {
        client->setKey(KEY_SYNC_DIRECTION, dirStr);
    } else {
        qCWarning(lcButeoCore) << "Profile" << name() << "has no client profile";
        qCWarning(lcButeoCore) << "Failed to set sync direction";
    }
}

SyncProfile::ConflictResolutionPolicy SyncProfile::conflictResolutionPolicy() const
{
    ConflictResolutionPolicy policy = CR_POLICY_UNDEFINED;
    QString policyStr;

    const Profile *client = clientProfile();
    if (client) {
        policyStr = client->key(KEY_CONFLICT_RESOLUTION_POLICY);
    }

    if (policyStr == VALUE_PREFER_REMOTE) {
        policy = CR_POLICY_PREFER_REMOTE_CHANGES;
    } else if (policyStr == VALUE_PREFER_LOCAL) {
        policy = CR_POLICY_PREFER_LOCAL_CHANGES;
    } else {
        policy = CR_POLICY_UNDEFINED;
    }

    return policy;
}

void SyncProfile::setConflictResolutionPolicy(ConflictResolutionPolicy aPolicy)
{
    QString policyStr;

    switch (aPolicy) {
    case CR_POLICY_PREFER_REMOTE_CHANGES:
        policyStr = VALUE_PREFER_REMOTE;
        break;

    case CR_POLICY_PREFER_LOCAL_CHANGES:
        policyStr = VALUE_PREFER_LOCAL;
        break;

    case CR_POLICY_UNDEFINED:
    default:
        // Value string is left as null. Key gets deleted when the value is set.
        break;
    }

    Profile *client = clientProfile();
    if (client) {
        client->setKey(KEY_CONFLICT_RESOLUTION_POLICY, policyStr);
    } else {
        qCWarning(lcButeoCore) << "Profile" << name() << "has no client profile";
        qCWarning(lcButeoCore) << "Failed to set conflict resolution policy";
    }
}

bool SyncProfile::hasRetries() const
{
    return d_ptr->iSyncRetriesInfo.retries() > 0;
}

QList<quint32> SyncProfile::retryIntervals() const
{
    return d_ptr->iSyncRetriesInfo.intervals();
}

SyncProfile::CurrentSyncStatus SyncProfile::currentSyncStatus() const
{
    //Fetch the last sync result
    const SyncResults *syncResult = lastResults();
    SyncProfile::CurrentSyncStatus syncStatus = SyncProfile::SYNC_NEVER_HAPPENED;

    if (syncResult) {
        if ((syncResult->majorCode() == SyncResults::SYNC_RESULT_SUCCESS)
            && (syncResult->minorCode() == SyncResults::NO_ERROR))
            syncStatus = SyncProfile::SYNC_SUCCESS;
        else if (syncResult->majorCode() == SyncResults::SYNC_RESULT_FAILED)
            syncStatus = SyncProfile::SYNC_FAILED;
        else if (syncResult->majorCode() == SyncResults::SYNC_RESULT_CANCELLED)
            syncStatus = SyncProfile::SYNC_CANCLLED;
    }

    return syncStatus;
}
