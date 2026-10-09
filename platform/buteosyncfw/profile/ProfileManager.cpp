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

#include "ProfileManager.h"

#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QDomDocument>

#include "ProfileFactory.h"
#include "ProfileEngineDefs.h"
#include "SyncCommonDefs.h"

#include "LogMacros.h"
#include "BtHelper.h"

// implement here in lack of better place. not sure should this even be included in the api
const QString Sync::syncConfigDir()
{
    // This is the root for all sorts of things: data, config, logs, so using .local/share/
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/system/privileged/msyncd";
}

const QString Sync::syncCacheDir()
{
    // IF we need a cache dir for something, this should return such, but now just
    // returning config as this has been used for such
    qWarning() << "Sync::syncCacheDir() is deprecated, use Sync::syncConfigDir(). Or not even that if possible";
    return Sync::syncConfigDir();
}

static const QString FORMAT_EXT = ".xml";
static const QString BACKUP_EXT = ".bak";
static const QString LOG_EXT = ".log";
static const QString LOG_DIRECTORY = "logs";
static const QString BT_PROFILE_TEMPLATE("bt_template");

static const QString DEFAULT_PRIMARY_PROFILE_PATH = Sync::syncConfigDir();
static const QString DEFAULT_SECONDARY_PROFILE_PATH = "/etc/buteo/profiles";

namespace Buteo {

class ProfileManagerPrivate
{
public:
    ProfileManagerPrivate();

    /*! \brief Loads a profile from persistent storage.
     *
     * \param aName Name of the profile to load.
     * \param aType Type of the profile to load.
     * \return The loaded profile. 0 if the profile was not found.
     */
    Profile *load(const QString &aName, const QString &aType);

    /*! \brief Loads the synchronization log associated with the given profile.
     *
     * \param aProfileName Name of the sync profile whose log shall be loaded.
     * \return The loaded log. 0 if the log was not found.
     */
    SyncLog *loadLog(const QString &aProfileName);

    bool parseFile(const QString &aPath, QDomDocument &aDoc);
    void restoreBackupIfFound(const QString &aProfilePath,
                              const QString &aBackupPath);
    QDomDocument constructProfileDocument(const Profile &aProfile);
    bool writeProfileFile(const QString &aProfilePath, const QDomDocument &aDoc);
    QString findProfileFile(const QString &aName, const QString &aType);
    bool createBackup(const QString &aProfilePath, const QString &aBackupPath);
    bool matchProfile(const Profile &aProfile,
                      const ProfileManager::SearchCriteria &aCriteria);
    bool matchKey(const Profile &aProfile,
                  const ProfileManager::SearchCriteria &aCriteria);
    bool save(const Profile &aProfile);
    bool remove(const QString &aName, const QString &aType);
    bool profileExists(const QString &aProfileId, const QString &aType);

    QString iConfigPath;
    QString iSystemConfigPath;
    QHash<QString, QList<quint32> > iSyncRetriesInfo;
};

}

using namespace Buteo;

ProfileManagerPrivate::ProfileManagerPrivate()
    : iConfigPath(DEFAULT_PRIMARY_PROFILE_PATH)
    , iSystemConfigPath(DEFAULT_SECONDARY_PROFILE_PATH)
{
}

Profile *ProfileManagerPrivate::load(const QString &aName, const QString &aType)
{
    QString profilePath = findProfileFile(aName, aType);
    QString backupProfilePath = profilePath + BACKUP_EXT;

    QDomDocument doc;
    Profile *profile = nullptr;

    restoreBackupIfFound(profilePath, backupProfilePath);

    if (parseFile(profilePath, doc)) {
        ProfileFactory pf;
        profile = pf.createProfile(doc.documentElement());

        if (QFile::exists(backupProfilePath)) {
            QFile::remove(backupProfilePath);
        }
    } else {
        qCDebug(lcButeoCore) << "Failed to load profile:" << aName;
    }

    return profile;
}

SyncLog *ProfileManagerPrivate::loadLog(const QString &aProfileName)
{
    QString fileName = iConfigPath + QDir::separator() + Profile::TYPE_SYNC + QDir::separator()
                       + LOG_DIRECTORY + QDir::separator() + aProfileName + LOG_EXT + FORMAT_EXT;

    if (!QFile::exists(fileName)) {
        return nullptr;
    }

    QFile file(fileName);
    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(lcButeoCore) << "Failed to open sync log file for reading:"
                    << file.fileName();
        return nullptr;
    }

    QDomDocument doc;
    if (!doc.setContent(&file)) {
        file.close();
        qCWarning(lcButeoCore) << "Failed to parse XML from sync log file:"
                    << file.fileName();
        return nullptr;
    }

    file.close();

    return new SyncLog(doc.documentElement());
}

