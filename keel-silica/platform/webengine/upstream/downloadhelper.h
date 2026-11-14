// SPDX-FileCopyrightText: 2016 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
//
// Modified by Shipwright for Keel: registered as Sailfish.WebEngine's
// DownloadHelper singleton here (upstream registers it in its plugin).
/****************************************************************************
**
** Copyright (C) 2016 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
** Contact: Raine Makelainen <raine.makelaine@jolla.com>
** Contact: Chris Adams <chris.adams@jolla.com>
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef SAILFISHOS_WEBENGINE_DOWNLOADHELPER_H
#define SAILFISHOS_WEBENGINE_DOWNLOADHELPER_H

#include <QObject>
#include <QtQml/qqmlregistration.h> // Modified by Shipwright for Keel

namespace SailfishOS {

namespace WebEngineUtils {

class DownloadHelper : public QObject
{
    Q_OBJECT
    QML_ELEMENT // Modified by Shipwright for Keel
    QML_SINGLETON
public:
    DownloadHelper(QObject *parent = Q_NULLPTR);
    Q_INVOKABLE QString createUniqueFileUrl(QString fileName, const QString &path) const;
};

}
}

#endif // SAILFISHOS_WEBENGINE_DOWNLOADHELPER_H
