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

#ifndef PROFILE_H
#define PROFILE_H

#include <QList>
#include <QMap>
#include <QString>
#include <QStringList>
#include "ProfileField.h"

class QDomDocument;
class QDomElement;

namespace Buteo {

class ProfileTest;
class ProfilePrivate;


/*! \brief This class represents a single profile, a collection of settings or
 *  data releated to some entity.
 *
 * A profile can contain keys, fields and other profiles as sub-profiles.
 * Functions for accessing all these in different ways are provided. A profile
 * object can be created from XML and exported to XML, but otherwise the class
 * interface does not use XML. New classes can be derived from this class for
 * different profile types to add helper functions for accessing specific keys
 * and fields known by the profile type.
 */
class Profile
{
public:
    //! String constants for different profile type names.
    static const QString TYPE_CLIENT;
    //! Server type .
    static const QString TYPE_SERVER;
    //! Storage type
    static const QString TYPE_STORAGE;
    //! Service type
    //static const QString TYPE_SERVICE;
    //! Sync type
    static const QString TYPE_SYNC;

    /*! \brief Default Constructor
     *
     */
    Profile();

    /*! \brief Constructs a Profile object with given name and type.
     *
     * \param aName Profile name.
     * \param aType Profile type. Prefer using predefined constants like
     *  TYPE_SYNC.
     */
    Profile(const QString &aName, const QString &aType);

    /*! \brief Constructs a Profile object from XML.
     *
     * \param aRoot Root element of the profile XML.
     */
    explicit Profile(const QDomElement &aRoot);

    /*! \brief Copy constructor.
     *
     * \param aSource Copy source.
     */
    Profile(const Profile &aSource);

    /*! \brief Creates a clone of the profile.
     *
     * \return The clone.
     */
    virtual Profile *clone() const;

    //! \brief Destructor.
    virtual ~Profile();

    /*! \brief Gets the name of the profile.
     *
     * \return Profile name.
     */
    QString name() const;

    /*! \brief Gets the display name of the profile.
     *
     * \return Profile display name.
     */
    QString displayname() const;

    /*! \brief Sets the name of the profile.
     *
     * \param aName Name of the profile.
     */
    virtual void setName(const QString &aName);

    /*! \brief Sets the name of the profile.
     *
     * \param aKeys Keys required to generate the profile name.
     */
    virtual void setName(const QStringList &aKeys);

    /*! \brief Gets the type of the profile.
     *
     * \return Profile type.
     */
    QString type() const;

    /*! \brief Creates a XML representation of the profile.
     *
     * \param aDoc Parent document for the created XML elements. The elements
     *  are not inserted to the document by this function, but the document is
     *  required to create the elements.
     * \param aLocalOnly Should only local profile elements be present in the
     *  generated XML. If this is true, elements merged from sub-profiles are
     *  not included.
     * \return Generated XML node tree.
     */
    virtual QDomElement toXml(QDomDocument &aDoc, bool aLocalOnly = true) const;

    /*! \brief Outputs a XML representation of the profile to a string.
     *
     * Merged sub-profile data is also included in the output string.
     * \return Generated XML string.
     */
    QString toString() const;

    /*! \brief Gets the value of the given key.
     *
     * \param aName Name of the key to read.
     * \param aDefault Default value.
     * \return Value of the key. If the key was not found, the default is
     *  returned. If there are multiple instances of the key with the given
     *  name, the value of the first instance is returned.
     */
    QString key(const QString &aName, const QString &aDefault = QString()) const;

    /*! \brief Gets all keys and their values.
     *
     * \return Map of key names/values.
     */
    QMultiMap<QString, QString> allKeys() const; // Modified by Shipwright for Qt 6: QMultiMap

    /*! \brief Gets all keys that are not related to storages.
     *
     * \return Map of key names/values.
     */
    QMultiMap<QString, QString> allNonStorageKeys() const; // Modified by Shipwright for Qt 6: QMultiMap

    /*! \brief Gets the value of the given boolean key.
     *
     * Returns true if the key exists and its value equals "true". If
     * the key does not exist, the default value is returned.
     * \param aName Name of the key to read.
     * \param aDefault Value to return if the key does not exist.
     * \return The boolean value of the key.
     */
    bool boolKey(const QString &aName, bool aDefault = false) const;

    /*! \brief Gets the values of all keys with the given name.
     *
     * If the key does not exist at all, an empty list is returned.
     * \param aName Name of the key to read.
     * \return List of values associated with the key.
     */
    QStringList keyValues(const QString &aName) const;

    /*! \brief Gets the names of all keys.
     *
     * \return List of key names.
     */
    QStringList keyNames() const;

    /*! \brief Sets the value of a key.
     *
     * If the key does not exist yet, it is created.
     * \param aName Name of the key.
     * \param aValue Value of the key.
     */
    void setKey(const QString &aName, const QString &aValue);

    /*! \brief Sets multiple values for a key.
     *
     * All previous (local) values of the key are removed. A key entry for
     * each of the provided values is then created.
     * \param aName Name of the key.
     * \param aValues Values for the key.
     */
    void setKeyValues(const QString &aName, const QStringList &aValues);

    /*! \brief Sets the value of a boolean key.
     *
     * The key value is set to "true" of "false". If the key does not exist
     * yet, it is created.
     * \param aName Name of the key.
     * \param aValue Value of the key.
     */
    void setBoolKey(const QString &aName, bool aValue);

