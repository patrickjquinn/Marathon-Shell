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

#ifndef PROFILEMANAGER_H
#define PROFILEMANAGER_H

#include "SyncProfile.h"
#include "Profile.h"

#include <QObject>
#include <QList>
#include <QHash>

namespace Buteo {

class ProfileManagerPrivate;

/*! \brief
 * ProfileManager is responsible for storing and retrieving the profiles.
 *
 * It also constructs top level profiles by loading and merging all referenced
 * sub-profiles. The ProfileManager hides the actual storage from the user, so
 * that it makes no difference if the profiles are stored to simple XML-files
 * or to a database. Profiles can be queried by name and type.
 */
class ProfileManager: public QObject
{
    Q_OBJECT
public:
    //! Search criteria for finding profiles.
    struct SearchCriteria {
        //! Enum to identify if a member type exists or not
        enum Type {
            //! Sub-profile (and key) exists.
            EXISTS,
            //! Sub-profile (or key) does not exist.
            NOT_EXISTS,
            //! Key value is equal.
            EQUAL,
            //! Key value is not equal.
            NOT_EQUAL
        };

        //! \brief Constructor.
        SearchCriteria();

        //! \brief Copy constructor.
        SearchCriteria(const SearchCriteria &aSource);
        SearchCriteria &operator=(const SearchCriteria &other);

        //! Search criteria type.
        Type iType;

        //! Sub-profile name. If this is empty but profile type is given,
        //! matching is tried with each sub-profile of correct type. If both
        //! profile name and type are empty, mathing is done with keys of the
        //! main profile.
        QString iSubProfileName;

        //! Sub-profile type. If this is empty but profile name is given,
        //! matching is done with the first sub-profile having the correct name
        //! regardless of the type.
        QString iSubProfileType;

        //! Key name. If this is empty, key comparison is not made.
        QString iKey;

        //! Key value. This must be given if criteria type is EQUAL or NOT_EQUAL.
        QString iValue;
    };

    //! \brief  Enum to indicate the change type of the Profile Operation
    enum ProfileChangeType {
        //! a New Profile has been added
        PROFILE_ADDED = 0,
        //! a Existing Profile has been modified
        PROFILE_MODIFIED,
        //! Profile has been Removed
        PROFILE_REMOVED,
        //! Profile log file Modified.
        PROFILE_LOGS_MODIFIED
    };

    /*! \brief Constructor.
     */
    ProfileManager();

    /*! \brief Destructor.
     */
    ~ProfileManager();

    /*! \brief Gets the names of all available profiles with the given type.
     *
     * \param aType Type of the profiles to get.
     * \return The list of profile names.
     */
    QStringList profileNames(const QString &aType);

    /*! \brief Gets a sync profile.
     *
     * Loads and merges also all sub-profiles that are referenced from the
     * main profile. Loads the log of finished synchronization sessions with
     * this profile.
     * \param aName Name of the profile to get.
     * \return The sync profile. NULL if the profile is not found. Caller becomes
     * the owner of the returned object and is responsible of deleting it after
     * use. Changes made to the profile are not saved to the persistent profile
     * storage, unless save function of this class is called.
     */
    SyncProfile *syncProfile(const QString &aName);

    /*! \brief Gets all sync profiles.
     *
     * \return The list of sync profiles. Caller is responsible for deleting
     *  the returned profile objects.
     */
    QList<SyncProfile *> allSyncProfiles();

    /*! \brief Gets all visible sync profiles.
     *
     * Returns all sync profiles that should be visible in sync ui. A profile
     * is visible if it has not been explicitly set as hidden.
     * \return The list of sync profiles. Caller is responsible for deleting
     *  the returned profile objects.
     */
    QList<SyncProfile *> allVisibleSyncProfiles();

