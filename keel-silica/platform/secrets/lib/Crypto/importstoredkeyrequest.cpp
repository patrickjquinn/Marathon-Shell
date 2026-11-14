// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/importstoredkeyrequest_p.h"

#include "Crypto/cryptomanager.h"
#include "Crypto/cryptomanager_p.h"
#include "Crypto/serialization_p.h"

#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusPendingCallWatcher>

using namespace Sailfish::Crypto;

ImportStoredKeyRequestPrivate::ImportStoredKeyRequestPrivate()
    : m_status(Request::Inactive)
{
}

/*!
  \qmltype ImportStoredKeyRequest
  \brief Allows a client request that the system crypto service import and securely store a key.
  \inqmlmodule Sailfish.Crypto
  \inherits Request
  \instantiates Sailfish::Crypto::ImportStoredKeyRequest
*/

/*!
  \class ImportStoredKeyRequest
  \brief Allows a client request that the system crypto service import and securely store a key.
  \inmodule SailfishCrypto
  \inheaderfile Crypto/importstoredkeyrequest.h

  The imported key will be stored securely by the crypto daemon into the storage
  plugin identified by the storage plugin specified in the key template's
  identifier, and the returned key reference will not contain any private or secret
  key data.

  Available storage providers can be enumerated from the Sailfish Secrets API.

  If the cryptoPluginName() and the storage plugin specified in the identifier of
  the keyTemplate() are the same, then the key will be stored in storage managed by
  the crypto provider plugin, if that plugin supports storing keys.
  In that case, the crypto plugin must also be a Sailfish::Secrets::EncryptedStoragePlugin.
  Such crypto storage plugins can enforce key component readability constraints,
  and allow cryptographic operations to occur in the most secure manner possible.

  An example of importing a public key from a .pem file and storing securely follows:

  \code
  // Read the PEM data from the file.
  QFile pemFile("/path/to/file.pem");
  if (!pemFile.open(QIODevice::ReadOnly)) {
      qWarning() << "Unable to open file for reading.";
      return;
  }
  const QByteArray pemData = pemFile.readAll();

  // Set interaction parameters for the passphrase prompt
  // if a passphrase is required to decrypt the key from .pem.
  Sailfish::Crypto::InteractionParameters uiParams;
  uiParams.setInputType(Sailfish::Crypto::InteractionParameters::AlphaNumericInput);
  uiParams.setEchoMode(Sailfish::Crypto::InteractionParameters::NormalEcho);

  // Define the key metadata via a template.
  Sailfish::Crypto::Key keyTemplate;
  keyTemplate.setOperations(Sailfish::Crypto::CryptoManager::OperationEncrypt
                           |Sailfish::Crypto::CryptoManager::OperationVerify);
  keyTemplate.setComponentConstraints(Sailfish::Crypto::Key::MetaData
                                     |Sailfish::Crypto::Key::PublicKeyData);
  keyTemplate.setIdentifier(
          Sailfish::Crypto::Key::Identifier(
              QLatin1String("ExampleImportedKey"),
              QLatin1String("ExampleCollection"),
              Sailfish::Crypto::CryptoManager::DefaultCryptoStoragePluginName)));

  // Ask the crypto service to perform the required operations.
  Sailfish::Crypto::ImportStoredKeyRequest iskr;
  iskr.setManager(cryptoManager);
  iskr.setCryptoPluginName(Sailfish::Crypto::CryptoManager::DefaultCryptoStoragePluginName);
  iskr.setInteractionParameters(uiParams);
  iskr.setKeyTemplate(keyTemplate);
  iskr.setData(pemData);
  iskr.startRequest();
  \endcode
 */

/*!
  \brief Constructs a new ImportStoredKeyRequest object with the given \a parent.
 */
ImportStoredKeyRequest::ImportStoredKeyRequest(QObject *parent)
    : Request(parent)
    , d_ptr(new ImportStoredKeyRequestPrivate)
{
}

/*!
  \brief Destroys the ImportStoredKeyRequest
 */
ImportStoredKeyRequest::~ImportStoredKeyRequest()
{
}

/*!
  \qmlproperty string ImportStoredKeyRequest::cryptoPluginName
  \brief The name of the crypto plugin which the client wishes to perform the key generation operation
*/

/*!
  \brief Returns the name of the crypto plugin which the client wishes to perform the key generation operation
 */
QString ImportStoredKeyRequest::cryptoPluginName() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_cryptoPluginName;
}

/*!
  \brief Sets the name of the crypto plugin which the client wishes to perform the key generation operation to \a pluginName
 */
void ImportStoredKeyRequest::setCryptoPluginName(const QString &pluginName)
{
    Q_D(ImportStoredKeyRequest);
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
  \qmlproperty InteractionParameters ImportStoredKeyRequest::InteractionParameters
  \brief The user input parameters which should be used when requesting the input data from the user
*/

/*!
  \brief Returns the user input parameters which should be used when requesting the input data from the user

  If specified, the user may be prompted to enter a pass phrase needed to decrypt the imported
  key.
 */
Sailfish::Crypto::InteractionParameters
ImportStoredKeyRequest::interactionParameters() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_uiParams;
}

/*!
  \brief Sets the user input parameters which should be used when requesting the input data from the user to \a uiParams
 */
