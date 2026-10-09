// SPDX-FileCopyrightText: 2013 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "signinparameters.h"
#include <QtDebug>

/*!
    \qmltype SignInParameters
    \instantiates SignInParameters
    \inqmlmodule Sailfish.Accounts
    \brief Provides access to sign-in parameters applicable to a service

    The Account::signIn() function requires clients to pass in
    SignInParameters which allow the application to sign in using
    the specified credentials.  These parameters include the authentication
    method and mechanism associated with a service (for example,
    Facebook requires a \c user_agent OAuth2 flow) and can include other
    parameters pertinent to the sign in process (for example, scopes which
    define permissions requested from the user).

    The properties of an SignInParameter instance will NOT update
    automatically if the credentials in the database are updated
    or removed by a different process, or if any services change.

    When performing sign-in, applications will retrieve the parameters
    applicable for them through the account, and then modify the
    parameters (for example, to add the \c ClientId parameter) as necessary
    for their use-case.

    An example of using the SignInParameters type to create sign-in
    credentials with an OAuth-based service is:

    \qml
        import Sailfish.Accounts 1.0

        Account {
            id: account
            identifier: 12 // retrieved from AccountManager or AccountModel

            onStatusChanged: {
                if (status == Account.Initialized) {
                    var siParams = signInParameters("facebook-sharing")
                    siParams.setParameter("ClientId", "123456789abcdef") // set application-specific client id
                    siParams.setParameter("Scope", ["user_events"])      // set application-specific scopes
                    if (!hasSignInCredentials("MyApp", "MyCredentials")) {
                        createSignInCredentials("MyApp", "SharingCredentials", "MySecretKey", siParams)
                    } else {
                        signIn("MyApp", "SharingCredentials", "MySecretKey", siParams)
                    }
                }
            }

            onSignInCredentialsCreated: {
                for (var i in data) console.log(i+"="+data[i]) // AccessToken etc
            }

            onSignInResponse: {
                for (var i in data) console.log(i+"="+data[i]) // AccessToken etc
            }
        }
    \endqml

    Credentials for non-OAuth-based services often require a username and
    password to be specified.  These fields of the SignInParameters need only
    be specified if the application needs to create sign-in credentials (as
    you should not ask the user to input username/password once the credentials
    have been created).

    \qml
        import Sailfish.Accounts 1.0

        Account {
            id: account
            identifier: 15 // some Jabber account retrieved from AccountManager or AccountModel

            onStatusChanged: {
                if (status == Account.Initialized) {
                    if (!hasSignInCredentials("MyApp", "MyCredentials")) {
                        // ... request username/password from user via UI
                        // var usernameFromUI = ...
                        // var passwordFromUI = ...
                        // once we have those, create the SignInParameters:
                        var siParams = signInParameters("jabber", usernameFromUI, passwordFromUI)
                        createSignInCredentials("MyApp", "JabberCredentials", "MySecretKey", siParams)
                    } else {
                        // already have sign in credentials, so use the existing SignInParameters:
                        var siParams = signInParameters("jabber")
                        signIn("MyApp", "JabberCredentials", "MySecretKey", siParams)
                    }
                }
            }

            onSignInCredentialsCreated: {
                for (var i in data) console.log(i+"="+data[i]) // AccessToken etc
            }

            onSignInResponse: {
                for (var i in data) console.log(i+"="+data[i]) // AccessToken etc
            }
        }
    \endqml
*/

SignInParameters::SignInParameters(const QString &serviceName, const QString &method, const QString &mechanism,
                                   const QVariantMap &parameters, const QString &username, const QString &password,
                                   QObject *parent)
    : QObject(parent)
    , m_serviceName(serviceName)
    , m_method(method)
    , m_mechanism(mechanism)
    , m_parameters(parameters)
    , m_username(username)
    , m_password(password)
{
}

SignInParameters::~SignInParameters()
{
}