bool ProfileManagerPrivate::matchProfile(const Profile &aProfile,
                                         const ProfileManager::SearchCriteria &aCriteria)
{
    bool matched = false;

    const Profile *testProfile = &aProfile;
    if (!aCriteria.iSubProfileName.isEmpty()) {
        // Sub-profile name was given, request a sub-profile with a
        // matching name and type.
        testProfile = aProfile.subProfile(aCriteria.iSubProfileName,
                                          aCriteria.iSubProfileType);

        if (testProfile != 0) {
            matched = matchKey(*testProfile, aCriteria);
        } else {
            matched = (aCriteria.iType == ProfileManager::SearchCriteria::NOT_EXISTS);
        }
    } else if (!aCriteria.iSubProfileType.isEmpty()) {
        // Sub-profile name was empty, but type was given. Get all
        // sub-profiles with the matching type.
        QStringList subProfileNames = aProfile.subProfileNames(aCriteria.iSubProfileType);

        if (!subProfileNames.isEmpty()) {
            matched = false;

            foreach (const QString &subProfileName, subProfileNames) {
                testProfile = aProfile.subProfile(subProfileName,
                                                  aCriteria.iSubProfileType);
                if (testProfile != 0 && matchKey(*testProfile, aCriteria)) {
                    matched = true;
                    break;
                }
            }
        } else {
            matched = (aCriteria.iType == ProfileManager::SearchCriteria::NOT_EXISTS);
        }
    } else {
        matched = matchKey(aProfile, aCriteria);
    }

    return matched;
}

bool ProfileManagerPrivate::matchKey(const Profile &aProfile,
                                     const ProfileManager::SearchCriteria &aCriteria)
{
    bool matched = false;

    if (!aCriteria.iKey.isEmpty()) {
        // Key name was given, get a key with matching name.
        QString value = aProfile.key(aCriteria.iKey);

        if (value.isNull()) {
            if (aCriteria.iType == ProfileManager::SearchCriteria::NOT_EXISTS ||
                    aCriteria.iType == ProfileManager::SearchCriteria::NOT_EQUAL) {
                matched = true;
            } else {
                matched = false;
            }
        } else {
            switch (aCriteria.iType) {
            case ProfileManager::SearchCriteria::EXISTS:
                matched = true;
                break;

            case ProfileManager::SearchCriteria::NOT_EXISTS:
                matched = false;
                break;

            case ProfileManager::SearchCriteria::EQUAL:
                matched = (value == aCriteria.iValue);
                break;

            case ProfileManager::SearchCriteria::NOT_EQUAL:
                matched = (value != aCriteria.iValue);
                break;

            default:
                matched = false;
                break;
            }
        }
    } else {
        matched = (aCriteria.iType != ProfileManager::SearchCriteria::NOT_EXISTS);
    }

    return matched;
}

ProfileManager::SearchCriteria::SearchCriteria()
    : iType(ProfileManager::SearchCriteria::EQUAL)
{
}

ProfileManager::SearchCriteria::SearchCriteria(const SearchCriteria &aSource)
    : iType(aSource.iType)
    , iSubProfileName(aSource.iSubProfileName)
    , iSubProfileType(aSource.iSubProfileType)
    , iKey(aSource.iKey)
    , iValue(aSource.iValue)
{
}

ProfileManager::SearchCriteria &ProfileManager::SearchCriteria::operator=(const ProfileManager::SearchCriteria &other)
{
    if (&other == this) {
        return *this;
    }

    iType = other.iType;
    iSubProfileName = other.iSubProfileName;
    iSubProfileType = other.iSubProfileType;
    iKey = other.iKey;
    iValue = other.iValue;

    return *this;
}

ProfileManager::ProfileManager()
    : d_ptr(new ProfileManagerPrivate)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
}

ProfileManager::~ProfileManager()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    delete d_ptr;
    d_ptr = nullptr;
}

void ProfileManager::setPaths(const QString &configPath, const QString &systemConfigPath)
{
    if (!configPath.isEmpty()) {
        d_ptr->iConfigPath = configPath;
        if (d_ptr->iConfigPath.endsWith(QDir::separator())) {
            d_ptr->iConfigPath.chop(1);
        }
    }

    if (!systemConfigPath.isEmpty()) {
        d_ptr->iSystemConfigPath = systemConfigPath;
        if (d_ptr->iSystemConfigPath.endsWith(QDir::separator())) {
            d_ptr->iSystemConfigPath.chop(1);
        }
    }
}

Profile *ProfileManager::profile(const QString &aName, const QString &aType)
{
    return d_ptr->load(aName, aType);
}

