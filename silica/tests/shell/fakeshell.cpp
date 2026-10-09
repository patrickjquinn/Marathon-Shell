// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "fakeshell.h"

#include <QMetaObject>
#include <QSemaphore>

int FakeShellObject::contentOrientation() const
{
    QMutexLocker l(&m_mutex);
    return m_contentOrientations.isEmpty() ? 0 : m_contentOrientations.constLast();
}

int FakeShellObject::activateCalls() const
{
    QMutexLocker l(&m_mutex);
    return m_activateCalls;
}

QList<int> FakeShellObject::contentOrientations() const
{
    QMutexLocker l(&m_mutex);
    return m_contentOrientations;
}

void FakeShellObject::Activate()
{
    QMutexLocker l(&m_mutex);
    ++m_activateCalls;
}

void FakeShellObject::SetContentOrientation(int degrees)
{
    {
        QMutexLocker l(&m_mutex);
        m_contentOrientations.append(degrees);
    }
    emit ContentOrientationChanged(degrees);
}

void FakeShellObject::setOrientation(int degrees)
{
    m_orientation = degrees;
    emit OrientationChanged(degrees);
}

void FakeShellObject::setActive(bool active)
{
    m_active = active;
    emit ActiveChanged(active);
}

void FakeShellObject::setCoverStatus(int status)
{
    m_coverStatus = status;
    emit CoverStatusChanged(status);
}

void FakeShellObject::setAmbience(const QVariantMap &ambience)
{
    m_ambience = ambience;
    emit AmbienceChanged(ambience);
}

void FakeShellObject::requestClose()
{
    emit CloseRequested();
}

FakeShell::FakeShell(const QString &socketDir)
    : m_context(new QObject)
{
    m_thread.setObjectName(QStringLiteral("fake-keel-shell"));
    m_thread.start();
    m_context->moveToThread(&m_thread);
    QSemaphore ready;
    QMetaObject::invokeMethod(
        m_context,
        [this, socketDir, &ready]() {
            m_object = new FakeShellObject;
            m_server = new QDBusServer(QStringLiteral("unix:dir=") + socketDir);
            m_server->setAnonymousAuthenticationAllowed(true);
            QObject::connect(m_server, &QDBusServer::newConnection, m_object,
                             [this](const QDBusConnection &c) {
                                 QDBusConnection conn(c);
                                 conn.registerObject(QStringLiteral("/org/shipwright/keel/Shell"), m_object,
                                                     QDBusConnection::ExportScriptableContents
                                                         | QDBusConnection::ExportAllProperties);
                                 QMutexLocker l(&m_mutex);
                                 m_connected = true;
                             },
                             Qt::DirectConnection);
            m_address = m_server->address();
            ready.release();
        },
        Qt::QueuedConnection);
    ready.acquire();
}

FakeShell::~FakeShell()
{
    QMetaObject::invokeMethod(
        m_context,
        [this]() {
            delete m_server;
            delete m_object;
        },
        Qt::BlockingQueuedConnection);
    m_thread.quit();
    m_thread.wait();
    delete m_context;
}

bool FakeShell::clientConnected() const
{
    QMutexLocker l(&m_mutex);
    return m_connected;
}
