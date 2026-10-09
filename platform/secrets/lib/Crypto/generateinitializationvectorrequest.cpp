// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Bea Lam <bea.lam@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/generateinitializationvectorrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

GenerateInitializationVectorRequestPrivate::GenerateInitializationVectorRequestPrivate()
    : m_algorithm(CryptoManager::AlgorithmUnknown)
    , m_blockMode(CryptoManager::BlockModeCbc)
    , m_keySize(-1)
    , m_status(Request::Inactive)
{
}

/*!
  \class GenerateInitializationVectorRequest
  \brief Allows the client to request an Initialization Vector from the system crypto service
  \inmodule SailfishCrypto
  \inheaderfile Crypto/generateinitializationvectorrequest.h
 */

/*!
  \brief Constructs a new GenerateInitializationVectorRequest object with the given \a parent.
 */
GenerateInitializationVectorRequest::GenerateInitializationVectorRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new GenerateInitializationVectorRequestPrivate)
{
}

/*!
  \brief Destroys the GenerateInitializationVectorRequest
 */
GenerateInitializationVectorRequest::~GenerateInitializationVectorRequest()
{
}

/*!
  \brief Returns the algorithm which should be used when generating the IV
 */
CryptoManager::Algorithm GenerateInitializationVectorRequest::algorithm() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_algorithm;
}

/*!
  \brief Sets the algorithm which should be used when generating the IV to \a algorithm
 */
void GenerateInitializationVectorRequest::setAlgorithm(CryptoManager::Algorithm algorithm)
{
    Q_D(GenerateInitializationVectorRequest);
    if (d->m_status != Request::Active && d->m_algorithm != algorithm) {
        d->m_algorithm = algorithm;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit algorithmChanged();
    }
}

/*!
  \brief Returns the block mode which should be used when generating the IV
 */
Sailfish::Crypto::CryptoManager::BlockMode GenerateInitializationVectorRequest::blockMode() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_blockMode;
}

/*!
  \brief Sets the block mode which should be used when generating the IV to \a mode
 */
void GenerateInitializationVectorRequest::setBlockMode(Sailfish::Crypto::CryptoManager::BlockMode mode)
{
    Q_D(GenerateInitializationVectorRequest);
    if (d->m_status != Request::Active && d->m_blockMode != mode) {
        d->m_blockMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit blockModeChanged();
    }
}

/*!
  \brief Returns the key size which should be used when generating the IV
 */
int GenerateInitializationVectorRequest::keySize() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_keySize;
}

/*!
  \brief Sets the key size which should be used when generating the IV to \a keySize
 */
void GenerateInitializationVectorRequest::setKeySize(int keySize)
{
    Q_D(GenerateInitializationVectorRequest);
    if (d->m_status != Request::Active && d->m_keySize != keySize) {
        d->m_keySize = keySize;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit keySizeChanged();
    }
}

/*!
  \brief Returns the name of the crypto plugin which the client wishes to perform the generation
 */
QString GenerateInitializationVectorRequest::cryptoPluginName() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_cryptoPluginName;
}

/*!
  \brief Sets the name of the crypto plugin which the client wishes to perform the generation to \a pluginName
 */
void GenerateInitializationVectorRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(GenerateInitializationVectorRequest);
    if (d->m_status != Request::Active && d->m_cryptoPluginName != pluginName) {
        d->m_cryptoPluginName = pluginName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit cryptoPluginNameChanged();
    }
}

QByteArray GenerateInitializationVectorRequest::generatedInitializationVector() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_generatedIv;
}

Request::Status GenerateInitializationVectorRequest::status() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_status;
}

Result GenerateInitializationVectorRequest::result() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_result;
}

QVariantMap GenerateInitializationVectorRequest::customParameters() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_customParameters;
}

void GenerateInitializationVectorRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(GenerateInitializationVectorRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *GenerateInitializationVectorRequest::manager() const
{
    Q_D(const GenerateInitializationVectorRequest);
    return d->m_manager.data();
}

void GenerateInitializationVectorRequest::setManager(CryptoManager *manager)
{
    Q_D(GenerateInitializationVectorRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void GenerateInitializationVectorRequest::startRequest()
{
    Q_D(GenerateInitializationVectorRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, QByteArray> reply =
                d->m_manager->d_ptr->generateInitializationVector(d->m_algorithm,
                                                                  d->m_blockMode,
                                                                  d->m_keySize,
                                                                  d->m_customParameters,
                                                                  d->m_cryptoPluginName);
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
            d->m_generatedIv = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit generatedInitializationVectorChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, QByteArray> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_generatedIv = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->generatedInitializationVectorChanged();
            });
        }
    }
}

void GenerateInitializationVectorRequest::waitForFinished()
{
    Q_D(GenerateInitializationVectorRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
