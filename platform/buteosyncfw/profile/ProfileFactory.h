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
#ifndef PROFILEFACTORY_H
#define PROFILEFACTORY_H

#include "Profile.h"

namespace Buteo {

/*! \brief ProfileFactory handles creating Profile instances.
 *
 * ProfileFactory knows all the classed derived from the Profile class and
 * creates an instance of a correct class based on the profile type given as a
 * parameter for the create function. By using the ProfileFactory it is
 * possible to create profiles from a component that is not aware of the
 * different derived profile classes, especially from the Profile class itself.
 */
class ProfileFactory
{
public:
    //! \brief Constructor.
    ProfileFactory();

    /*! \brief Creates an empty profile with the given name and type.
     *
     * An instance of the correct class derived from Profile is created based
     * on the given profile type. If the type is not recognizer as a specific
     * derived class, an instance of the Profile base class is created.
     * \param aName Name of the profile.
     * \param aType Type of the profile.
     * \return The created profile.
     */
    Profile *createProfile(const QString &aName, const QString &aType);

    /*! \brief Creates a profile from XML.
     *
     * An instance of the correct class derived from Profile is created based
     * on the profile type read from XML. If the type is not recognizer as a
     * specific derived class, an instance of the Profile base class is
     * created.
     * \param aRoot Root element of the profile XML.
     * \return Created profile.
     */
    Profile *createProfile(const QDomElement &aRoot);
};

}

#endif // PROFILEFACTORY_H
