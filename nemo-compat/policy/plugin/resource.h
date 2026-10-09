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

#ifndef NEMORESOURCE_H
#define NEMORESOURCE_H

#include <QObject>
#include <QString>

#include <policy/resource.h>
#include <policy/resource-set.h>

class Permissions;

class Resource : public QObject
{
    Q_OBJECT
    Q_PROPERTY(Type type READ type WRITE setType NOTIFY typeChanged)
    Q_PROPERTY(bool optional READ isOptional WRITE setOptional NOTIFY optionalChanged)
    Q_PROPERTY(bool required READ isRequired WRITE setRequired NOTIFY requiredChanged)
    Q_PROPERTY(bool acquired READ isAcquired NOTIFY acquiredChanged)
    Q_ENUMS(Type)
public:
    enum Type
    {
        AudioPlayback   = ResourcePolicy::AudioPlaybackType,
        VideoPlayback   = ResourcePolicy::VideoPlaybackType,
        AudioRecorder   = ResourcePolicy::AudioRecorderType,
        VideoRecorder   = ResourcePolicy::VideoRecorderType,
        Vibra           = ResourcePolicy::VibraType,
        Led             = ResourcePolicy::LedsType,
        Backlight       = ResourcePolicy::BacklightType,
        SystemButton    = ResourcePolicy::SystemButtonType,
        LockButton      = ResourcePolicy::LockButtonType,
        ScaleButton     = ResourcePolicy::ScaleButtonType,
        SnapButton      = ResourcePolicy::SnapButtonType,
        LensCover       = ResourcePolicy::LensCoverType,
        HeadsetButtons  = ResourcePolicy::HeadsetButtonsType
    };

    explicit Resource(QObject *parent = 0);

    Type type() const;
    void setType(Type type);

    bool isOptional() const;
    void setOptional(bool optional);

    bool isRequired() const;
    void setRequired(bool required);

    bool isAcquired() const;
    void updateAcquired();
    void clearAcquired();

    void addResource(ResourcePolicy::ResourceSet *resourceSet);
    void clearResource();

    void setPermissions(Permissions *permissions);

signals:
    void typeChanged();
    void optionalChanged();
    void requiredChanged();
    void acquiredChanged();

protected:
    ResourcePolicy::Resource *createResource();

private:
    Permissions *m_permissions;
    ResourcePolicy::Resource *m_resource;
    Type m_type;
    bool m_optional;
    bool m_required;
    bool m_acquired;
};

#endif