SyncProfile *ProfileManager::syncProfile(const QString &aName)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    Profile *p = profile(aName, Profile::TYPE_SYNC);
    SyncProfile *syncProfile = nullptr;

    if (p != nullptr && p->type() == Profile::TYPE_SYNC) {
        // RTTI is not allowed, use static_cast. Should be safe, because
        // type is verified.
        syncProfile = static_cast<SyncProfile *>(p);

        // Load and merge all sub-profiles.
        expand(*syncProfile);

        // Load sync log. If not found, create an empty log.
        if (syncProfile->log() == nullptr) {
            SyncLog *log = d_ptr->loadLog(aName);
            if (!log) {
                log = new SyncLog(aName);
            }
            syncProfile->setLog(log);
        }
    } else {
        qCDebug(lcButeoCore) << "did not find a valid sync profile with the given name:" << aName;
        if (p != nullptr) {
            qCDebug(lcButeoCore) << "but found a profile of type:" << p->type() << "with the given name:" << aName;
            delete p;
        }
    }

    return syncProfile;
}

QStringList ProfileManager::profileNames(const QString &aType)
{
    // Search for all profile files from the config directory
    QStringList names;
    QString nameFilter = QString("*") + FORMAT_EXT;

    {
        QDir dir(d_ptr->iConfigPath + QDir::separator() + aType);
        QFileInfoList fileInfoList = dir.entryInfoList(QStringList(nameFilter),
                                                       QDir::Files | QDir::NoSymLinks);
        foreach (const QFileInfo &fileInfo, fileInfoList) {
            names.append(fileInfo.completeBaseName());
        }
    }

    // Search for all profile files from the system config directory
    {
        QDir dir(d_ptr->iSystemConfigPath + QDir::separator() + aType);
        QFileInfoList fileInfoList = dir.entryInfoList(QStringList(nameFilter),
                                                       QDir::Files | QDir::NoSymLinks);
        foreach (const QFileInfo &fileInfo, fileInfoList) {
            // Add only if the list does not yet contain the name.
            QString profileName = fileInfo.completeBaseName();
            if (!names.contains(profileName)) {
                names.append(profileName);
            }
        }
    }

    return names;
}

QList<SyncProfile *> ProfileManager::allSyncProfiles()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QList<SyncProfile *> profiles;

    QStringList names = profileNames(Profile::TYPE_SYNC);
    foreach (const QString &name, names) {
        SyncProfile *p = syncProfile(name);
        if (p != nullptr) {
            profiles.append(p);
        }
    }

    return profiles;
}

QList<SyncProfile *> ProfileManager::allVisibleSyncProfiles()
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QList<SyncProfile *> profiles = allSyncProfiles();
    QList<SyncProfile *> visibleProfiles;
    foreach (SyncProfile *p, profiles) {
        if (!p->isHidden()) {
            visibleProfiles.append(p);
        } else {
            delete p;
        }
    }

    return visibleProfiles;
}

QList<SyncProfile *> ProfileManager::getSyncProfilesByData(const QString &aSubProfileName,
                                                           const QString &aSubProfileType,
                                                           const QString &aKey, const QString &aValue)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QList<SyncProfile *> allProfiles = allSyncProfiles();
    QList<SyncProfile *> matchingProfiles;

    foreach (SyncProfile *profile, allProfiles) {
        Profile *testProfile = profile;
        if (!aSubProfileName.isEmpty()) {
            // Sub-profile name was given, request a sub-profile with a
            // matching name and type.
            testProfile = profile->subProfile(aSubProfileName, aSubProfileType);
        } else if (!aSubProfileType.isEmpty()) {
            // Sub-profile name was empty, but type was given. Get the first
            // sub-profile with the matching type.
            QStringList subProfileNames =
                profile->subProfileNames(aSubProfileType);
            if (!subProfileNames.isEmpty()) {
                testProfile = profile->subProfile(subProfileNames.first(),
                                                  aSubProfileType);
            } else {
                testProfile = nullptr;
            }
        }

        if (!testProfile) { // Sub-profile was not found.
            delete profile;
            profile = nullptr;
            continue; // Not a match, continue with next profile.
        }

        if (!aKey.isEmpty()) {
            // Key name was given, get a key with matching name.
            QString value = testProfile->key(aKey);
            if (value.isNull() || // Key was not found.
                    (!aValue.isEmpty() && (value != aValue))) { // Value didn't match
                delete profile;
                profile = nullptr;
                continue; // Not a match, continue with next profile.
            }
        }

        // Match, add profile to the list to be returned.
        matchingProfiles.append(profile);
    }

    return matchingProfiles;
}

