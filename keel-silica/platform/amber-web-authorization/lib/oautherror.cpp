// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

#include "oautherror.h"

namespace Amber {

namespace Web {

namespace Authorization {

class ErrorPrivate
{
    Q_DISABLE_COPY(ErrorPrivate)

public:
    explicit ErrorPrivate() {}
    explicit ErrorPrivate(Error::Code code, const QString &message, int httpCode)
        : m_code(code), m_message(message), m_httpCode(httpCode) {}

    Error::Code m_code = Error::NoError;
    QString m_message;
    int m_httpCode = 0;
};


/*!
  \class Amber::Web::Authorization::Error
  \brief Encapsulates an error which occurred during an OAuth operation
  \inmodule AmberWebAuthorization

  This simple Q_GADGET class provides access to three members:
  \c{code}, \c{message}, and \c{httpCode}.
*/

/*!
  \inmodule AmberWebAuthorization
  \enum Amber::Web::Authorization::Error::Code

  This enum defines the types of errors which may be encountered by an OAuth helper.

  \value NoError No error occurred, the operation succeeded
  \value InvalidOperationError The specified operation is not valid for the currently selected flow type
  \value InvalidParametersError The client application has not set the appropriate properties required for the operation
  \value StateMismatchError The state data does not match the expected state, possibly due to a man-in-the-middle attack
  \value NetworkError The helper was unable to perform the request to the remote service
  \value SslError The request to the remote service failed due to an SSL error
  \value HttpError The request to the remote service failed due to a HTTP error (or server-side authorization error)
  \value ParseError The result of the request could not be parsed successfully
  \value TimedOutError The timeout was reached while waiting for redirect
  \value OtherError The operation failed for some other reason

  \sa Amber::Web::Authorization::Error::code
*/

/*!
  \brief Destroys the error object
*/
Error::~Error()
{
    // empty, but required due to QScopedPointer deleter requiring knowledge
    // of layout, so can't use default destructor as that is defined within
    // the class declaration.
}

/*!
  \brief Constructs a new, empty error object
*/
Error::Error()
    : d_ptr(new ErrorPrivate)
{
}

/*!
  \brief Constructs a new error object with the given \a code, \a message, and \a httpCode set
*/
Error::Error(Error::Code code, const QString &message, int httpCode)
    : d_ptr(new ErrorPrivate(code, message, httpCode))
{
}

/*!
  \brief Constructs a copy of the \a other error object
*/
Error::Error(const Error &other)
    : d_ptr(new ErrorPrivate(other.code(), other.message(), other.httpCode()))
{
}

/*!
  \brief Sets this error's code, message, and httpCode equal to that of the \a other error object.
*/
Error& Error::operator=(const Error &other)
{
    d_ptr->m_code = other.code();
    d_ptr->m_message = other.message();
    d_ptr->m_httpCode = other.httpCode();
    return *this;
}

/*!
  \property Amber::Web::Authorization::Error::code
  \brief This property holds the error code associated with the most recent failed operation

  \sa Amber::Web::Authorization::Error::Code
*/
Error::Code Error::code() const
{
    return d_ptr->m_code;
}

/*!
  \property Amber::Web::Authorization::Error::message
  \brief This property holds the error message associated with the most recent failed operation

  The message is not translated or user-friendly, but is intended for developer
  consumption only.

  It may contain sensitive information, and as such it should not be logged
  persistently.
*/
QString Error::message() const
{
    return d_ptr->m_message;
}

/*!
  \property Amber::Web::Authorization::Error::httpCode
  \brief This property holds the HTTP error code associated with the most recent failed operation

  If the \c{code} property value is \c{HttpError} then a value will be set for this property.
*/
int Error::httpCode() const
{
    return d_ptr->m_httpCode;
}

} // namespace Authorization

} // namespace Web

} // namespace Amber

