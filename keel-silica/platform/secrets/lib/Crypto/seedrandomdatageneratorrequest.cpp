// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/seedrandomdatageneratorrequest.h"
#include "Crypto/seedrandomdatageneratorrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

const QString SeedRandomDataGeneratorRequest::DefaultCsprngEngineName = QStringLiteral("default");

SeedRandomDataGeneratorRequestPrivate::SeedRandomDataGeneratorRequestPrivate()
    : m_csprngEngineName(SeedRandomDataGeneratorRequest::DefaultCsprngEngineName)
    , m_entropyEstimate(1.0)
    , m_status(Request::Inactive)
{
}

/*!
  \qmltype SeedRandomDataGeneratorRequest
  \brief Allows a client request that the system crypto service seed its RNG with specific data.
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::SeedRandomDataGeneratorRequest
*/

/*!
  \class SeedRandomDataGeneratorRequest
  \brief Allows a client request that the system crypto service seed its RNG with specific data.
  \inmodule SailfishCrypto
  \inheaderfile Crypto/seedrandomdatageneratorrequest.h
 */

/*!
  \brief Constructs a new SeedRandomDataGeneratorRequest object with the given \a parent.
 */
SeedRandomDataGeneratorRequest::SeedRandomDataGeneratorRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new SeedRandomDataGeneratorRequestPrivate)
{
}

/*!
  \brief Destroys the SeedRandomDataGeneratorRequest
 */
SeedRandomDataGeneratorRequest::~SeedRandomDataGeneratorRequest()
{
}

/*!
  \qmlproperty string SeedRandomDataGeneratorRequest::cryptoPluginName
  \brief The name of the crypto plugin which the client wishes to perform the key generation operation
*/

/*!
  \brief Returns the name of the crypto plugin which the client wishes to perform the key generation operation
 */
QString SeedRandomDataGeneratorRequest::cryptoPluginName() const
{
    Q_D(const SeedRandomDataGeneratorRequest);
    return d->m_cryptoPluginName;
}

/*!
  \brief Sets the name of the crypto plugin which the client wishes to perform the key generation operation to \a pluginName
 */
void SeedRandomDataGeneratorRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(SeedRandomDataGeneratorRequest);
    if (d->m_status != Request::Active && d->m_cryptoPluginName != pluginName) {
        d->m_cryptoPluginName = pluginName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit cryptoPluginNameChanged();
    }
}

/*!
  \qmlproperty string SeedRandomDataGeneratorRequest::csprngEngineName
  \brief The name of the cryptographically secure random number generator engine
         offered by the crypto plugin which the client wishes to seed.
*/

/*!
  \brief Returns the name of the cryptographically secure random number generator engine
         offered by the crypto plugin which the client wishes to seed.
 */
QString SeedRandomDataGeneratorRequest::csprngEngineName() const
{
    Q_D(const SeedRandomDataGeneratorRequest);
    return d->m_csprngEngineName;
}

/*!
  \brief Sets the name of the cryptographically secure random number generator engine
         offered by the crypto plugin which the client wishes to seed to \a engineName

  Usually, the default engine offered by the plugin is the correct CSPRNG engine
  to use (and in fact, most plugins will only offer that one engine), so clients
  should not have to set this parameter in the majority of cases.
 */
void SeedRandomDataGeneratorRequest::setCsprngEngineName(const QString &engineName)
{
    Q_D(SeedRandomDataGeneratorRequest);
    if (d->m_status != Request::Active && d->m_csprngEngineName != engineName) {
        d->m_csprngEngineName = engineName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit csprngEngineNameChanged();
    }
}

/*!
  \qmlproperty double SeedRandomDataGeneratorRequest::entropyEstimate
  \brief The client's estimate for how much entropy is contained in the seed data
*/

/*!
  \brief Returns the client's estimate for how much entropy is contained in the seed data

  The entropy estimate must be between 0.0 (no randomness) and 1.0 (totally random).
  The default entropy estimate is 1.0.
 */
double SeedRandomDataGeneratorRequest::entropyEstimate() const
{
    Q_D(const SeedRandomDataGeneratorRequest);
    return d->m_entropyEstimate;
}

/*!
  \brief Sets the client's estimate for how much entropy is contained in the seed data to \a estimate

  The value of \a estimate will be clamped to between 0.0 (no randomness) and 1.0 (totally random).
 */
void SeedRandomDataGeneratorRequest::setEntropyEstimate(double estimate)
{
    Q_D(SeedRandomDataGeneratorRequest);
    double clampedEstimate = estimate;
    if (clampedEstimate > 1.0) {
        clampedEstimate = 1.0;
    } else if (clampedEstimate < 0.0) {
        clampedEstimate = 0.0;
    }

    if (d->m_status != Request::Active && d->m_entropyEstimate != clampedEstimate) {
        d->m_entropyEstimate = clampedEstimate;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit entropyEstimateChanged();
    }
}

/*!
  \qmlproperty ArrayBuffer SeedRandomDataGeneratorRequest::seedData
  \brief The seed data
*/

/*!
  \brief Returns the seed data
 */
QByteArray SeedRandomDataGeneratorRequest::seedData() const
{
    Q_D(const SeedRandomDataGeneratorRequest);
    return d->m_seedData;
}

/*!
  \brief Sets the seed data to \a data
 */
void SeedRandomDataGeneratorRequest::setSeedData(const QByteArray &data)
{
    Q_D(SeedRandomDataGeneratorRequest);
    if (d->m_status != Request::Active && d->m_seedData != data) {
        d->m_seedData = data;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit seedDataChanged();
    }
}

Request::Status SeedRandomDataGeneratorRequest::status() const
{
    Q_D(const SeedRandomDataGeneratorRequest);
    return d->m_status;
}

Result SeedRandomDataGeneratorRequest::result() const
{
    Q_D(const SeedRandomDataGeneratorRequest);
    return d->m_result;
}

QVariantMap SeedRandomDataGeneratorRequest::customParameters() const
{
    Q_D(const SeedRandomDataGeneratorRequest);
    return d->m_customParameters;
}

void SeedRandomDataGeneratorRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(SeedRandomDataGeneratorRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *SeedRandomDataGeneratorRequest::manager() const
{
    Q_D(const SeedRandomDataGeneratorRequest);
    return d->m_manager.data();
}

void SeedRandomDataGeneratorRequest::setManager(CryptoManager *manager)
{
    Q_D(SeedRandomDataGeneratorRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void SeedRandomDataGeneratorRequest::startRequest()
{
    Q_D(SeedRandomDataGeneratorRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result> reply =
                d->m_manager->d_ptr->seedRandomDataGenerator(
                        d->m_seedData,
                        d->m_entropyEstimate,
                        d->m_csprngEngineName,
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
            emit statusChanged();
            emit resultChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
            });
        }
    }
}

void SeedRandomDataGeneratorRequest::waitForFinished()
{
    Q_D(SeedRandomDataGeneratorRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