QList<SyncProfile *> ProfileManager::getSyncProfilesByData(const QList<SearchCriteria> &aCriteria)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QList<SyncProfile *> allProfiles = allSyncProfiles();
    QList<SyncProfile *> matchingProfiles;

    foreach (SyncProfile *profile, allProfiles) {
        bool matched = true;
        if (profile == nullptr)
            continue;

        foreach (const SearchCriteria &criteria, aCriteria) {
            if (!d_ptr->matchProfile(*profile, criteria)) {
                matched = false;
                break;
            }
        }

        if (matched) {
            matchingProfiles.append(profile);
        } else {
            delete profile;
            profile = nullptr;
        }
    }

    return matchingProfiles;
}

QList<SyncProfile *> ProfileManager::getSOCProfilesForStorage(
    const QString &aStorageName)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QList<SearchCriteria> criteriaList;

    // Require that the profile is not disabled.
    // Profile is enabled by default. Comparing with enabled = true would
    // not work, because the key may not exist at all, even if the profile
    // is enabled.
    SearchCriteria profileEnabled;
    profileEnabled.iType = SearchCriteria::NOT_EQUAL;
    profileEnabled.iKey = KEY_ENABLED;
    profileEnabled.iValue = BOOLEAN_FALSE;
    criteriaList.append(profileEnabled);

    // Profile must not be hidden.
    SearchCriteria profileVisible;
    profileVisible.iType = SearchCriteria::NOT_EQUAL;
    profileVisible.iKey = KEY_HIDDEN;
    profileVisible.iValue = BOOLEAN_TRUE;
    criteriaList.append(profileVisible);

    // Online service.
    SearchCriteria onlineService;
    onlineService.iType = SearchCriteria::EQUAL;
    //onlineService.iSubProfileType = Profile::TYPE_SERVICE;
    // Service profile name is left empty. Key value is matched with all
    // found service sub-profiles, though there should be only one.
    onlineService.iKey = KEY_DESTINATION_TYPE;
    onlineService.iValue = VALUE_ONLINE;
    criteriaList.append(onlineService);

    // The profile should be interested
    // in SOC
    SearchCriteria socSupported;
    //socSupported.iSubProfileType = Profile::TYPE_SERVICE;
    socSupported.iType = SearchCriteria::EQUAL;
    socSupported.iKey = KEY_SOC;
    socSupported.iValue = BOOLEAN_TRUE;
    criteriaList.append(socSupported);

    SearchCriteria storageSupported;
    storageSupported.iSubProfileType = Profile::TYPE_STORAGE;
    storageSupported.iType = SearchCriteria::EQUAL;
    storageSupported.iKey = KEY_LOCAL_URI;
    storageSupported.iValue = aStorageName;
    criteriaList.append(storageSupported);

    return getSyncProfilesByData(criteriaList);
}

QList<SyncProfile *> ProfileManager::getSyncProfilesByStorage(
    const QString &aStorageName, bool aStorageMustBeEnabled)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QList<SearchCriteria> criteriaList;

    // Require that the profile is not disabled.
    // Profile is enabled by default. Comparing with enabled = true would
    // not work, because the key may not exist at all, even if the profile
    // is enabled.
    SearchCriteria profileEnabled;
    profileEnabled.iType = SearchCriteria::NOT_EQUAL;
    profileEnabled.iKey = KEY_ENABLED;
    profileEnabled.iValue = BOOLEAN_FALSE;
    criteriaList.append(profileEnabled);

    // Profile must not be hidden.
    SearchCriteria profileVisible;
    profileVisible.iType = SearchCriteria::NOT_EQUAL;
    profileVisible.iKey = KEY_HIDDEN;
    profileVisible.iValue = BOOLEAN_TRUE;
    criteriaList.append(profileVisible);

    // Online service.
    SearchCriteria onlineService;
    onlineService.iType = SearchCriteria::EQUAL;
    //onlineService.iSubProfileType = Profile::TYPE_SERVICE;
    // Service profile name is left empty. Key value is matched with all
    // found service sub-profiles, though there should be only one.
    onlineService.iKey = KEY_DESTINATION_TYPE;
    onlineService.iValue = VALUE_ONLINE;
    criteriaList.append(onlineService);

    // Storage must be supported.
    SearchCriteria storageSupported;
    storageSupported.iSubProfileName = aStorageName;
    storageSupported.iSubProfileType = Profile::TYPE_STORAGE;

    if (aStorageMustBeEnabled) {
        // Storage must be enabled also. Storages are disabled by default,
        // so we can compare with enabled = true.
        storageSupported.iType = SearchCriteria::EQUAL;
        storageSupported.iKey = KEY_ENABLED;
        storageSupported.iValue = BOOLEAN_TRUE;
    } else {
        // Existence of the storage sub-profile is sufficient.
        storageSupported.iType = SearchCriteria::EXISTS;
    }
    criteriaList.append(storageSupported);

    return getSyncProfilesByData(criteriaList);
}


