// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_PLUGININFO_P_H
#define LIBSAILFISHSECRETS_PLUGININFO_P_H

#include "Secrets/plugininfo.h"

#include <QtCore/QString>
#include <QtCore/QSharedData>

namespace Sailfish {

namespace Secrets {

class PluginInfoPrivate : public QSharedData
{
public:
    PluginInfoPrivate();
    PluginInfoPrivate(const PluginInfoPrivate &other);
    ~PluginInfoPrivate();

    QString m_displayName;
    QString m_name;
    int m_version;
    Sailfish::Secrets::PluginInfo::StatusFlags m_statusFlags;
};

} // namespace Secrets

} // namespace Sailfish

#endif // LIBSAILFISHSECRETS_PLUGININFO_P_H
