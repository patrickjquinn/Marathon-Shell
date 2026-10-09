// SPDX-FileCopyrightText: 2013 Jolla Mobile <andrew.den.exter@jollamobile.com>
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2013 Jolla Mobile <andrew.den.exter@jollamobile.com>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#include "resource.h"
#include "permissions.h"

#include <policy/resources.h>
#include <policy/audio-resource.h>

Resource::Resource(QObject *parent)
    : QObject(parent)
    , m_permissions(0)
    , m_resource(0) // Modified by Shipwright: was left uninitialised; read by updateAcquired().
    , m_type(AudioPlayback)
    , m_optional(false)
    , m_required(true)
    , m_acquired(false)
{
}

Resource::Type Resource::type() const
{
    return m_type;
}

void Resource::setType(Resource::Type type)
{
    if (!m_permissions && m_type != type) {
        m_type = type;
        emit typeChanged();
    }
}

bool Resource::isOptional() const
{
    return m_optional;
}

void Resource::setOptional(bool optional)
{
    if (m_optional != optional) {
        m_optional = optional;
        emit optionalChanged();
    }
}

bool Resource::isRequired() const
{
    return m_required;
}

void Resource::setRequired(bool required)
{
    if (m_required != required) {
        m_required = required;
        if (m_permissions)
            m_permissions->resourceRequiredChanged(this);
        emit requiredChanged();
    }
}

bool Resource::isAcquired() const
{
    return m_acquired;
}

void Resource::updateAcquired()
{
    bool acquired = m_resource && m_resource->isGranted();
    if (m_acquired != acquired) {
        m_acquired = acquired;
        emit acquiredChanged();
    }
}

void Resource::clearAcquired()
{
    if (m_acquired) {
        m_acquired = false;
        emit acquiredChanged();
    }
}

void Resource::addResource(ResourcePolicy::ResourceSet *resourceSet)
{
    m_resource = createResource();
    if (m_resource) {
        m_resource->setOptional(m_optional);
        resourceSet->addResourceObject(m_resource);
    }
}

void Resource::clearResource()
{
    m_resource = 0;
    if (m_acquired) {
        m_acquired = false;
    }
}

ResourcePolicy::Resource *Resource::createResource()
{
    switch (m_type) {
    case AudioPlayback: {
        ResourcePolicy::AudioResource *audioResource = new ResourcePolicy::AudioResource;
        audioResource->setProcessID(QCoreApplication::applicationPid());
        audioResource->setStreamTag("media.name", "*");
        return audioResource;
    }
    case VideoPlayback:
        return new ResourcePolicy::VideoResource;
    case AudioRecorder:
        return new ResourcePolicy::AudioRecorderResource;
    case VideoRecorder:
        return new ResourcePolicy::VideoRecorderResource;
    case Vibra:
        return new ResourcePolicy::VibraResource;
    case Led:
        return new ResourcePolicy::LedsResource;
    case Backlight:
        return new ResourcePolicy::BacklightResource;
    case SystemButton:
        return new ResourcePolicy::SystemButtonResource;
    case LockButton:
        return new ResourcePolicy::LockButtonResource;
    case ScaleButton:
        return new ResourcePolicy::ScaleButtonResource;
    case SnapButton:
        return new ResourcePolicy::SnapButtonResource;
    case LensCover:
        return new ResourcePolicy::LensCoverResource;
    case HeadsetButtons:
        return new ResourcePolicy::HeadsetButtonsResource;
    default:
        qWarning() << "Resource type not supported" << m_type;
        return 0;
    }
}

void Resource::setPermissions(Permissions *permissions)
{
    m_permissions = permissions;
}
