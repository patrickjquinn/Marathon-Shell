// SPDX-FileCopyrightText: 2011 Nokia Corporation
// SPDX-License-Identifier: LGPL-2.1-only
/*************************************************************************
This file is part of libresourceqt

Copyright (C) 2011 Nokia Corporation.

This library is free software; you can redistribute
it and/or modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation
version 2.1 of the License.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301
USA.
*************************************************************************/

#include <policy/resource.h>

using namespace ResourcePolicy;

Resource::Resource()
    : optional(false),
      identifier(0), granted(false)
{
}

Resource::Resource(const Resource &other)
    : optional(other.optional),
      identifier(other.identifier), granted(other.granted)
{
}

Resource::~Resource()
{
}

bool Resource::isOptional() const
{
    return optional;
}

void Resource::setOptional(bool resourceIsOptional)
{
    optional = resourceIsOptional;
}

bool Resource::isGranted() const
{
    return granted;
}

void Resource::setGranted()
{
    granted = true;
}

void Resource::unsetGranted()
{
    granted = false;
}
