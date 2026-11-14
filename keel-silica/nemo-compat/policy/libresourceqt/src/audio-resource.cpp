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

#include <policy/audio-resource.h>

using namespace ResourcePolicy;

class AudioResourcePrivate
{
public:
    AudioResourcePrivate(const QString &audioGroup)
        : group(audioGroup)
        , pid(0)
    {
    }

    AudioResourcePrivate(const AudioResourcePrivate &other)
        : group(other.group)
        , pid(other.pid)
        , streamName(other.streamName)
        , streamValue(other.streamValue)
    {
    }

    QString group;
    quint32 pid;
    QString streamName;
    QString streamValue;
};

AudioResource::AudioResource(const QString &audioGroup)
    : QObject()
    , Resource()
    , d(new AudioResourcePrivate(audioGroup))
{
}

AudioResource::AudioResource(const AudioResource &other)
    : QObject()
    , Resource(other)
    , d(new AudioResourcePrivate(*other.d))
{
}

AudioResource::~AudioResource()
{
    delete d;
}

QString AudioResource::audioGroup() const
{
    return d->group;
}

bool AudioResource::audioGroupIsSet() const
{
    if (d->group.isEmpty() || d->group.isNull()) {
        return false;
    }
    return true;
}

void AudioResource::setAudioGroup(const QString &newGroup)
{
    d->group = newGroup;
    emit audioPropertiesChanged(d->group, d->pid, d->streamName, d->streamValue);
}

quint32 AudioResource::processID() const
{
    return d->pid;
}

void AudioResource::setProcessID(quint32 newPID)
{
    d->pid = newPID;
    emit audioPropertiesChanged(d->group, d->pid, d->streamName, d->streamValue);
}

QString AudioResource::streamTagName() const
{
    return d->streamName;
}

QString AudioResource::streamTagValue() const
{
    return d->streamValue;
}

bool AudioResource::streamTagIsSet() const
{
    if (d->streamName.isEmpty() || d->streamName.isNull()
        || d->streamValue.isEmpty() || d->streamValue.isNull()) {
        return false;
    }
    return true;
}

void AudioResource::setStreamTag(const QString &name, const QString &value)
{
    d->streamName = name;
    d->streamValue = value;
    emit audioPropertiesChanged(d->group, d->pid, name, value);
}

ResourceType AudioResource::type() const
{
    return AudioPlaybackType;
}
