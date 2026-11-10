// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_PLUGININFO_P_H
#define LIBSAILFISHCRYPTO_PLUGININFO_P_H

#include "Crypto/plugininfo.h"

#include <QtCore/QString>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Crypto {

class PluginInfoPrivate : public QSharedData
{
public:
    PluginInfoPrivate();
    PluginInfoPrivate(const PluginInfoPrivate &other);
    ~PluginInfoPrivate();

    QString m_displayName;
    QString m_name;
    int m_version;
    Sailfish::Crypto::PluginInfo::StatusFlags m_statusFlags;
};

} // namespace Crypto

} // namespace Sailfish

#endif // LIBSAILFISHCRYPTO_PLUGININFO_P_H
