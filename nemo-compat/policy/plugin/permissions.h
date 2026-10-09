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

#ifndef NEMOPERMISSIONS_H
#define NEMOPERMISSIONS_H

#include <QObject>
#include <QString>

#include <QQmlParserStatus>
#include <QQmlListProperty>

#include <policy/resource.h>
#include <policy/resources.h>
#include <policy/resource-set.h>

class Resource;

class Permissions : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_PROPERTY(QString applicationClass READ applicationClass WRITE setApplicationClass NOTIFY applicationClassChanged)
    Q_PROPERTY(bool autoRelease READ autoRelease WRITE setAutoRelease NOTIFY autoReleaseChanged)
    Q_PROPERTY(QQmlListProperty<Resource> resources READ resources)
    Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool acquired READ isAcquired NOTIFY acquiredChanged)
    Q_INTERFACES(QQmlParserStatus)
    Q_CLASSINFO("DefaultProperty", "resources")
public:
    explicit Permissions(QObject *parent = 0);

    void classBegin();
    void componentComplete();

    QString applicationClass() const;
    void setApplicationClass(const QString &applicationClass);

    bool autoRelease() const;
    void setAutoRelease(bool release);

    QQmlListProperty<Resource> resources();

    void resourceRequiredChanged(Resource *resource);

    bool isEnabled() const;
    void setEnabled(bool enabled);


    bool isAcquired() const;

    Q_INVOKABLE void release();

signals:
    void applicationClassChanged();
    void autoReleaseChanged();
    void enabledChanged();
    void acquiredChanged();
    void granted();
    void denied();
    void lost();
    void released();
    void releasedByManager();

private slots:
    void resourcesBecameAvailable(const QList<ResourcePolicy::ResourceType> &resources);
    void resourcesGranted(const QList<ResourcePolicy::ResourceType> &resources);
    void updateOk();
    void resourcesDenied();
    void resourcesReleased();
    void resourcesReleasedByManager();
    void lostResources();

private:
    void clearAcquired();

    static void resourcesAppend(QQmlListProperty<Resource> *property, Resource *resource);
    // Modified by Shipwright for Qt 6: QQmlListProperty counts in qsizetype.
    static Resource *resourcesAt(QQmlListProperty<Resource> *property, qsizetype index);
    static qsizetype resourcesCount(QQmlListProperty<Resource> *property);
    static void resourcesClear(QQmlListProperty<Resource> *property);

    QString m_applicationClass;
    QList<Resource *> m_resources;
    ResourcePolicy::ResourceSet *m_resourceSet;
    bool m_autoRelease;
    bool m_enabled;
    bool m_acquired;
};

#endif
