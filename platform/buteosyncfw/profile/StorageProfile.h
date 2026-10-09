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
#ifndef STORAGEPROFILE_H
#define STORAGEPROFILE_H

#include "Profile.h"

namespace Buteo {

class StorageProfilePrivate;

/*! \brief Storage Profile Class */
class StorageProfile : public Profile
{
public:
    /*! \brief Constructs an empty StorageProfile with the given name.
     *
     * \param aName Name of the profile to create.
     */
    explicit StorageProfile(const QString &aName);

    /*! \brief Constructs a profile from the given XML.
     *
     * \param aRoot Root element of the XML node tree.
     */
    explicit StorageProfile(const QDomElement &aRoot);

    /*! \brief Copy constructor.
     *
     * \param aSource Copy source.
     */
    StorageProfile(const StorageProfile &aSource);

    /*! \brief Destructor.
     */
    ~StorageProfile();

    /*! \brief Creates a clone of the profile.
     *
     * \return The clone.
     */
    virtual StorageProfile *clone() const;

    /*! \brief Returns if the profile is enabled.
     *
     * Storage profile is disabled by default. This means that if there is no
     * key for the enabled status, the profile will be disabled.
     * \return Is the profile enabled.
     */
    virtual bool isEnabled() const;

private:
    StorageProfile &operator=(const StorageProfile &aRhs);

    StorageProfilePrivate *d_ptr;
};

}

#endif // STORAGEPROFILE_H
