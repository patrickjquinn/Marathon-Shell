// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/plugininforequest.h"
#include "Secrets/plugininforequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

PluginInfoRequestPrivate::PluginInfoRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \class PluginInfoRequest
  \brief Allows a client request information about available storage, encryption and authentication plugins
  \inmodule SailfishSecrets
  \inheaderfile Secrets/plugininforequest.h

  An example of retrieving information about available plugins follows:

  \code
  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::PluginInfoRequest pir;
  pir.setManager(&sm);
  pir.startRequest();
  // status() will change to Finished when complete
  // real clients should not use waitForFinished().
  pir.waitForFinished();
  for (const auto &plugin : pir.encryptedStoragePlugins()) {
      qDebug() << "Have encrypted storage plugin:" << plugin.name()
               << "with version:" << plugin.version();
  }
  \endcode
 */

/*!
  \brief Constructs a new PluginInfoRequest object with the given \a parent.
 */
PluginInfoRequest::PluginInfoRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new PluginInfoRequestPrivate)
{
}

/*!
  \brief Destroys the PluginInfoRequest
 */
PluginInfoRequest::~PluginInfoRequest()
{
}

/*!
  \brief Returns information about available storage plugins.

  Storage plugins provide storage for secrets.  Different plugins
  may be better for different use cases (e.g., some may be backed
  by a secure hardware peripheral, or a Trusted Execution Environment
  application, whereas others may simply run "normal" application code
  to store data to an SQL database on the device's filesystem).

  These storage plugins don't perform any encryption; the Secrets
  service will use a specific encryption plugin to perform encryption
  and decryption operations.
 */
QVector<PluginInfo>
PluginInfoRequest::storagePlugins() const
{
    Q_D(const PluginInfoRequest);
    return d->m_storagePlugins;
}

/*!
  \brief Returns information about available encryption plugins.

  Encryption plugins provide crypto operations for secrets.
  Different plugisn may be better for different use cases (e.g.,
  some may be backed by a secure hardware peripheral, or a
  Trusted Execution Environment application, whereas others may
  simply run "normal" application code to perform cryptographic
  operations).
 */
QVector<PluginInfo>
PluginInfoRequest::encryptionPlugins() const
{
    Q_D(const PluginInfoRequest);
    return d->m_encryptionPlugins;
}

/*!
  \brief Returns information about available encrypted storage plugins.

  Encrypted storage plugins provide all-in-one encryption and
  storage for secrets.  They generally use block-mode encryption
  algorithms such as AES256 to encrypt or decrypt entire pages
  of data when writing to or reading from a database, which makes
  them ideally suited to implement device-lock protected secret
  collection stores.
 */
QVector<PluginInfo>
PluginInfoRequest::encryptedStoragePlugins() const
{
    Q_D(const PluginInfoRequest);
    return d->m_encryptedStoragePlugins;
}

/*!
  \brief Returns information about available authentication plugins.

  Authentication plugins provide UI flows which request the user
  to provide an authentication key (e.g. lock code, password,
  fingerprint, iris scan or voice recognition template) which
  can be used to generate an encryption or decryption key.

  If your application intends to store only application-specific
  secrets, then when creating the collection or secret you
  can specify an authentication plugin which supports
  the \c ApplicationSpecificAuthentication authentication type,
  and register a \l InteractionView with the manager
  which will then be used to provide the UI interaction with the
  user, in-process.  (Note that if you do not wish any UI interaction,
  the InteractionView implementation can return a precalculated key directly.)

  Alternatively, other plugins provide various system-mediated
  UI flows which ensure that the integrity of the user's authentication
  data is maintained.
 */
QVector<PluginInfo>
PluginInfoRequest::authenticationPlugins() const
{
    Q_D(const PluginInfoRequest);
    return d->m_authenticationPlugins;
}

Request::Status PluginInfoRequest::status() const
{
    Q_D(const PluginInfoRequest);
    return d->m_status;
}

Result PluginInfoRequest::result() const
{
    Q_D(const PluginInfoRequest);
    return d->m_result;
}

SecretManager *PluginInfoRequest::manager() const
{
    Q_D(const PluginInfoRequest);
    return d->m_manager.data();
}

void PluginInfoRequest::setManager(SecretManager *manager)
{
    Q_D(PluginInfoRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void PluginInfoRequest::startRequest()
{
    Q_D(PluginInfoRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result,
                          QVector<PluginInfo>,
                          QVector<PluginInfo>,
                          QVector<PluginInfo>,
                          QVector<PluginInfo> > reply
                = d->m_manager->d_ptr->getPluginInfo();
        if (!reply.isValid() && !reply.error().message().isEmpty()) {
            d->m_status = Request::Finished;
            d->m_result = Result(Result::SecretManagerNotInitializedError,
                                 reply.error().message());
            emit statusChanged();
            emit resultChanged();
        } else if (reply.isFinished()
                // work around a bug in QDBusAbstractInterface / QDBusConnection...
                && reply.argumentAt<0>().code() != Sailfish::Secrets::Result::Succeeded) {
            d->m_status = Request::Finished;
            d->m_result = reply.argumentAt<0>();
            d->m_storagePlugins.clear();
            d->m_encryptionPlugins.clear();
            d->m_encryptedStoragePlugins.clear();
            d->m_authenticationPlugins.clear();
            emit statusChanged();
            emit resultChanged();
            emit storagePluginsChanged();
            emit encryptionPluginsChanged();
            emit encryptedStoragePluginsChanged();
            emit authenticationPluginsChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result,
                                  QVector<PluginInfo>,
                                  QVector<PluginInfo>,
                                  QVector<PluginInfo>,
                                  QVector<PluginInfo> > reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_storagePlugins = reply.argumentAt<1>();
                    this->d_ptr->m_encryptionPlugins = reply.argumentAt<2>();
                    this->d_ptr->m_encryptedStoragePlugins = reply.argumentAt<3>();
                    this->d_ptr->m_authenticationPlugins = reply.argumentAt<4>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->storagePluginsChanged();
                emit this->encryptionPluginsChanged();
                emit this->encryptedStoragePluginsChanged();
                emit this->authenticationPluginsChanged();
            });
        }
    }
}

void PluginInfoRequest::waitForFinished()
{
    Q_D(PluginInfoRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
