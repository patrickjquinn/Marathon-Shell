// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_IMPORTSTOREDKEYREQUEST_H
#define LIBSAILFISHCRYPTO_IMPORTSTOREDKEYREQUEST_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/request.h"
#include "Crypto/key.h"
#include "Crypto/interactionparameters.h"

#include <QtCore/QObject>
#include <QtCore/QScopedPointer>
#include <QtCore/QString>

namespace Sailfish {

namespace Crypto {

class CryptoManager;

class ImportStoredKeyRequestPrivate;
class SAILFISH_CRYPTO_API ImportStoredKeyRequest : public Sailfish::Crypto::Request
{
    Q_OBJECT
    Q_PROPERTY(QString cryptoPluginName READ cryptoPluginName WRITE setCryptoPluginName NOTIFY cryptoPluginNameChanged)
    Q_PROPERTY(Sailfish::Crypto::InteractionParameters interactionParameters READ interactionParameters WRITE setInteractionParameters NOTIFY interactionParametersChanged)
    Q_PROPERTY(QByteArray data READ data WRITE setData NOTIFY dataChanged)
    Q_PROPERTY(Sailfish::Crypto::Key keyTemplate READ keyTemplate WRITE setKeyTemplate NOTIFY keyTemplateChanged)
    Q_PROPERTY(Sailfish::Crypto::Key importedKeyReference READ importedKeyReference NOTIFY importedKeyReferenceChanged)

public:
    ImportStoredKeyRequest(QObject *parent = Q_NULLPTR);
    ~ImportStoredKeyRequest();

    QString cryptoPluginName() const;
    void setCryptoPluginName(const QString &pluginName);

    Sailfish::Crypto::InteractionParameters interactionParameters() const;
    void setInteractionParameters(const Sailfish::Crypto::InteractionParameters &uiParams);

    QByteArray data() const;
    void setData(const QByteArray &data);

    Sailfish::Crypto::Key keyTemplate() const;
    void setKeyTemplate(const Sailfish::Crypto::Key &keyTemplate);

    Sailfish::Crypto::Key importedKeyReference() const;

    Sailfish::Crypto::Request::Status status() const Q_DECL_OVERRIDE;
    Sailfish::Crypto::Result result() const Q_DECL_OVERRIDE;

    Sailfish::Crypto::CryptoManager *manager() const Q_DECL_OVERRIDE;
    void setManager(Sailfish::Crypto::CryptoManager *manager) Q_DECL_OVERRIDE;

    QVariantMap customParameters() const Q_DECL_OVERRIDE;
    void setCustomParameters(const QVariantMap &params) Q_DECL_OVERRIDE;

    void startRequest() Q_DECL_OVERRIDE;
    void waitForFinished() Q_DECL_OVERRIDE;

Q_SIGNALS:
    void cryptoPluginNameChanged();
    void interactionParametersChanged();
    void dataChanged();
    void keyTemplateChanged();
    void importedKeyReferenceChanged();

private:
    QScopedPointer<ImportStoredKeyRequestPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(ImportStoredKeyRequest)
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_GENERATESTOREDKEYREQUEST_H
