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
* \file resources.h
* \brief Declaration of The different resource classes: 
* ResourcePolicy::AudioRecorderResource
* ResourcePolicy::BacklightResource
* ResourcePolicy::LedsResource
* ResourcePolicy::VibraResource
* ResourcePolicy::VideoRecorderResource
* ResourcePolicy::VideoResource
* ResourcePolicy::LockButtonResource
* ResourcePolicy::ScaleButtonResource
* ResourcePolicy::SystemButtonResource
* ResourcePolicy::LensCoverResource
* ResourcePolicy::HeadsetButtonsResource
* ResourcePolicy::RearFlashlightResource
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

#ifndef RESOURCES_H
#define RESOURCES_H

#include <policy/resource.h>
#include <QString>

namespace ResourcePolicy
{

/**
* The AudioRecorderResource class represents the audio recorder device.
*/
class AudioRecorderResource: public Resource
{
public:
    AudioRecorderResource();
    AudioRecorderResource(const AudioRecorderResource &other);

    virtual ~AudioRecorderResource();

    virtual ResourceType type() const;
};

/**
* The BacklightResource is used by applications wanting to control the
* backlight
*/
class BacklightResource: public Resource
{
public:
    BacklightResource();
    BacklightResource(const BacklightResource &other);

    virtual ~BacklightResource();

    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to fiddle with the leds.
*/
class LedsResource: public Resource
{
public:
    LedsResource();
    LedsResource(const LedsResource &other);

    virtual ~LedsResource();

    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to use the vibra.
*/
class VibraResource: public Resource
{
public:
    VibraResource();
    VibraResource(const VibraResource &other);

    virtual ~VibraResource();

    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to record video.
*/
class VideoRecorderResource: public Resource
{
public:
    VideoRecorderResource();
    VideoRecorderResource(const VideoRecorderResource &other);

    virtual ~VideoRecorderResource();

    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to render video with the
* DSP decoder to render the viewfinder.
*/
class VideoResource: public QObject, public Resource
{
	Q_OBJECT
public:
	VideoResource(quint32 pid);

    VideoResource()
        : pid(0)
    {
    }

    VideoResource(const VideoResource &other);
    virtual ~VideoResource();

    /**
      * \return the resource type
      */
    virtual ResourceType type() const;

    quint32 processID() const { return pid; }

    /**
      * Set the process ID of the video resource.
      */
    void setProcessID(quint32 newPID);

signals:
    void videoPropertiesChanged(quint32 pid);

private:
    quint32 pid;
};

/**
* Resource to be used when the application wants to control the system button.
*/
class SystemButtonResource: public Resource
{
public:
    SystemButtonResource();
    SystemButtonResource(const SystemButtonResource &other);

    virtual ~SystemButtonResource();

    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to control the lock button.
*/
class LockButtonResource: public Resource
{
public:
    LockButtonResource();
    LockButtonResource(const LockButtonResource &other);

    virtual ~LockButtonResource();

    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to control
* the volume/scale button.
*/
class ScaleButtonResource: public Resource
{
public:
    ScaleButtonResource();
    ScaleButtonResource(const ScaleButtonResource &other);

    virtual ~ScaleButtonResource();
    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to take still pictures.
*/
class SnapButtonResource: public Resource
{
public:
    SnapButtonResource();
    SnapButtonResource(const SnapButtonResource &other);

    virtual ~SnapButtonResource();

    virtual ResourceType type() const;
};

class LensCoverResource: public Resource
{
public:
    LensCoverResource();
    LensCoverResource(const LensCoverResource &other);

    virtual ~LensCoverResource();

    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to control the
* headset buttons.
*/
class HeadsetButtonsResource: public Resource
{
public:
    HeadsetButtonsResource();
    HeadsetButtonsResource(const HeadsetButtonsResource &other);

    virtual ~HeadsetButtonsResource();

    virtual ResourceType type() const;
};

/**
* Resource to be used when the application wants to control the
* rear flashlight.
*/
class RearFlashlightResource: public Resource
{
public:
    RearFlashlightResource();
    RearFlashlightResource(const RearFlashlightResource &other);
    virtual ~RearFlashlightResource();

    virtual ResourceType type() const;
};

}
#endif