void ImportStoredKeyRequest::setInteractionParameters(
        const Sailfish::Crypto::InteractionParameters &uiParams)
{
    Q_D(ImportStoredKeyRequest);
    if (d->m_status != Request::Active && d->m_uiParams != uiParams) {
        d->m_uiParams = uiParams;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit interactionParametersChanged();
    }
}

/*!
  \qmlproperty ArrayBuffer ImportStoredKeyRequest::data
  \brief The data which should be imported as a key.
*/

/*!
  \brief Returns the data which should be imported as a key.
 */
QByteArray ImportStoredKeyRequest::data() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_data;
}

/*!
  \brief Sets the \a data which should be imported.
 */
void ImportStoredKeyRequest::setData(const QByteArray &data)
{
    Q_D(ImportStoredKeyRequest);
    if (d->m_status != Request::Active && d->m_data != data) {
        d->m_data = data;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit dataChanged();
    }
}

/*!
  \qmlproperty Key ImportStoredKeyRequest::keyTemplate
  \brief Returns the key which should be used as a template when storing the imported key
*/

/*!
  \brief Returns the key which should be used as a template when storing the imported key

  The key template should contain a valid identifier, component constraints to prevent
  unauthorized clients from reading back sensitive data, and valid operations, as
  well as any filter data the client wishes to be associated with the key.

  Other information, like the algorithm and key size, will be set automatically by
  the crypto plugin which constructs the key from the import data.
 */
Key ImportStoredKeyRequest::keyTemplate() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_keyTemplate;
}

/*!
  \brief Sets the key which should be used as a template when storing the imported key to \a keyTemplate
 */
void ImportStoredKeyRequest::setKeyTemplate(const Key &keyTemplate)
{
    Q_D(ImportStoredKeyRequest);
    if (d->m_status != Request::Active && d->m_keyTemplate != keyTemplate) {
        d->m_keyTemplate = keyTemplate;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit keyTemplateChanged();
    }
}

/*!
  \qmlproperty Key ImportStoredKeyRequest::importedKeyReference
  \brief Returns a key reference to the securely-stored imported key
  \note this value is only valid if the status of the request is \c Request.Finished.
*/

/*!
  \brief Returns a key reference to the securely-stored imported key

  Note: this value is only valid if the status of the request is Request::Finished.

  The key reference will contain metadata and a valid identifier, but no private or secret key data.
 */
Key ImportStoredKeyRequest::importedKeyReference() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_importedKeyReference;
}

Request::Status ImportStoredKeyRequest::status() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_status;
}

Result ImportStoredKeyRequest::result() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_result;
}

QVariantMap ImportStoredKeyRequest::customParameters() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_customParameters;
}

void ImportStoredKeyRequest::setCustomParameters(const QVariantMap &params)
{
    Q_D(ImportStoredKeyRequest);
    if (d->m_customParameters != params) {
        d->m_customParameters = params;
        if (d->m_status == Request::Finished) {
            d->m_status = Request::Inactive;
            emit statusChanged();
        }
        emit customParametersChanged();
    }
}

CryptoManager *ImportStoredKeyRequest::manager() const
{
    Q_D(const ImportStoredKeyRequest);
    return d->m_manager.data();
}

void ImportStoredKeyRequest::setManager(CryptoManager *manager)
{
    Q_D(ImportStoredKeyRequest);
    if (d->m_manager.data() != manager) {
        d->m_manager = manager;
        emit managerChanged();
    }
}

void ImportStoredKeyRequest::startRequest()
{
    Q_D(ImportStoredKeyRequest);
    if (d->m_status != Request::Active && !d->m_manager.isNull()) {
        d->m_status = Request::Active;
        emit statusChanged();
        if (d->m_result.code() != Result::Pending) {
            d->m_result = Result(Result::Pending);
            emit resultChanged();
        }

        QDBusPendingReply<Result, Key> reply =
                d->m_manager->d_ptr->importStoredKey(d->m_data,
                                                     d->m_keyTemplate,
                                                     d->m_uiParams,
                                                     d->m_customParameters,
                                                     d->m_cryptoPluginName);
        if (reply.isError()) {
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
            d->m_importedKeyReference = reply.argumentAt<1>();
            emit statusChanged();
            emit resultChanged();
            emit importedKeyReferenceChanged();
        } else {
            d->m_watcher.reset(new QDBusPendingCallWatcher(reply));
            connect(d->m_watcher.get(), &QDBusPendingCallWatcher::finished,
                    [this] {
                QDBusPendingCallWatcher *watcher = this->d_ptr->m_watcher.release();
                QDBusPendingReply<Result, Key> reply = *watcher;
                this->d_ptr->m_status = Request::Finished;
                if (reply.isError()) {
                    this->d_ptr->m_result = Result(Result::CryptoManagerNotInitializedError,
                                         reply.error().message());
                    this->d_ptr->m_importedKeyReference = Key();
                } else {
                    this->d_ptr->m_result = reply.argumentAt<0>();
                    this->d_ptr->m_importedKeyReference = reply.argumentAt<1>();
                }
                watcher->deleteLater();
                emit this->statusChanged();
                emit this->resultChanged();
                emit this->importedKeyReferenceChanged();
            });
        }
    }
}

void ImportStoredKeyRequest::waitForFinished()
{
    Q_D(ImportStoredKeyRequest);
    if (d->m_status == Request::Active && d->m_watcher) {
        d->m_watcher->waitForFinished();
    }
}
