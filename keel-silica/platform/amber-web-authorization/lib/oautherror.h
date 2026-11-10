// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#ifndef AMBER_WEB_AUTHORIZATION_OAUTHERROR_H
#define AMBER_WEB_AUTHORIZATION_OAUTHERROR_H

#include "oauthsymbols.h"

#include <QtCore/QScopedPointer>
#include <QtCore/QObject>
#include <QtCore/QString>

namespace Amber {

namespace Web {

namespace Authorization {

class ErrorPrivate;
class EXPORT_SYMBOL Error
{
    Q_GADGET
    Q_DECLARE_PRIVATE(Error)
    Q_PROPERTY(Code code READ code CONSTANT)
    Q_PROPERTY(QString message READ message CONSTANT)
    Q_PROPERTY(int httpCode READ httpCode CONSTANT)

public:
    enum Code {
        NoError = 0,
        InvalidOperationError,
        InvalidParametersError,
        StateMismatchError,
        NetworkError,
        SslError,
        HttpError,
        ParseError,
        TimedOutError,
        OtherError
    };
    Q_ENUM(Code)

    ~Error();
    Error();
    Error(Code code, const QString &message, int httpCode = 0);
    Error(const Error &other);
    Error& operator=(const Error &other);

    Code code() const;
    QString message() const;
    int httpCode() const;

private:
    QScopedPointer<ErrorPrivate> const d_ptr;
};

} // namespace Authorization

} // namespace Web

} // namespace Amber

Q_DECLARE_METATYPE(Amber::Web::Authorization::Error)

#endif // AMBER_WEB_AUTHORIZATION_OAUTHERROR_H