QVariant sanitiseValue(const QVariant &value)
{
    QVariant retn;
    int valueType = value.type();
    if (valueType == QMetaType::QVariantList) {
        retn = value.toStringList();
    } else if (valueType == QMetaType::QVariantMap) {
        QVariantMap map = value.toMap();
        for (auto it = map.begin(); it != map.end(); ++it) {
            QVariant ret = sanitiseValue(*it);
            if (ret.isValid())
                *it = ret;
            else
                return QVariant();
        }
        retn = QVariant::fromValue(map);
    } else if (valueType == QMetaType::Bool
            || valueType == QMetaType::Int
            || valueType == QMetaType::UInt
            || valueType == QMetaType::LongLong
            || valueType == QMetaType::ULongLong
            || valueType == QMetaType::QString
            || valueType == QMetaType::QStringList) {
        // valid value.
        retn = value;
    }

    return retn;
}

/*!
    \qmlproperty string SignInParameters::serviceName
    The name of the service for which these parameters are valid
*/

QString SignInParameters::serviceName() const
{
    return m_serviceName;
}

/*!
    \qmlproperty string SignInParameters::method
    The name of the method used to authenticate with the service
*/

QString SignInParameters::method() const
{
    return m_method;
}

/*!
    \qmlproperty string SignInParameters::mechanism
    The mechanisms used to authenticate with the service
*/

QString SignInParameters::mechanism() const
{
    return m_mechanism;
}

/*!
    \qmlproperty object SignInParameters::parameters
    The parameters used during authentication with the service.
*/

QVariantMap SignInParameters::parameters() const
{
    return m_parameters;
}

/*!
    \qmlproperty string SignInParameters::username
    The username to be used during authentication with the service.

    This property should only be set during credentials creation;
    subsequent sign-in requests will use the username specified
    during credentials creation only.
*/

QString SignInParameters::username() const
{
    return m_username;
}

/*!
    \qmlproperty string SignInParameters::password
    The password to be used during authentication with the service.
    It is only applicable to services which use password-based
    authentication methods, and does not affect OAuth-based services
    (as these use web-based authentication instead).

    This property should only be set during credentials creation;
    subsequent sign-in requests will use the password specified
    during credentials creation only.
*/

QString SignInParameters::password() const
{
    return m_password;
}

/*!
    \qmlmethod void SignInParameters::setParameter(string parameterName, parameterValue)

    Sets the value of the parameter specified by the given \a parameterName to
    the given \a parameterValue.  This does not affect the method, mechanism,
    username or password parameters.

    Only string, string[], int and bool values are recognised.

    Example:
    \code
    var params = account.signInParameters("facebook-sharing")
    params.setParameter("ClientId", "123456789abcdef")
    // application can now sign in to Facebook with these parameters
    \endcode

    Different services accept different parameters.  Valid parameter names
    may be ascertained by inspecting
    \l {https://docs.sailfishos.org/Reference/Core_Areas_and_APIs/Apps_and_MW/Accounts_and_SSO/Providers_and_Services}
    {account provider} \c{.service} files,
    and some commonly-used parameter names are included below for information
    purposes:

    OAuth-based services using the \c user_agent flow have the following known
    parameter names:
    \list
    \li Host
    \li AuthPath
    \li RedirectUri
    \li Scope
    \li Display ("touch" is a valid value)
    \li ClientId
    \li ClientSecret
    \endlist

    OAuth-based services using the \c HMAC-SHA1 flow have the following known
    parameter names:
    \list
    \li RequestEndpoint
    \li TokenEndpoint
    \li AuthorizationEndpoint
    \li AllowedSchemes
    \li Callback
    \li ConsumerKey
    \li ConsumerSecret
    \endlist

    Generally speaking most of these parameters should be provided by the
    service automatically.  Some, like the \c ClientId or \c ConsumerKey
    parameters MUST be provided by applications performing sign-in.

    Additionally, the "UiPolicy" parameter is applicable for all services,
    and valid values are defined by the \c UiPolicy enumeration, which
    are as follows:
    
    \list
    \li DefaultPolicy - UI may be shown to the user if no cached credentials exist
    \li RequestPasswordPolicy - UI will be shown to the user even if cached credentials exist
    \li NoUserInteractionPolicy - UI will not be shown to the user even if no cached credentials exist.
        The sign in operation will fail unless cached credentials exist.
    \li ValidationPolicy - UI will only be shown to the user if validation (eg, CAPTCHA) is requested by the service
    \endlist
    
    In general, the \c DefaultPolicy should suffice for most use-cases, except
    for sync use-cases (where \c NoUserInteractionPolicy) should generally be
    defined.  For example:

    \code
    var params = account.signInParameters("facebook-sync")
    params.setParameter("ClientId", "123456789abcdef")
    params.setParameter("UiPolicy", SignInParameters.NoUserInteractionPolicy)
    // application can now sign in to Facebook with these parameters
    \endcode

    Further, the "CredentialsPolicy" parameter is applicable for OAuth services.
    The value of this parameter may be:
    \list
    \li UseCachedCredentialsPolicy - sign in will return cached credentials if they exist and have not expired
    \li RefreshCredentialsPolicy - sign in will cause a token refresh to occur even if cached credentials exist
        and have not expired
    \endlist

    Note that the \c UseCachedCredentialsPolicy can still result in a token
    refresh occurring, if the currently cached tokens have expired.
    The \c RefreshCredentialsPolicy should be used if the token has been
    invalidated server-side, and the client application has detected this
    case (due to the error message which is returned from the server).
    For example:

    \code
    var params = account.signInParameters("google-sync")
    params.setParameter("ClientId", "123456789abcdef")
    params.setParameter("ClientSecret", "abcdef123456789")
    params.setParameter("UiPolicy", SignInParameters.NoUserInteractionPolicy)
    params.setParameter("CredentialsPolicy", SignInParameters.RefreshCredentialsPolicy)
    // signing in will return refreshed tokens (if they are able to be refreshed)
    \endcode

    The \c CredentialsPolicy parameter is ignored if the service is not an
    OAuth-enabled service.
*/

