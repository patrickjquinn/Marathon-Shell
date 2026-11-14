// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#include "redirecturiparser_p.h"

#include <QtCore/QUrl>
#include <QtCore/QUrlQuery>
#include <QtCore/QStringList>
#include <QtCore/QString>
#include <QtCore/QByteArray>
#include <QtCore/QPair>
#include <QtCore/QList>

QVariantMap Amber::Web::Authorization::parseRedirectUri(const QString &redirectUri, QString *errorMessage)
{
    QVariantMap data;

    const QUrl url(redirectUri);
    const QUrlQuery query(url.query());
    const QStringList fragments = url.fragment(QUrl::FullyEncoded).split(QChar('&'));

    QString errorString;

    QList<QPair<QString, QString> > fragmentPairs;
    for (const QString &fragment : fragments) {
        const QStringList pair = fragment.split(QChar('='));
        if (pair.size() != 2) {
            errorString += (errorString.isEmpty() ? QString() : QStringLiteral(", "))
                         + QStringLiteral("invalid fragment: not a pair: %1").arg(fragment);
            continue;
        }
        fragmentPairs.append(QPair<QString, QString>(
                QUrl::fromPercentEncoding(pair.first().toUtf8()),
                QUrl::fromPercentEncoding(pair.last().toUtf8())));
    }

    if (!errorString.isEmpty()) {
        // set the error message, but don't emit error, as it may not be fatal.
        *errorMessage = "Error parsing redirect uri: " + errorString;
    }

    const QList<QPair<QString, QString> > pairs(fragmentPairs + query.queryItems());
    for (const QPair<QString, QString> &pair : pairs) {
        data.insert(pair.first, pair.second);
    }

    return data;
}
