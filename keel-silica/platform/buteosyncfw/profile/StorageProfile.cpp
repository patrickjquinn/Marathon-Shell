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

#include "StorageProfile.h"
#include "ProfileEngineDefs.h"

namespace Buteo {
// Private implementation class for StorageProfile. Currently not needed, but
// reserved for future usage.
class StorageProfilePrivate
{
public:
    StorageProfilePrivate();

    StorageProfilePrivate(const StorageProfilePrivate &aSource);
};

}

using namespace Buteo;

StorageProfilePrivate::StorageProfilePrivate()
{
}

StorageProfilePrivate::StorageProfilePrivate(
    const StorageProfilePrivate & /*aSource*/)
{
}

StorageProfile::StorageProfile(const QString &aName)
    : Profile(aName, Profile::TYPE_STORAGE)
    , d_ptr(new StorageProfilePrivate())
{
}

StorageProfile::StorageProfile(const QDomElement &aRoot)
    : Profile(aRoot)
    , d_ptr(new StorageProfilePrivate())
{
}

StorageProfile::StorageProfile(const StorageProfile &aSource)
    : Profile(aSource)
    , d_ptr(new StorageProfilePrivate(*aSource.d_ptr))
{
}

StorageProfile::~StorageProfile()
{
    delete d_ptr;
    d_ptr = nullptr;
}

StorageProfile *StorageProfile::clone() const
{
    return new StorageProfile(*this);
}

bool StorageProfile::isEnabled() const
{
    return boolKey(KEY_ENABLED, false);
}