    /*! \brief Gets profiles with matching data.
     *
     * \param aSubProfileName Name of a required sub-profile. If this is given,
     *  the sub-profile must exist and key comparison is made with the keys
     *  of the sub-profile.
     * \param aSubProfileType Type of a required sub-profile. If this is given but
     *  sub-profile name is empty, the first sub-profile with matching type is
     *  used in comparison.
     * \param aKey Name of a required key. If this is empty, key comparison is
     *  not made and existance of the sub-profile is enough.
     * \param aValue Value of the required key. If this is empty, any value
     *  is accepted as long as the key itself exists.
     * \return List of matching profiles. Caller is responsible for deleting
     *  the returned profile objects.
     */
    QList<SyncProfile *> getSyncProfilesByData(const QString &aSubProfileName,
                                               const QString &aSubProfileType,
                                               const QString &aKey = "", const QString &aValue = "");

    /*! \brief Gets profiles with matching data.
     *
     * \param aCriteria List of criteria to use in the search. Each criterion
     *  in the list has to match for a profile to be returned as a result.
     * \return List of matching profiles. Caller is responsible for deleting
     *  the returned profile objects.
     */
    QList<SyncProfile *> getSyncProfilesByData(const QList<SearchCriteria> &aCriteria);

    /*! \brief Gets profiles based on supported storages.
     *
     * Returns all enabled and visible sync profiles of online destinations
     * that support the given storage. Device-to-device sync profiles are not
     * returned.
     * \param aStorageName Name of the storage that must be supported.
     * \param aStorageMustBeEnabled True if the supported storage must be
     *  also enabled. Only enabled storages are included in sync session.
     * \return List of matching profiles. Caller is responsible for deleting
     *  the returned profile objects.
     */
    QList<SyncProfile *> getSyncProfilesByStorage(const QString &aStorageName, bool aStorageMustBeEnabled = false);

    /*! \brief Gets profiles interested in sync on change for a storage
     *
     * Returns all enabled and visible sync profiles of online destinations
     * Device-to-device sync profiles are not returned.
     * \param aStorageName Name of the storage
     * \return List of matching profiles. Caller is responsible for deleting
     *  the returned profile objects.
     */
    QList<SyncProfile *> getSOCProfilesForStorage(const QString &aStorageName);

    /*! \brief Expands the given profile.
     *
     * Loads and merges all sub-profiles that are referenced from the main
     * profile.
     * \param aProfile Name of the profile to expand.
     */
    void expand(Profile &aProfile);

    /*! \brief Saves the given synchronization log.
     *
     * \param aLog Log to save.
     * \return True if saving was successful.
     */
    bool saveLog(const SyncLog &aLog);

    /*! \brief Saves the results of a sync session to the log.
     *
     * This is a convenience function that loads the log associated with the
     * given profile, appends the given results to the log and then saves the
     * log.
     * \param aProfileName Name of the profile used in the sync session.
     * \param aResults Results.
     * \return True if saving was successful.
     */
    bool saveSyncResults(QString aProfileName, const SyncResults &aResults);

    /*! \brief Gets a profile.
     *
     * \param aName Name of the profile to get.
     * \param aType Type of the profile to get.
     * \return Pointer to the profile. If the profile is not found, NULL is
     *  returned. Caller is responsible for deleting the returned object.
     *  Changes made to the profile are not saved to profile storage, unless
     *  updateProfile function of this class is called
     */
    Profile *profile(const QString &aName, const QString &aType);

    /*! \brief Gets a temporary profile (saved if sync is sucessfull).
     *
     * \param btAddress  Address of the remote device bt address/usb .
     * \param saveNewProfile If to save the profile or not (e.g pc suite profile)
     * \return Pointer to the profile.
     *  Changes made to the profile are not saved to profile storage, unless
     *  save function of this class is called
     */
    SyncProfile *createTempSyncProfile (const QString &btAddress, bool &saveNewProfile);

    /*! \brief Updates the existing profile with the profile
     * given as parameter and emits profileChanged() Signal with appropriate value
     * depening if profile was newly added (0) or updated (1)
     *
     * NOTE: only Sync Profiles can be updated using ProfileManger
     *
     * \param aProfile  - Profile Object
     * \return profileId - this will be empty if the update Failed.
     */
    QString updateProfile(const Profile &aProfile);