bool ProfileManagerPrivate::save(const Profile &aProfile)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QDomDocument doc = constructProfileDocument(aProfile);
    if (doc.isNull()) {
        qCWarning(lcButeoCore) << "No profile data to write";
        return false;
    }

    // Create path for the new profile file.
    QDir dir;
    dir.mkpath(iConfigPath + QDir::separator() + aProfile.type());
    QString profilePath(iConfigPath + QDir::separator() + aProfile.type() + QDir::separator()
                        + aProfile.name() + FORMAT_EXT);

    // Create a backup of the existing profile file.
    QString oldProfilePath = findProfileFile(aProfile.type(), aProfile.name());
    QString backupPath = profilePath + BACKUP_EXT;

    if (QFile::exists(oldProfilePath)
        && !createBackup(oldProfilePath, backupPath)) {
        qCWarning(lcButeoCore) << "Failed to create profile backup";
    }

    bool profileWritten = false;

    if (writeProfileFile(profilePath, doc)) {
        QFile::remove(backupPath);
        profileWritten = true;
    } else {
        qCWarning(lcButeoCore) << "Failed to save profile:" << aProfile.name();
    }

    return profileWritten;
}

Profile *ProfileManager::profileFromXml(const QString &aProfileAsXml)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    Profile *profile = nullptr;
    if (!aProfileAsXml.isEmpty()) {
        QDomDocument doc;
        QString error;
        if (doc.setContent(aProfileAsXml, true, &error)) {
            ProfileFactory pf;
            profile = pf.createProfile(doc.documentElement());
        } else {
            qCWarning(lcButeoCore) << "Cannot parse profile: " + error;
        }
    }
    return profile;
}

QString ProfileManager::updateProfile(const Profile &aProfile)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    // Don't save invalid profiles.
    if (aProfile.name().isEmpty() || aProfile.type().isEmpty()) {
        qCWarning(lcButeoCore) << "Malformed profile, missing name or type.";
        return QString();
    }

    // We must have a profile existing before updating it...

    bool exists = d_ptr->profileExists(aProfile.name(), aProfile.type());

    QString profileId("");

    // We need to save before emit the signalProfileChanged, if this is the first
    // update the profile will only exists on disk after the save and any operation
    // using this profile triggered by the signal will fail.
    if (d_ptr->save(aProfile)) {
        profileId = aProfile.name();
    }

    // Profile did not exist, it was a new one. Add it and emit signal with "added" value:
    if (!exists) {
        emit signalProfileChanged(aProfile.name(), ProfileManager::PROFILE_ADDED, aProfile.toString());
    } else {
        emit signalProfileChanged(aProfile.name(), ProfileManager::PROFILE_MODIFIED, aProfile.toString());
    }

    return profileId;
}

SyncProfile *ProfileManager::createTempSyncProfile(const QString &destAddress, bool &saveNewProfile)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    qCDebug(lcButeoCore) << "createTempSyncProfile(" << destAddress << ")";

    if (destAddress.contains("USB")) { //USB - PCSUite no requirement to save profile
        qCInfo(lcButeoCore) << "USB connect - pc";
        SyncProfile *profile = new SyncProfile(PC_SYNC);
        profile->setBoolKey(KEY_HIDDEN, true);
        profile->setKey(KEY_DISPLAY_NAME, PC_SYNC);
        qCDebug(lcButeoCore) << "USB connect does not require a sync profile to be created.";
        return profile;
    }

    saveNewProfile = true;
    BtHelper btHelp(destAddress);
    QString profileDisplayName = btHelp.getDeviceProperties().value("Name").toString();
    if (profileDisplayName.isEmpty()) {
        //Fixes 171340
        profileDisplayName = QString ("qtn_sync_dest_name_device_default");
    }

    qCInfo(lcButeoCore) << "Profile Name :" << profileDisplayName;
    SyncProfile *tProfile = syncProfile(BT_PROFILE_TEMPLATE);
    tProfile->setKey(KEY_DISPLAY_NAME, profileDisplayName);

    QStringList keys;
    keys << destAddress << tProfile->name();
    tProfile->setName(keys);
    tProfile->setEnabled(true);
    tProfile->setBoolKey("hidden", false);
    QStringList subprofileNames = tProfile->subProfileNames();

    Q_FOREACH (const QString &spn, subprofileNames) {
        if (spn == QLatin1String("bt")) {
            // this is the bluetooth profile.  Set some Bluetooth-specific keys here.
            Profile *btSubprofile = tProfile->subProfile(spn);
            btSubprofile->setKey(KEY_BT_ADDRESS, destAddress);
            btSubprofile->setKey(KEY_BT_NAME, profileDisplayName);
            btSubprofile->setEnabled(true);
        }
    }

    return tProfile;
}

