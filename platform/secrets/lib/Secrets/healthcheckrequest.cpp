// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Timur Kristóf <timur.kristof@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/healthcheckrequest.h"
#include "Secrets/healthcheckrequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

HealthCheckRequestPrivate::HealthCheckRequestPrivate()
    : m_status(Request::Inactive)
    , m_saltDataHealth(HealthCheckRequest::HealthUnknown)
    , m_masterlockHealth(HealthCheckRequest::HealthUnknown)
{
}

/*!
  \qmltype HealthCheckRequest
  \brief Allows a client request information about the well-being of secrets data.
  \inqmlmodule Sailfish.Secrets
  \inherits Request
 */

/*!
  \class HealthCheckRequest
  \brief Allows a client request information about the well-being of secrets data.
  \inmodule SailfishSecrets
  \inheaderfile Secrets/healthcheckrequest.h

  Normally, a client does not have to use this kind of request, because the
  data corruption is taken care of by the Settings app. When a data corruption
  is detected by the secrets daemon it will display a notification to the user
  which opens the Settings app that will take care of it.

  Here is an example that retrieves information about the secrets data health:

  \code
  Sailfish::Secrets::SecretManager man;
  Sailfish::Secrets::HealthCheckRequest req;
  req.setManager(&man);
  req.startRequest(); // status() will change to Finished when complete

  // real clients should not use waitForFinished() because it blocks
  req.waitForFinished();
  qDebug() << "salt data health:" << req.saltDataHealth();
  qDebug() << "masterlock health:" << req.masterlockHealth();
  \endcode
 */

/*!
  \brief Constructs a new HealthCheckRequest object with the given \a parent.
 */
HealthCheckRequest::HealthCheckRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new HealthCheckRequestPrivate)
{
}

/*!
  \brief Destroys the HealthCheckRequest
 */
HealthCheckRequest::~HealthCheckRequest()
{
}

/*!
 \qmlproperty enumeration HealthCheckRequest::saltDataHealth
 \brief Provides information about salt data health.
 \value HealthOK
 \value HealthUnknown
 \value HealthCorrupted
 \value HealthOtherError
 */

/*!
  \brief Returns information about salt data health.

  The result can be used to decuce whether a data corruption happened
  to the salt data.
 */
HealthCheckRequest::Health HealthCheckRequest::saltDataHealth() const
{
    Q_D(const HealthCheckRequest);
    return d->m_saltDataHealth;
}

/*!
 \qmlproperty enumeration HealthCheckRequest::masterLockHealth
 \brief Provides information about masterlock health.
 \value HealthOK
 \value HealthUnknown
 \value HealthCorrupted
 \value HealthOtherError
 */

/*!
  \brief Returns information about masterlock health.

  The result can be used to decuce whether a data corruption happened
  to the masterlock data.
 */
HealthCheckRequest::Health HealthCheckRequest::masterlockHealth() const
{
    Q_D(const HealthCheckRequest);
    return d->m_masterlockHealth;
}

/*!
 \qmlproperty bool HealthCheckRequest::isHealthy
 \brief Tells whether the secrets data is completely healthy.
 */

/*!
  \brief Tells whether the secrets data is completely healthy.

  The result can be used to decuce whether a data corruption happened
  to any data which is monitored for data corruptions. Returns true if
  everything is okay and false otherwise.
 */
bool HealthCheckRequest::isHealthy() const
{
    Q_D(const HealthCheckRequest);
    return (d->m_saltDataHealth == HealthOK) && (d->m_masterlockHealth == HealthOK);
}

Request::Status HealthCheckRequest::status() const
{
    Q_D(const HealthCheckRequest);
    return d->m_status;
}

Result HealthCheckRequest::result() const
{
    Q_D(const HealthCheckRequest);
    return d->m_result;
}

SecretManager *HealthCheckRequest::manager() const
{
    Q_D(const HealthCheckRequest);
    return d->m_manager.data();
}

void HealthCheckRequest::setManager(SecretManager *manager)
{
    Q_D(HealthCheckRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void HealthCheckRequest::startRequest()
{
    Q_D(HealthCheckRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result,
                          HealthCheckRequest::Health,
                          HealthCheckRequest::Health> reply
                = d->m_manager->d_ptr->getHealthInfo();
        if (!reply.isValid() && !reply.error().message().isEmpty()) {
            d->m_status = Request::Finished;
            d->m_result = Result(Result::SecretManagerNotInitializedError,
                                 reply.error().message());
            d->m_saltDataHealth = HealthCheckRequest::HealthUnknown;
            d->m_masterlockHealth = HealthCheckRequest::HealthUnknown;
            emit saltDataHealthChanged();
            emit masterlockHealthChanged();
            emit isHealthyChanged();
            emit statusChanged();
            emit resultChanged();
        } else if (reply.isFinished()
                // work around a bug in QDBusAbstractInterface / QDBusConnection...
                && reply.argumentAt<0>().code() != Sailfish::Secrets::Result::Succeeded) {
            d->m_status = Request::Finished;
            d->m_result = reply.argumentAt<0>();
            d->m_saltDataHealth = reply.argumentAt<1>();
            d->m_masterlockHealth = reply.argumentAt<2>();
            emit saltDataHealthChanged();
            emit masterlockHealthChanged();
            emit isHealthyChanged();
            emit statusChanged();
            emit resultChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished, [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result,
                                  HealthCheckRequest::Health,
                                  HealthCheckRequest::Health> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_saltDataHealth = reply.argumentAt<1>();
                    this->d_ptr->m_masterlockHealth = reply.argumentAt<2>();
                }
                watcher->deleteLater();
                emit this->saltDataHealthChanged();
                emit this->masterlockHealthChanged();
                emit this->isHealthyChanged();
                emit this->statusChanged();
                emit this->resultChanged();
            });
        }
    }
}

void HealthCheckRequest::waitForFinished()
{
    Q_D(HealthCheckRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