    /*! \brief Removes a key from profile. All instances of the key are removed.
     *
     * \param aName Name of the key to remove.
     */
    void removeKey(const QString &aName);

    /*! \brief Gets the field with the given name.
     *
     * If the field does not exist, NULL is returned.
     * To get/set the value associated with the field, use the key handling
     * functions with the name of the field.
     * \param aName Name of the field.
     * \return Pointer to the field.
     */
    const ProfileField *field(const QString &aName) const;

    /*! \brief Gets all fields.
     *
     * \return List of pointers to the fields.
     */
    QList<const ProfileField *> allFields() const;

    /*! \brief Gets all visible fields of the profile.
     *
     * Each field can define its visibility. This functions returns only
     * fields that are visible.
     * \return List of pointers to the visible fields.
     */
    QList<const ProfileField *> visibleFields() const;

    /*! \brief Checks if the profile is valid.
     *
     * A profile is valid if:
     * 1. Name and type are set (not empty).
     * 2. For each field there is a key with the same name, and the key value
     *  (or all values, if multiple keys with the same name exist) is valid for
     *  the field.
     * 3. All sub-profiles are valid according to these three rules.
     * \return Is the profile valid.
     */
    bool isValid() const;

    /*! \brief Gets the names of all sub-profiles with the given type.
     *
     * \param aType Type of sub-profiles to get. If this is empty, all
     *  sub-profile names are returned.
     * \return Names of the sub-profiles.
     */
    QStringList subProfileNames(const QString &aType = "") const;

    /*! \brief Gets a sub-profile with the given name and type.
     *
     * \param aName Name of the sub-profile to get.
     * \param aType Type of the sub-profile to get. If the type is empty,
     *  any type is accepted.
     * \return The first sub-profile that matches the criteria. NULL if no such
     *  sub-profile was found. The returned sub-profile is owned by the main
     *  profile and the user must not delete it.
     */
    Profile *subProfile(const QString &aName, const QString &aType = "");

    /*! \brief const method for subProfile \see Profile::subProfile
     *
     */
    const Profile *subProfile(const QString &aName, const QString &aType = "") const;

    /*! \brief Gets a sub-profile by key value.
     *
     * Returns the first sub-profile that has a key with the given value.
     * \param aKey Name of the key.
     * \param aValue Required value of the key.
     * \param aType Type of the sub-profile. If empty, any type can match.
     * \param aEnabledOnly Should only enabled sub-profiles be compared.
     * \return First matching sub-profile, NULL if no match.
     */
    const Profile *subProfileByKeyValue(const QString &aKey,
                                        const QString &aValue,
                                        const QString &aType,
                                        bool aEnabledOnly) const;

    /*! \brief Gets all sub-profiles.
     *
     * \return List of sub-profiles. The returned sub-profiles are owned by the main
     *  profile and the user must not delete them.
     */
    QList<Profile *> allSubProfiles();

    /*! \brief Gets all sub-profiles as const
     *
     * \return List of sub-profiles. The returned sub-profiles are const and are owned by the main
     *  profile and the user must not delete them.
     */
    QList<const Profile *> allSubProfiles() const;

    /*! \brief Merges a profile to this profile.
     *
     * The source profile and all its sub-profiles are merged as direct
     * sub-profiles of this profile. This function is mainly used by the
     * ProfileManager, when it constructs a single profile from multiple
     * sub-profile files.
     * \param aSource Profile to merge.
     */
    void merge(const Profile &aSource);

    /*! \brief Checks if the profile is fully constructed by loading all
     * sub-profiles from separate profile files.
     *
     * A profile can have sub-profiles defined directly inside it, but
     * typically the sub-profiles are made complete by checking if there is
     * a separate profile file with the same name and type, and then loading
     * and merging the keys and fields defined in these files to the ones
     * defined directly in the main profile.
     * \return Is the profile fully loaded.
     */
    bool isLoaded() const;

    /*! \brief Sets if the profile is fully loaded.
     *
     * This function is used by the ProfileManager. The purpose of this flag
     * is to avoid loading the same sub-profile multiple times, if there are
     * more than one references to it in the sub-profile tree.
     * \param aLoaded Is the profile loaded.
     */
    void setLoaded(bool aLoaded);

    /*! \brief Returns if the profile is enabled.
     *
     * \return Is the profile enabled.
     */
    virtual bool isEnabled() const;

    /*! \brief Set is the profile is enabled.
     *
     * \param aEnabled New enabled status.
     */
    void setEnabled(bool aEnabled);

    /*! \brief Checks if the profile is hidden.
     *
     * A hidden profile should not be visible in sync ui.
     * \return True if hidden.
     */
    bool isHidden() const;

    /*! \brief Checks if the profile is protected.
     *
     * A protected profile can not be removed using the ProfileManager.
     * \return True if protected.
     */
    bool isProtected() const;

private:
    Profile &operator=(const Profile &aRhs);
    ProfilePrivate *d_ptr;

    /*! \brief Generates a profile id based on keys
     *
     * \param aKeys List of keys to generate profile id
     * \returns Profile name
     *
     */
    QString generateProfileId(const QStringList &aKeys);

#ifdef SYNCFW_UNIT_TESTS
    friend class ProfileTest;
#endif
};

}

#endif // PROFILE_H