void ProfileManager::enableStorages(Profile &aProfile,
                                    QMap<QString, bool> &aStorageMap,
                                    bool *aModified)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QMapIterator<QString, bool> i(aStorageMap);
    qCInfo(lcButeoCore) << "ProfileManager::enableStorages";
    while (i.hasNext()) {
        i.next();
        Profile *profile = aProfile.subProfile(i.key(), Profile::TYPE_STORAGE);
        if (profile) {
            if (profile->isEnabled() != i.value()) {
                profile->setEnabled(i.value());
                if (aModified) {
                    *aModified = true;
                }
            }
        } else {
            qCWarning(lcButeoCore) << "No storage profile by key :" << i.key();
        }
    }
}

void ProfileManager::setStoragesVisible(Profile &aProfile,
                                        QMap<QString, bool> &aStorageMap,
                                        bool *aModified)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QMapIterator<QString, bool> i(aStorageMap);
    qCInfo(lcButeoCore) << "ProfileManager::enableStorages";
    while (i.hasNext()) {
        i.next();
        Profile *profile = aProfile.subProfile(i.key(), Profile::TYPE_STORAGE);

        if (profile) {
            // For setting the "hidden" value to correspond visiblity, invert the value from map.
            if (profile->boolKey(Buteo::KEY_HIDDEN) == i.value()) {
                profile->setBoolKey(Buteo::KEY_HIDDEN, !i.value());
                if (aModified) {
                    *aModified = true;
                }
            }
        } else {
            qCWarning(lcButeoCore) << "No storage profile by key :" << i.key();
        }
    }
}

bool ProfileManager::removeProfile(const QString &aProfileId)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    bool success = false;

    SyncProfile *profile = syncProfile(aProfileId);
    if (profile) {
        success = d_ptr->remove(aProfileId, profile->type());
        if (success) {
            emit signalProfileChanged(aProfileId, ProfileManager::PROFILE_REMOVED, QString(""));
        }
        delete profile;
        profile = nullptr;
    }
    return success;
}

bool ProfileManagerPrivate::remove(const QString &aName, const QString &aType)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    bool success = false;
    QString filePath = iConfigPath + QDir::separator() + aType + QDir::separator() + aName + FORMAT_EXT;

    // Try to load profile without expanding it. We need to check from the
    // profile data if the profile is protected before removing it.
    Profile *p = load(aName, aType);
    if (p) {
        if (!p->isProtected()) {
            success = QFile::remove(filePath);
            if (success) {
                QString logFilePath = iConfigPath + QDir::separator() + aType + QDir::separator()
                                      + LOG_DIRECTORY + QDir::separator() + aName + LOG_EXT + FORMAT_EXT;
                //Initial the will be no log this will fail.
                QFile::remove(logFilePath);
            }
        } else {
            qCDebug(lcButeoCore) << "Cannot remove protected profile:" << aName;
        }
        delete p;
        p = nullptr;
    } else {
        qCDebug(lcButeoCore) << "Profile not found from the config path, cannot remove:" << aName;
    }

    return success;
}

void ProfileManager::expand(Profile &aProfile)
{

    if (aProfile.isLoaded())
        return; // Already expanded.

    // Load and merge sub-profiles.
    int prevSubCount = 0;
    QList<Profile *> subProfiles = aProfile.allSubProfiles();
    int subCount = subProfiles.size();

    while (subCount > prevSubCount) {
        foreach (Profile *sub, subProfiles) {
            if (!sub->isLoaded()) {
                Profile *loadedProfile = profile(sub->name(), sub->type());
                if (loadedProfile != nullptr) {
                    aProfile.merge(*loadedProfile);
                    delete loadedProfile;
                    loadedProfile = nullptr;
                } else {
                    // No separate profile file for the sub-profile.
                    qCDebug(lcButeoCore) << "Referenced sub-profile not found:" << sub->name();
                    qCDebug(lcButeoCore) << "Referenced from:" << aProfile.name() << aProfile.type();
                }
                sub->setLoaded(true);
            }
        }

        // Load/merge may have created new sub-profile entries. Those need
        // to be loaded also. Loop if sub-profile count has changed.
        prevSubCount = subCount;
        subProfiles = aProfile.allSubProfiles();
        subCount = subProfiles.size();
    }

    aProfile.setLoaded(true);
}

