// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/plugininforequest.h"
#include "Crypto/plugininforequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"
#include "Crypto/plugininfo.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

PluginInfoRequestPrivate::PluginInfoRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \class PluginInfoRequest
  \brief Allows a client request information about available crypto and storage plugins
  \inmodule SailfishCrypto
  \inheaderfile Crypto/plugininforequest.h
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
  \brief Returns information about available crypto plugins

  Note: this value is only valid if the status of the request is Request::Finished.
 */
QVector<Sailfish::Crypto::PluginInfo> PluginInfoRequest::cryptoPlugins() const
{
    Q_D(const PluginInfoRequest);
    return d->m_cryptoPlugins;
}

/*!
  \brief Returns information about available (Secrets) storage plugins

  A plugin which is both a crypto plugin and a storage plugin is able
  to store keys (and thus can be used with GenerateStoredKeyRequest etc).

  Note: this value is only valid if the status of the request is Request::Finished.
 */
QVector<Sailfish::Crypto::PluginInfo> PluginInfoRequest::storagePlugins() const
{
    Q_D(const PluginInfoRequest);
    return d->m_storagePlugins;
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

QVariantMap PluginInfoRequest::customParameters() const
{
    Q_D(const PluginInfoRequest);
    return d->m_customParameters;
}

void PluginInfoRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(PluginInfoRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *PluginInfoRequest::manager() const
{
    Q_D(const PluginInfoRequest);
    return d->m_manager.data();
}

void PluginInfoRequest::setManager(CryptoManager *manager)
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

        // should we pass customParameters in this case, or not?
        // there's no "specific plugin" which is the target of the request..
        QDBusPendingReply<Result, QVector<PluginInfo>, QVector<PluginInfo> > reply =
                d->m_manager->d_ptr->getPluginInfo();
        if (!reply.isValid() && !reply.error().message().isEmpty()) {
            d->m_status = Request::Finished;
            d->m_result = Result(Result::CryptoManagerNotInitializedError,
                                 reply.error().message());
            emit statusChanged();
            emit resultChanged();
        } else if (reply.isFinished()
                // work around a bug in QDBusAbstractInterface / QDBusConnection...
                && reply.argumentAt<0>().code() != Sailfish::Crypto::Result::Succeeded) {
            d->m_status = Request::Finished;
            d->m_result = reply.argumentAt<0>();
            d->m_cryptoPlugins = reply.argumentAt<1>();
            d->m_storagePlugins = reply.argumentAt<2>();
            emit statusChanged();
            emit resultChanged();
            emit cryptoPluginsChanged();
            emit storagePluginsChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, QVector<PluginInfo>, QVector<PluginInfo> > reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_cryptoPlugins = reply.argumentAt<1>();
                    this->d_ptr->m_storagePlugins = reply.argumentAt<2>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->cryptoPluginsChanged();
                emit this->storagePluginsChanged();
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
