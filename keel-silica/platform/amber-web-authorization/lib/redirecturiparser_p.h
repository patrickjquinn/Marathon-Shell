// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#ifndef AMBER_WEB_AUTHORIZATION_REDIRECTURIPARSER_H
#define AMBER_WEB_AUTHORIZATION_REDIRECTURIPARSER_H

#include "oauthsymbols.h"

#include <QtCore/QVariantMap>
#include <QtCore/QString>

namespace Amber {

namespace Web {

namespace Authorization {

QVariantMap parseRedirectUri(const QString &redirectUri, QString *errorMessage) EXPORT_SYMBOL;

} // namespace Authorization

} // namespace Web

} // namespace Amber

#endif // AMBER_WEB_AUTHORIZATION_REDIRECTURIPARSER_H
