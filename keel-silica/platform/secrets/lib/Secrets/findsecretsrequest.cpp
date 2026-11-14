// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/findsecretsrequest.h"
#include "Secrets/findsecretsrequest_p.h"

#include "Secrets/secretmanager.h"
#include "Secrets/secretmanager_p.h"
#include "Secrets/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Secrets;

FindSecretsRequestPrivate::FindSecretsRequestPrivate()
    : m_userInteractionMode(SecretManager::PreventInteraction)
    , m_status(Request::Inactive)
{
}

/*!
  \class FindSecretsRequest
  \brief Allows a client find the identifiers of secrets which match a specific filter
         from the system's secure secret storage service
  \inmodule SailfishSecrets
  \inheaderfile Secrets/findsecretsrequest.h

  The filter specifies metadata field/value pairs, and will be matched against
  secrets in the storage plugin identified by the specified storagePluginName()
  according to the given filterOperator().

  If a collection() is specified to search within, and the calling application is
  the creator of the collection, or alternatively if the user has granted the
  application permission to read from the collection, then the Secrets service will
  instruct the storage plugin to search the collection for matching secrets.

  However, if the application is not the creator of the collection and the user has
  not yet been asked if the application should have permission to read the collection,
  then a system-mediated access control UI flow may be triggered
  to obtain the user's permission (unless the given userInteractionMode() is
  \c PreventInteraction in which case the request will fail).

  If the collection uses an encryption key derived from the system device-lock,
  then the value will be able to be retrieved without any other UI flow being required
  if the collection is currently unlocked; however, if the collection uses an encryption
  key derived from a custom lock, then the custom lock authentication key will be obtained
  from the user via an authentication flow determined by the authentication plugin used for that
  collection (which may support \c ApplicationInteraction if the collection
  is an application-specific collection using an \c ApplicationSpecificAuthentication
  plugin, but otherwise will be a system-mediated UI flow, unless the userInteractionMode()
  specified is \c PreventInteraction in which case the request will fail).

  If no collection() is specified to search within, then only those standalone secrets
  which the application owns (that is, created) or has been granted explicit permission
  to access will be matched against the filter and potentially returned.

  An example of searching for secrets in a collection which match a filter follows:

  \code
  Secret::FilterData filter;
  filter.insert(QLatin1String("domain"), testSecret.filterData(QLatin1String("sailfishos.org")));
  filter.insert(QLatin1String("example"), testSecret.filterData(QLatin1String("true")));

  Sailfish::Secrets::SecretManager sm;
  Sailfish::Secrets::FindSecretsRequest fsr;
  fsr.setManager(&sm);
  fsr.setCollectionName(QLatin1String("ExampleCollection"));
  fsr.setStoragePluginName(Sailfish::Secrets::SecretManager::DefaultEncryptedStoragePluginName);
  fsr.setFilter(filter);
  fsr.setFilterOperator(Sailfish::Secrets::SecretManager::OperatorAnd);
  fsr.setUserInteractionMode(Sailfish::Secrets::SecretManager::PreventInteraction);
  fsr.startRequest(); // status() will change to Finished when complete
  \endcode
 */

/*!
  \brief Constructs a new FindSecretsRequest object with the given \a parent.
 */
FindSecretsRequest::FindSecretsRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new FindSecretsRequestPrivate)
{
}

/*!
  \brief Destroys the FindSecretsRequest
 */
FindSecretsRequest::~FindSecretsRequest()
{
}

/*!
  \qmlproperty string FindSecretsRequest::collectionName
  \brief The name of the collection that the client wishes to search for secrets matching some filter
*/

/*!
  \brief Returns the name of the collection that the client wishes to search for secrets matching some filter
 */
QString FindSecretsRequest::collectionName() const
{
    Q_D(const FindSecretsRequest);
    return d->m_collectionName;
}

/*!
  \brief Sets the name of the collection that the client wishes to search for secrets matching some filter to \a name

  Note: if the \a name is empty, then standalone secrets will be searched instead.
 */
void FindSecretsRequest::setCollectionName(const QString &name)
{
    Q_D(FindSecretsRequest);
    if (d->m_status != Request::Active && d->m_collectionName != name) {
        d->m_collectionName = name;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit collectionNameChanged();
    }
}

/*!
  \qmlproperty string FindSecretsRequest::storagePluginName
  \brief The name of the storage plugin within which the client wishes to find secrets
*/

/*!
  \brief Returns the name of the storage plugin within which the client wishes to find secrets
 */
QString FindSecretsRequest::storagePluginName() const
{
    Q_D(const FindSecretsRequest);
    return d->m_storagePluginName;
}

/*!
  \brief Sets the name of the storage plugin within which the client wishes to use to find secrets to \a pluginName
 */
void FindSecretsRequest::setStoragePluginName(const QString &pluginName)
{
    Q_D(FindSecretsRequest);
    if (d->m_status != Request::Active && d->m_storagePluginName != pluginName) {
        d->m_storagePluginName = pluginName;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit storagePluginNameChanged();
    }
}

/*!
  \qmlproperty FilterData FindSecretsRequest::filter
  \brief The filter which will be used when searching for matching secrets
*/

