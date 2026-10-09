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

#include "permissions.h"
#include "resource.h"

Permissions::Permissions(QObject *parent)
    : QObject(parent)
    , m_resourceSet(0)
    , m_autoRelease(false)
    , m_enabled(false)
    , m_acquired(false)
{
}

void Permissions::classBegin()
{
}

void Permissions::componentComplete()
{
    if (!m_resourceSet) {
        m_resourceSet = new ResourcePolicy::ResourceSet(m_applicationClass, this, false, m_autoRelease);

        connect(m_resourceSet, SIGNAL(resourcesBecameAvailable(QList<ResourcePolicy::ResourceType>)),
                this, SLOT(resourcesBecameAvailable(QList<ResourcePolicy::ResourceType>)));
        connect(m_resourceSet, SIGNAL(resourcesGranted(QList<ResourcePolicy::ResourceType>)),
                this, SLOT(resourcesGranted(QList<ResourcePolicy::ResourceType>)));
        connect(m_resourceSet, SIGNAL(updateOK()), this, SLOT(updateOk()));
        connect(m_resourceSet, SIGNAL(resourcesDenied()), this, SLOT(resourcesDenied()));
        connect(m_resourceSet, SIGNAL(resourcesDenied()), this, SLOT(resourcesDenied()));
        connect(m_resourceSet, SIGNAL(resourcesReleased()), this, SLOT(resourcesReleased()));
        connect(m_resourceSet, SIGNAL(resourcesReleasedByManager()),
                this, SLOT(resourcesReleasedByManager()));
        connect(m_resourceSet, SIGNAL(lostResources()), this, SLOT(lostResources()));

        for (int i = 0; i < m_resources.count(); ++i) {
            Resource * const resource = m_resources.at(i);
            if (resource->isRequired())
                resource->addResource(m_resourceSet);
        }
        if (m_enabled)
            m_resourceSet->acquire();
    }
}

QString Permissions::applicationClass() const
{
    return m_applicationClass;
}

void Permissions::setApplicationClass(const QString &applicationClass)
{
    if (m_applicationClass != applicationClass) {
        m_applicationClass = applicationClass;
        emit applicationClassChanged();
    }
}

bool Permissions::autoRelease() const
{
    return m_autoRelease;
}

void Permissions::setAutoRelease(bool release)
{
    if (m_autoRelease != release) {
        m_autoRelease = release;
        emit autoReleaseChanged();
    }
}

void Permissions::resourcesAppend(QQmlListProperty<Resource> *property, Resource *resource)
{
    Permissions *permissions = qobject_cast<Permissions *>(property->object);

    permissions->m_resources.append(resource);
    if (permissions->m_resourceSet) {
        resource->setPermissions(permissions);
        resource->addResource(permissions->m_resourceSet);
        if (permissions->m_enabled)
            permissions->m_resourceSet->update();
    }
}

// Modified by Shipwright for Qt 6: qsizetype index and count.
Resource *Permissions::resourcesAt(QQmlListProperty<Resource> *property, qsizetype index)
{
    return qobject_cast<Permissions *>(property->object)->m_resources.at(index);
}

qsizetype Permissions::resourcesCount(QQmlListProperty<Resource> *property)
{
    return qobject_cast<Permissions *>(property->object)->m_resources.count();
}

void Permissions::resourcesClear(QQmlListProperty<Resource> *)
{
}

QQmlListProperty<Resource> Permissions::resources()
{
    return QQmlListProperty<Resource>(
                this, 0, resourcesAppend, resourcesCount, resourcesAt, resourcesClear);
}

void Permissions::resourceRequiredChanged(Resource *resource)
{
    if (resource->isRequired()) {
        resource->addResource(m_resourceSet);
    } else {
        m_resourceSet->deleteResource(ResourcePolicy::ResourceType(resource->type()));
    }

    if (m_enabled)
        m_resourceSet->update();
}

bool Permissions::isEnabled() const
{
    return m_enabled;
}

void Permissions::setEnabled(bool enabled)
{
    if (m_enabled != enabled) {
        m_enabled = enabled;
        if (m_resourceSet) {
            if (m_enabled)
                m_resourceSet->acquire();
            else
                m_resourceSet->release();
        }
        emit enabledChanged();
    }
}

bool Permissions::isAcquired() const
{
    return m_acquired;
}

void Permissions::release()
{
    if (m_resourceSet)
        m_resourceSet->release();
}

void Permissions::resourcesBecameAvailable(const QList<ResourcePolicy::ResourceType> &)
{
    if (m_enabled)
        m_resourceSet->acquire();
}

void Permissions::resourcesGranted(const QList<ResourcePolicy::ResourceType> &)
{
    bool wasAcquired = m_acquired;
    m_acquired = true;

    for (int i = 0; i < m_resources.count(); ++i)
        m_resources.at(i)->updateAcquired();

    if (!wasAcquired)
        emit acquiredChanged();

    emit granted();
}

void Permissions::updateOk()
{
    for (int i = 0; i < m_resources.count(); ++i)
        m_resources.at(i)->updateAcquired();
}

void Permissions::resourcesDenied()
{
    clearAcquired();
    emit denied();
}

void Permissions::resourcesReleased()
{
    clearAcquired();
    emit released();
}

void Permissions::resourcesReleasedByManager()
{
    clearAcquired();
    emit releasedByManager();
}

void Permissions::lostResources()
{
    clearAcquired();
    emit lost();
}

void Permissions::clearAcquired()
{
    if (m_acquired) {
        m_acquired = false;

        for (int i = 0; i < m_resources.count(); ++i)
            m_resources.at(i)->clearAcquired();

        emit acquiredChanged();
    }
}
