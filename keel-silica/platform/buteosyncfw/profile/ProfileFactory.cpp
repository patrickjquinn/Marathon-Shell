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

#include "ProfileFactory.h"
#include "SyncProfile.h"
#include "StorageProfile.h"
#include "ProfileEngineDefs.h"

#include <QDomDocument>

using namespace Buteo;

ProfileFactory::ProfileFactory()
{
}

Profile *ProfileFactory::createProfile(const QString &aName,
                                       const QString &aType)
{
    if (aType.isEmpty())
        return nullptr;

    Profile *p = nullptr;

    if (aType == Profile::TYPE_SYNC) {
        p = new SyncProfile(aName);
    } else if (aType == Profile::TYPE_STORAGE) {
        p = new StorageProfile(aName);
    }
    // Entries for each class derived from Profile can be added here.
    else {
        p = new Profile(aName, aType);
    }

    return p;
}

Profile *ProfileFactory::createProfile(const QDomElement &aRoot)
{
    Profile *p = nullptr;

    QString type = aRoot.attribute(ATTR_TYPE);
    if (type == Profile::TYPE_SYNC) {
        p = new SyncProfile(aRoot);
    } else if (type == Profile::TYPE_STORAGE) {
        p = new StorageProfile(aRoot);
    }
    // Entries for each class derived from Profile can be added here.
    else {
        p = new Profile(aRoot);
    }

    return p;
}