/*!
  \brief Returns the filter which will be used when searching for matching secrets
 */
Sailfish::Secrets::Secret::FilterData FindSecretsRequest::filter() const
{
    Q_D(const FindSecretsRequest);
    return d->m_filter;
}

/*!
  \brief Sets the filter which will be used when searching for matching secrets to \a filter

  The filter consists of key/value pairs which will be matched according to the
  specified filterOperation().

  For example, a Secret which has filter data which includes the following two entries:
  "website"="sailfishos.org","type"="CryptoCertificate" will match the filter
  \tt{{"website"="sailfishos.org","type"="UsernamePassword"}} if the filterOperator()
  is \c OperatorOr (since the secret metadata does match one of the filter values) but
  not if it is \c OperatorAnd (since the secret metadata doesn't match both filter values).
 */
void FindSecretsRequest::setFilter(const Sailfish::Secrets::Secret::FilterData &filter)
{
    Q_D(FindSecretsRequest);
    if (d->m_status != Request::Active && d->m_filter != filter) {
        d->m_filter = filter;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit filterChanged();
    }
}

/*!
  \qmlproperty enumeration FindSecretsRequest::filterOperator
  \brief The filter operator which will be used when searching for matching secrets
  \value OperatorOr
  \value OperatorAnd
*/

/*!
  \brief Returns the filter operator which will be used when searching for matching secrets
 */
Sailfish::Secrets::SecretManager::FilterOperator FindSecretsRequest::filterOperator() const
{
    Q_D(const FindSecretsRequest);
    return d->m_filterOperator;
}

/*!
  \brief Sets the filter operator which will be used when searching for matching secrets to \a op

  If the filter operator is AND then all keys must exist in the filter data stored for the secret,
  and all values for those keys must match the values specified in the input filter.

  If the filter operator is OR then at least one of the keys must exist in the filter data stored
  for the secret, where that key's value must match the value specified for that key in the
  input filter.
 */
void FindSecretsRequest::setFilterOperator(Sailfish::Secrets::SecretManager::FilterOperator op)
{
    Q_D(FindSecretsRequest);
    if (d->m_status != Request::Active && d->m_filterOperator != op) {
        d->m_filterOperator = op;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit filterOperatorChanged();
    }
}

/*!
  \qmlproperty enumeration FindSecretsRequest::userInteractionMode
  \brief The user interaction mode required when filtering the secrets (e.g. if a custom lock code must be requested from the user)
  \value PreventInteraction no user interaction allowed, operation will fail if interaction is required
  \value SystemInteraction system-mediated user interaction via system UI if required
  \value ApplicationInteraction in-process application UI will handle interaction, ApplicationSpecificAuthentication only.
*/

/*!
  \brief Returns the user interaction mode required when filtering the secrets (e.g. if a custom lock code must be requested from the user)
 */
SecretManager::UserInteractionMode FindSecretsRequest::userInteractionMode() const
{
    Q_D(const FindSecretsRequest);
    return d->m_userInteractionMode;
}

/*!
  \brief Sets the user interaction mode required when filtering the secrets (e.g. if a custom lock code must be requested from the user) to \a mode
 */
void FindSecretsRequest::setUserInteractionMode(SecretManager::UserInteractionMode mode)
{
    Q_D(FindSecretsRequest);
    if (d->m_status != Request::Active && d->m_userInteractionMode != mode) {
        d->m_userInteractionMode = mode;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit userInteractionModeChanged();
    }
}

/*!
  \qmlproperty Array FindSecretsRequest::identifiers
  \brief The identifiers of secrets which matched the filter
*/

/*!
  \brief Returns the identifiers of secrets which matched the filter.
 */
QVector<Secret::Identifier> FindSecretsRequest::identifiers() const
{
    Q_D(const FindSecretsRequest);
    return d->m_identifiers;
}

Request::Status FindSecretsRequest::status() const
{
    Q_D(const FindSecretsRequest);
    return d->m_status;
}

Result FindSecretsRequest::result() const
{
    Q_D(const FindSecretsRequest);
    return d->m_result;
}

SecretManager *FindSecretsRequest::manager() const
{
    Q_D(const FindSecretsRequest);
    return d->m_manager.data();
}

void FindSecretsRequest::setManager(SecretManager *manager)
{
    Q_D(FindSecretsRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void FindSecretsRequest::startRequest()
{
    Q_D(FindSecretsRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, QVector<Secret::Identifier> > reply;
        if (d->m_collectionName.isEmpty()) {
            reply = d->m_manager->d_ptr->findSecrets(d->m_storagePluginName,
                                                     d->m_filter,
                                                     d->m_filterOperator,
                                                     d->m_userInteractionMode);
        } else {
            reply = d->m_manager->d_ptr->findSecrets(d->m_collectionName,
                                                     d->m_storagePluginName,
                                                     d->m_filter,
                                                     d->m_filterOperator,
                                                     d->m_userInteractionMode);
        }

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
            d->m_identifiers = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit identifiersChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, QVector<Secret::Identifier> > reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::DaemonError,
                                                   reply.error().message());
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_identifiers = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->identifiersChanged();
            });
        }
    }
}

void FindSecretsRequest::waitForFinished()
{
    Q_D(FindSecretsRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