bool ProfileManager::saveLog(const SyncLog &aLog)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    QString fullPath = d_ptr->iConfigPath + QDir::separator() + Profile::TYPE_SYNC + QDir::separator()
                       + LOG_DIRECTORY;
    QDir dir;
    dir.mkpath(fullPath);
    QFile file(fullPath + QDir::separator() + aLog.profileName() + LOG_EXT + FORMAT_EXT);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCWarning(lcButeoCore) << "Failed to open sync log file for writing:"
                               << file.fileName();
        return false;
    }

    QDomDocument doc;
    QDomProcessingInstruction xmlHeading
        = doc.createProcessingInstruction("xml",
                                          "version=\"1.0\" encoding=\"UTF-8\"");
    doc.appendChild(xmlHeading);

    QDomElement root = aLog.toXml(doc);
    if (root.isNull()) {
        qCWarning(lcButeoCore) << "Failed to convert sync log to XML";
        return false;
    }

    doc.appendChild(root);

    QTextStream outputStream(&file);

    outputStream << doc.toString(PROFILE_INDENT);

    file.close();

    return true;
}

void ProfileManager::saveRemoteTargetId(Profile &aProfile, const QString &aTargetId)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    qCDebug(lcButeoCore) << "saveRemoteTargetId :" << aTargetId;
    aProfile.setKey (KEY_REMOTE_ID, aTargetId);
    updateProfile(aProfile);
    //addProfile(aProfile);
}

bool ProfileManager::rename(const QString &aName, const QString &aNewName)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);

    bool ret = false;
    // Rename the sync profile
    QString source = d_ptr->iConfigPath + QDir::separator() +  Profile::TYPE_SYNC + QDir::separator()
                     + aName + FORMAT_EXT;
    QString destination = d_ptr->iConfigPath + QDir::separator() + Profile::TYPE_SYNC + QDir::separator()
                          + aNewName + FORMAT_EXT;
    ret = QFile::rename(source, destination);
    if (true == ret) {
        // Rename the sync log
        QString sourceLog = d_ptr->iConfigPath + QDir::separator() +  Profile::TYPE_SYNC + QDir::separator()
                            + LOG_DIRECTORY + QDir::separator() + aName + LOG_EXT  + FORMAT_EXT;
        QString destinationLog = d_ptr->iConfigPath + QDir::separator() +  Profile::TYPE_SYNC + QDir::separator()
                                 + LOG_DIRECTORY + QDir::separator() + aNewName + LOG_EXT  + FORMAT_EXT;
        ret = QFile::rename(sourceLog, destinationLog);
        if (false == ret) {
            // Roll back the earlier rename
            QFile::rename(destination, source);
        }
    }
    if (false == ret) {
        qCWarning(lcButeoCore) << "Failed to rename profile" << aName;
    }
    return ret;
}

bool ProfileManager::saveSyncResults(QString aProfileName,
                                     const SyncResults &aResults)
{

    FUNCTION_CALL_TRACE(lcButeoTrace);
    bool success = false;

    SyncProfile *profile = syncProfile(aProfileName);
    if (profile) {
        SyncLog *log = profile->log();
        if (log) {
            log->addResults(aResults);
            success = saveLog(*log);

            emit signalProfileChanged(aProfileName, ProfileManager::PROFILE_LOGS_MODIFIED, profile->toString());
        }

        delete profile;
        profile = nullptr;
    }

    return success;
}

bool ProfileManager::setSyncSchedule(QString aProfileId, QString aScheduleAsXml)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    bool status = false;
    SyncProfile *profile = syncProfile(aProfileId);
    if (profile) {
        profile->setSyncType(SyncProfile::SYNC_SCHEDULED);
        QDomDocument doc;
        if (doc.setContent(aScheduleAsXml, true)) {
            SyncSchedule schedule(doc.documentElement());
            profile->setSyncSchedule(schedule);
            updateProfile(*profile);
            status = true;
        }
        delete profile;
        profile = nullptr;
    } else {
        qCWarning(lcButeoCore) << "Invalid Profile Supplied";
    }
    return status;
}

bool ProfileManagerPrivate::parseFile(const QString &aPath, QDomDocument &aDoc)
{
    bool parsingOk = false;

    if (QFile::exists(aPath)) {
        QFile file(aPath);

        if (file.open(QIODevice::ReadOnly)) {
            // Modified by Shipwright for Qt 6.5+: setContent() returns a ParseResult.
            parsingOk = static_cast<bool>(aDoc.setContent(&file));
            file.close();

            if (!parsingOk) {
                qCWarning(lcButeoCore) << "Failed to parse profile XML: " << aPath;
            }
        } else {
            qCWarning(lcButeoCore) << "Failed to open profile file for reading:" << aPath;
        }
    } else {
        qCDebug(lcButeoCore) << "Profile file not found:" << aPath;
    }

    return parsingOk;
}