    /*! \brief Deletes a profile from the persistent storage.
     *
     * This will emit a signalProfileChanged with ChangeType
     * as Removed if Removal is successful
     * NOTE: only Sync Profiles can be updated using ProfileManger
     * \param aProfileId Profile to be remove.
     * \return Success indicator.
     */
    bool removeProfile(const QString &aProfileId);

    /*! \brief Renames a profile, and the associated log too
     *
     * \param aName The old name of the profile
     * \param aNewName The new name for the profile
     * \return Returns true if the rename was successful
     */
    bool rename(const QString &aName, const QString &aNewName);

    /*! \brief Enables sync'd storages in profile
     *
     * \param aProfile Profile of the remote device
     * \param aStorageMap Map of storage names(hcalendar, hcontacts) and if sync
     * enabled value true/false
     * \param aModified Whether the profile was updated as a result of this function call,
     * and thus requires writing to disk
     */
    void enableStorages (Profile &aProfile, QMap<QString, bool> &aStorageMap, bool *aModified = nullptr);

    /*! \brief Sets storage subprofiles hidden status for the given profile
    *
    * \param aProfile Profile of the remote device
    * \param aStorageMap Map of storage names (hcalendar, hcontacts) and visibility status. With value \e true
    * the storage will be set visible (equals profile attribute hidden=false)
    * \param aModified Whether the profile was updated as a result of this function call,
    * and thus requires writing to disk
    */
    void setStoragesVisible(Profile &aProfile, QMap<QString, bool> &aStorageMap, bool *aModified = nullptr);

    /*! \brief Sets remote target in profile
     *
     * \param aProfile Profile of the remote device
     * \param aId remote device id
     *
     */
    void saveRemoteTargetId (Profile &aProfile, const QString &aId);

    /*! \brief Sets/Overwrites the schedule to a profile
     *
     * \param aProfileId Profile Id
     * \param aScheduleAsXml SyncSchedule Object as an xml string
     *
     */
    bool setSyncSchedule(QString aProfileId, QString aScheduleAsXml);

    /*! \brief checks if a profile has retries info and stores the same
     *
     * @param aProfile sync profile
     */
    void addRetriesInfo(const SyncProfile *aProfile);

    /*! \brief gets the next retry after time for a sync profile
     *
     * @param aProfile sync profile
     * @return next retry interval
     */
    QDateTime getNextRetryInterval(const SyncProfile *aProfile);

    /*! \brief call this to indicate that retries have to stop for a certain
     * sync for a profile - either the no. of retry attempts exhausted or one of the retries succeeded
     *
     * @param aProfileName name of the profile
     */
    void retriesDone(const QString &aProfileName);

#ifdef SYNCFW_UNIT_TESTS
    friend class ProfileManagerTest;
#endif
    // for testing purposes only
    // configPath is the root of primary profile directory, used for writing changes
    // systemConfigPath is for read-only system profiles
    void setPaths(const QString &configPath, const QString &systemConfigPath);

    /*! \brief Gets a profile object from an xml document.
     *
     * \param aProfileAsXml Name of the profile to get.
     * \return Pointer to the profile. If the xml is not valid, NULL is
     *  returned. Caller is responsible for deleting the returned object.
     *  Changes made to the profile are not saved to profile storage, unless
     *  updateProfile function of this class is called
     */
    static Profile *profileFromXml(const QString &aProfileAsXml);

signals:
    /*! \brief Notifies about a change in profile.
    *
    * This signal is sent when the profile data is modified or when a profile
    * is added or deleted in msyncd.
    * \param aProfileName Name of the changed profile.
    * \param aChangeType \see ProfileManager::ProfileChangeType
    * \param aProfileAsXml Updated Profile Object is sent as xml
    */
    void signalProfileChanged(QString aProfileName, int aChangeType, QString aProfileAsXml);

private:
    ProfileManager &operator=(const ProfileManager &aRhs);
    ProfileManagerPrivate *d_ptr;
};

}

#endif // PROFILEMANAGER_H
