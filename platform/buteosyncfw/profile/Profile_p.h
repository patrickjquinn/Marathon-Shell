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
#ifndef PROFILE_P_H
#define PROFILE_P_H

#include <QList>
#include <QMap>
#include <QString>
#include "ProfileField.h"

namespace Buteo {

//! Private implementation class for Profile class.
class ProfilePrivate
{
public:
    //! \brief Constructor
    ProfilePrivate();

    //! \brief Copy Constructor
    ProfilePrivate(const ProfilePrivate &aSource);

    //! \brief Destructor
    ~ProfilePrivate();

    //! Profile name.
    QString iName;

    //! Profile type.
    QString iType;

    //! Is the profile fully loaded and constructed.
    bool iLoaded;

    //! Is the profile merged created by merging from sub-profile.
    bool iMerged;

    //! Local keys, that are not merged from sub-profiles.
    // Modified by Shipwright for Qt 6: QMultiMap (Qt 5's QMap held several values per key).
    QMultiMap<QString, QString> iLocalKeys;

    //! Keys that are merged from sub-profile files.
    QMultiMap<QString, QString> iMergedKeys; // Modified by Shipwright for Qt 6

    //! Local fields, that are not merged from sub-profiles.
    QList<const ProfileField *> iLocalFields;

    //! Fields that are merged from sub-profiles.
    QList<const ProfileField *> iMergedFields;

    //! List of sub-profiles.
    QList<Profile *> iSubProfiles;
};
}


Buteo::ProfilePrivate::ProfilePrivate()
    : iLoaded(false)
    , iMerged(false)
{
}

Buteo::ProfilePrivate::ProfilePrivate(const ProfilePrivate &aSource)
    : iName(aSource.iName)
    , iType(aSource.iType)
    , iLoaded(aSource.iLoaded)
    , iMerged(aSource.iMerged)
    , iLocalKeys(aSource.iLocalKeys)
    , iMergedKeys(aSource.iMergedKeys)
{
    foreach (const ProfileField *localField, aSource.iLocalFields) {
        iLocalFields.append(new ProfileField(*localField));
    }
    foreach (const ProfileField *mergedField, aSource.iMergedFields) {
        iMergedFields.append(new ProfileField(*mergedField));
    }

    foreach (Profile *p, aSource.iSubProfiles) {
        iSubProfiles.append(p->clone());
    }
}

Buteo::ProfilePrivate::~ProfilePrivate()
{
    qDeleteAll(iLocalFields);
    iLocalFields.clear();
    qDeleteAll(iMergedFields);
    iMergedFields.clear();

    qDeleteAll(iSubProfiles);
    iSubProfiles.clear();
}

#endif // PROFILE_P_H