QDomDocument ProfileManagerPrivate::constructProfileDocument(const Profile &aProfile)
{
    QDomDocument doc;
    QDomElement root = aProfile.toXml(doc);

    if (root.isNull()) {
        qCWarning(lcButeoCore) << "Failed to convert profile to XML";
    } else {
        QDomProcessingInstruction xmlHeading
            = doc.createProcessingInstruction("xml",
                                              "version=\"1.0\" encoding=\"UTF-8\"");

        doc.appendChild(xmlHeading);
        doc.appendChild(root);
    }

    return doc;
}

bool ProfileManagerPrivate::writeProfileFile(const QString &aProfilePath,
                                             const QDomDocument &aDoc)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    qCWarning(lcButeoCore) << "writeProfileFile() called, forcing disk write:" << aProfilePath;

    QFile file(aProfilePath);
    bool profileWritten = false;

    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        QTextStream outputStream(&file);
        outputStream << aDoc.toString(PROFILE_INDENT);
        file.close();
        profileWritten = true;
    } else {
        qCWarning(lcButeoCore) << "Failed to open profile file for writing:" << aProfilePath;
    }

    return profileWritten;
}

void ProfileManagerPrivate::restoreBackupIfFound(const QString &aProfilePath,
                                                 const QString &aBackupPath)
{
    if (QFile::exists(aBackupPath)) {
        qCWarning(lcButeoCore) << "Profile backup file found. The actual profile may be corrupted.";

        QDomDocument doc;
        if (parseFile(aBackupPath, doc)) {
            qCDebug(lcButeoCore) << "Restoring profile from backup";
            QFile::remove(aProfilePath);
            QFile::copy(aBackupPath, aProfilePath);
        } else {
            qCWarning(lcButeoCore) << "Failed to parse backup file";
            qCDebug(lcButeoCore) << "Removing backup file";
            QFile::remove(aBackupPath);
        }
    }
}

bool ProfileManagerPrivate::createBackup(const QString &aProfilePath,
                                         const QString &aBackupPath)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    return QFile::copy(aProfilePath, aBackupPath);
}

QString ProfileManagerPrivate::findProfileFile(const QString &aName, const QString &aType)
{
    QString fileName = aType + QDir::separator() + aName + FORMAT_EXT;
    QString primaryPath = iConfigPath + QDir::separator() + fileName;
    QString secondaryPath = iSystemConfigPath + QDir::separator() + fileName;

    if (QFile::exists(primaryPath)) {
        return primaryPath;
    } else if (!QFile::exists(secondaryPath)) {
        return primaryPath;
    } else {
        return secondaryPath;
    }
}

// this function checks to see if its a new profile or an
// existing profile being modified under $Sync::syncConfigDir/profiles directory.
bool ProfileManagerPrivate::profileExists(const QString &aProfileId, const QString &aType)
{
    QString profileFile = iConfigPath + QDir::separator() + aType + QDir::separator() + aProfileId + FORMAT_EXT;
    qCDebug(lcButeoCore) << "profileFile:" << profileFile;
    return QFile::exists(profileFile);
}

void ProfileManager::addRetriesInfo(const SyncProfile *profile)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    if (profile) {
        if (profile->hasRetries() && !d_ptr->iSyncRetriesInfo.contains(profile->name())) {
            qCDebug(lcButeoCore) << "syncretries : retries info present for profile" << profile->name();
            d_ptr->iSyncRetriesInfo[profile->name()] = profile->retryIntervals();
        }
    }
}

QDateTime ProfileManager::getNextRetryInterval(const SyncProfile *aProfile)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    QDateTime nextRetryInterval;
    if (aProfile && d_ptr->iSyncRetriesInfo.contains(aProfile->name())
        && !d_ptr->iSyncRetriesInfo[aProfile->name()].isEmpty()) {
        quint32 mins = d_ptr->iSyncRetriesInfo[aProfile->name()].takeFirst();
        nextRetryInterval = QDateTime::currentDateTime().addSecs(mins * 60);
        qCDebug(lcButeoCore) << "syncretries : retry for profile" << aProfile->name() << "in" << mins << "minutes";
        qCDebug(lcButeoCore) << "syncretries :" << d_ptr->iSyncRetriesInfo[aProfile->name()].count() << "attempts remain";
    }
    return nextRetryInterval;
}

void ProfileManager::retriesDone(const QString &aProfileName)
{
    FUNCTION_CALL_TRACE(lcButeoTrace);
    if (d_ptr->iSyncRetriesInfo.contains(aProfileName)) {
        d_ptr->iSyncRetriesInfo.remove(aProfileName);
        qCDebug(lcButeoCore) << "syncretries : retry success for" << aProfileName;
    }
}
