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
/**
* \file resource.h
* \brief Declaration of ResourcePolicy::Resource and
* ResourcePolicy::ResourceType
*
* \copyright Copyright (C) 2011 Nokia Corporation.
* \author Wolf Bergenheim and Robert Löfman
* \par License
* @license LGPL
* This file is part of libresourceqt
* \par
* Copyright (C) 2011 Nokia Corporation.
* \par
* This library is free software; you can redistribute
* it and/or modify it under the terms of the GNU Lesser General Public
* License as published by the Free Software Foundation
* version 2.1 of the License.
* \par
* This library is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
* Lesser General Public License for more details.
* \par
* You should have received a copy of the GNU Lesser General Public
* License along with this library; if not, write to the Free Software
* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301
* USA.
*/

#ifndef RESOURCE_H
#define RESOURCE_H

#include <QtCore>

namespace ResourcePolicy
{
/**
* This enumeration represents the resources which can be reserved.
* \see ResourcePolicy::ResourceSet for info on how to reserve resources.
*/

enum ResourceType {
	AudioPlaybackType = 0,		///< For audio playback
	VideoPlaybackType,		///< For video playback
	AudioRecorderType,		///< For audio recording (using of the microphone)
	VideoRecorderType,		///< For video recording (using the camera)
	VibraType,			///< For Vibra
	LedsType,			///< For LEDs
	BacklightType,			///< For the backlight (of the display)
	SystemButtonType,		///< For the system (power) button
	LockButtonType,			///< For the lock button
	ScaleButtonType,		///< The scale (zoom) button
	SnapButtonType,			///< Use this if you are a camera application
	LensCoverType,
	HeadsetButtonsType,		///< Use this to reserve the headset buttons
	RearFlashlightType,		///< Use this for reserving the rear flashlight
	NumberOfTypes
};

class ResourceSet;
/**
* This class is the parent class for all resources. It represents a generic
* \ref Resource. The type specific resource classes should be used.
*/

class Resource
{
    friend class ResourceSet;
public:
    /**
      * Whether or not this resource is optional, in that it does not need to
      * be available for the set to be acquired.
      * \return true when this resource is optional
      */
    bool isOptional() const;

    /**
      * Sets the resource to be optional or mandatory.
      * \param resourceIsOptional This optional parameter is true by default.
      * The default, true, results in the resource becoming optional. When it
      * is set to false the resource becomes mandatory.
      */
    void setOptional(bool resourceIsOptional = true);

    /**
      * Whether or not the resource to be shared. If it is shared then other
      * programs are allowed to share this resource.
      * \return true when this resource is shared
      */
    bool isGranted() const;

    /**
      * Checks the type of Resource
      * \return The ResourceType associated to this resource
      */
    virtual ResourceType type() const = 0;

    virtual ~Resource();

protected:
    Resource();
    Resource(const Resource &other);

    /**
      * \internal
      * This holds the type of the resource.
      */
    ResourceType resourceType;

    /**
      * \internal
      * This is true when this resource is optional.
      * \sa isOptional
      * \sa setOptional
      */
    bool optional;

    /**
      * \internal
      * This is just a unique identifier for the resource.
      */
    quint32 identifier;

private:
    void setGranted();
    void unsetGranted();

    bool granted;
};
}

#endif
