// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_STOREDKEYREQUEST_P_H
#define LIBSAILFISHCRYPTO_STOREDKEYREQUEST_P_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/storedkeyrequest.h"
#include "Crypto/cryptomanager.h"

#include <QtCore/QPointer>
#include <QtCore/QString>

#include <QtDBus/QDBusPendingCallWatcher>

#include <memory>

namespace Sailfish {

namespace Crypto {

class StoredKeyRequestPrivate
{
    Q_DISABLE_COPY(StoredKeyRequestPrivate)

public:
    explicit StoredKeyRequestPrivate();

    QPointer<Sailfish::Crypto::CryptoManager> m_manager;
    QVariantMap m_customParameters;
    Sailfish::Crypto::Key::Identifier m_identifier;
    Key::Components m_keyComponents;
    Sailfish::Crypto::Key m_storedKey;

    std::unique_ptr<QDBusPendingCallWatcher> m_watcher;
    Sailfish::Crypto::Request::Status m_status;
    Sailfish::Crypto::Result m_result;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_STOREDKEYREQUEST_P_H
