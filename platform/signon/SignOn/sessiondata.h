// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation
// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
 * Copyright (C) 2012-2016 Canonical Ltd.
 *
 * Contact: Alberto Mardegan <alberto.mardegan@canonical.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 */
/*!
 * @copyright Copyright (C) 2009-2011 Nokia Corporation.
 * @license LGPL
 */

/*!
 * @todo move this to a common includes folder.
 * This is part of the plugin development kit, too.
 */

#ifndef SESSIONDATA_H
#define SESSIONDATA_H

#include <QMap>
#include <QString>
#include <QStringList>
#include <QVariant>

#include <SignOn/libsignoncommon.h>

namespace SignOn {

/*!
 * A macro to create declarations for parameter setter and getter.
 * This supports the same types as @see QVariant.
 * For user specified types @see QMetaType.
 *
 * @param type_ Type of parameter
 * @param name_ Name of property
 */
#define SIGNON_SESSION_DECLARE_PROPERTY(type_, name_) \
          void set##name_(const type_ &value ) { m_data.insert(QLatin1String(#name_), value); } \
          type_ name_() const { return m_data.value(QLatin1String(#name_)).value<type_>(); }

/*!
 * Property which holds the access control tokens that the requesting
 * application has.
 * @note to be used by the plugins developers only.
 */
#define SSO_ACCESS_CONTROL_TOKENS QLatin1String("AccessControlTokens")

/*!
 * @enum SignonUiPolicy
 * Policy to define how the plugin interacts with the user.
 * This is a hint for plugin how to handle user interaction.
 * NoUserInteractionPolicy does not allow any ui interaction to happen
 * and plugin will get error reply QUERY_ERROR_FORBIDDEN.
 * @see UiPolicy
 */
enum SignonUiPolicy {
    DefaultPolicy = 0,          /**< Plugin can decide when to show ui. */
    RequestPasswordPolicy,      /**< Force user to enter password. */
    NoUserInteractionPolicy,    /**< No ui elements are shown to user. */
    ValidationPolicy,           /**< UI elements can be shown to the user only
                                  when captcha-like security measures are
                                  required */
};

/*!
 * @class SessionData
 * @headerfile sessiondata.h SignOn/SessionData
 *
 * Data container to hold values for authentication session.
 * Inherit this class if you want to extend the property range.
 *
 *
 * @warning All this class' definitions must be inline.
 */
class SIGNON_EXPORT SessionData
{
public:
    /*!
     * Constructor. Creates a SessionData with data 'data'.
     * @param data The data to be contained by the SessionData
     * @attention internal use only recommended. As a SSO client application
     * developer use setters/gettters for specific SessionData properties.
     */
    SessionData(const QVariantMap &data = QVariantMap()) { m_data = data; }

    /*!
     * Copy constructor.
     * @param other SessionData object to be copied to this instance
     */
    SessionData(const SessionData &other) { m_data = other.m_data; }

    /*!
     * Assignment operator
     * @param other SessionData object to be assigned to this instance
     * @return Reference to this object
     */
    SessionData &operator=(const SessionData &other) {
        m_data = other.m_data;
        return *this;
    }

    /*!
     * Addition operator
     * @param other SessionData object to be added to this instance.
     * @return reference to this object
     */
    SessionData &operator+=(const SessionData &other) {
        for (auto it = other.m_data.constBegin(), itEnd = other.m_data.constEnd(); it != itEnd; ++it) {
            m_data[it.key()] = it.value();
        }
        return *this;
    }

    /*!
     * Access the list of runtime existing properties of the SessionData.
     * @return String list containing the property names
     */
    const QStringList propertyNames() const {
        return m_data.keys();
    }

    /*!
     * Access the list of runtime existing properties of the SessionData.
     * @param propertyName Name of the property to be accessed
     * @return Variant containing the property value of propertyName, or an
     * empty variant if property does not exist at runtime.
     */
    const QVariant getProperty(const QString &propertyName) const {
        return m_data.value(propertyName, QVariant());
    }

    /*!
     * Gets the access control tokens that the requesting application has.
     * @note to be used by the plugins developers only.
     */
    QStringList getAccessControlTokens() const {
        return getProperty(SSO_ACCESS_CONTROL_TOKENS).toStringList();
    }

    /*!
     * Creates an instance of type T, which must be derived from SessionData.
     * The instance will contain the data of this instance.
     * @return Instance of type T, containing the data of this instance.
     */
    template <class T> T data() const {
        T dataImpl;
        dataImpl.m_data = m_data;
        return dataImpl;
    }

    /*!
     * Gets the QVariantMap of session parameters.
     * @return A map of the session parameters.
     */
    QVariantMap toMap() const { return m_data; }

    /*!
     * Declares the property Secret setter and getter.
     * setSecret(const QString secret);
     * const QString Secret() const;
     */
    SIGNON_SESSION_DECLARE_PROPERTY(QString, Secret)

    /*!
     * Declares the property UserName setter and getter.
     */
    SIGNON_SESSION_DECLARE_PROPERTY(QString, UserName)

    /*!
     * Declares the property Realm setter and getter.
     * Realm that is used for authentication.
     */
    SIGNON_SESSION_DECLARE_PROPERTY(QString, Realm)

    /*!
     * Declares the property NetworkProxy setter and getter.
     * Network proxy to be used instead of system default.
     */
    SIGNON_SESSION_DECLARE_PROPERTY(QString, NetworkProxy)

    /*!
     * Declares the property UiPolicy setter and getter.
     * Use UiPolicy to define how plugin interacts with the user.
     * @see SignonUiPolicy
     */
    SIGNON_SESSION_DECLARE_PROPERTY(int, UiPolicy)

    /*!
     * Declares the property Caption setter and getter.
     * Caption is to tell user which application/credentials/provider is
     * requesting signon-ui.
     *
     * @note Caption is taken from database if not defined by application
     * or authentication plugin.
     */
    SIGNON_SESSION_DECLARE_PROPERTY(QString, Caption)

    /*!
     * Declares the property NetworkTimeout setter and getter.
     * Sets the timeout for network related operations in milliseconds.
     * To be used when a remote service does not reply in a reasonable amount
     * of time.
     */
    SIGNON_SESSION_DECLARE_PROPERTY(quint32, NetworkTimeout)

    /*!
     * Declares the property WindowId setter and getter.
     * This is to be used for setting signon-ui dialog application modal.
     */
    SIGNON_SESSION_DECLARE_PROPERTY(quint32, WindowId)

    /*!
     * Declares the property RenewToken setter and getter.
     * This is used by a signon plugin to check whether
     * the access token has to be renewed. When this
     * property is set, the signon plugin will remove the
     * old set of access tokens and get a new set.
     */
    SIGNON_SESSION_DECLARE_PROPERTY(bool, RenewToken)

protected:
    QVariantMap m_data;
};

} //namespace SignOn

Q_DECLARE_METATYPE(SignOn::SessionData)
#endif // SESSIONDATA_H