void SignInParameters::setParameter(const QString &parameterName, const QVariant &parameterValue)
{
    QVariant value = sanitiseValue(parameterValue);
    if (!value.isValid()) {
        qWarning() << Q_FUNC_INFO << "Cannot store parameter:" << parameterName << "with value" << value;
        return;
    }

    m_parameters.insert(parameterName, value);
    emit parametersChanged();
}

void SignInParameters::setParameter(const QString &parameterName, const QVariantMap &parameterValue)
{
    setParameter(parameterName, QVariant(parameterValue));
}

void SignInParameters::setParameter(const QString &parameterName, const QString &parameterValue)
{
    setParameter(parameterName, QVariant(parameterValue));
}

void SignInParameters::setParameter(const QString &parameterName, const QStringList &parameterValue)
{
    setParameter(parameterName, QVariant(parameterValue));
}

void SignInParameters::setParameter(const QString &parameterName, const QUrl &parameterValue)
{
    setParameter(parameterName, QVariant(parameterValue));
}

void SignInParameters::setParameter(const QString &parameterName, int parameterValue)
{
    setParameter(parameterName, QVariant(parameterValue));
}

void SignInParameters::setParameter(const QString &parameterName, bool parameterValue)
{
    setParameter(parameterName, QVariant(parameterValue));
}

/*!
    \qmlmethod void SignInParameters::removeParameter(string parameterName)

    Unsets the value of the parameter specified by the given \a parameterName.
    This does not affect the method, mechanism, username or password
    parameters.

    Example:
    \code
    var params = account.signInParameters("facebook-sharing")
    params.removeParameter("Scope")
    // no scopes (permissions) will be requested during sign in
    \endcode
*/

void SignInParameters::removeParameter(const QString &parameterName)
{
    if (m_parameters.contains(parameterName)) {
        m_parameters.remove(parameterName);
        emit parametersChanged();
    }
}

/*!
    \qmlmethod void SignInParameters::setParameters(params)

    Removes all existing parameters, and then calls setParameter() for each
    parameter in the specified \a params map.
*/
void SignInParameters::setParameters(const QVariantMap &params)
{
    m_parameters.clear();
    foreach (const QString &parameterName, params.keys()) {
        QVariant value = sanitiseValue(params.value(parameterName));
        if (!value.isValid()) {
            qWarning() << Q_FUNC_INFO << "Cannot store parameter:" << parameterName << "with value" << value;
        } else {
            m_parameters.insert(parameterName, value);
        }
    }
    emit parametersChanged();
}
