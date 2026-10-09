// SPDX-FileCopyrightText: 2009-2010 Nokia Corporation
// SPDX-FileCopyrightText: 2011-2016 Canonical Ltd
// SPDX-FileCopyrightText: 2009-2011 Nokia Corporation
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of signon
 *
 * Copyright (C) 2009-2010 Nokia Corporation.
 * Copyright (C) 2011-2016 Canonical Ltd.
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

#ifndef IDENTITY_INFO_H
#define IDENTITY_INFO_H

#include <QMetaType>
#include <QStringList>

#include "libsignoncommon.h"
#include "securitycontext.h"

namespace SignOn {

/*!
 * @typedef QString MethodName
 * Defines a string as an authentication method.
 */
typedef QString MethodName;

/*!
 * @typedef QStringList MechanismsList
 * Defines a string list as a list of mechanisms.
 */
typedef QStringList MechanismsList;

/*!
 * @typedef QList<SecurityContext> SecurityContextList
 * Defines a list of security contexts.
 */
typedef QList<SecurityContext> SecurityContextList;

/*!
 * @class IdentityInfo
 * @headerfile identityinfo.h SignOn/IdentityInfo
 *
 * Contains identity information. This information is stored into database.
 * @see queryIdentities()
 */
class SIGNON_EXPORT IdentityInfo
{
    friend class AuthServiceImpl;
    friend class IdentityImpl;

public:
    /*!
     * @enum CredentialsType
     * Values used to describe the type of the identity
     * @attention Mixed types, i.e Application|Web are not yet supported. Just
     * single types work for the time being.
     */
    enum CredentialsType {
        Other = 0,
        Application = 1 << 0,
        Web = 1 << 1,
        Network = 1 << 2
    };

public:
    /*!
     * Creates a new empty IdentityInfo object.
     */
    IdentityInfo();

    /*!
     * Copy constructor
     */
    IdentityInfo(const IdentityInfo &other);

    /*!
     * Assignment operator
     */
    IdentityInfo &operator=(const IdentityInfo &other);

    /*!
     * Creates a new IdentityInfo object with given values.
     * @param caption Description of identity
     * @param userName Username
     * @param methods Allowed methods for identity
     */
    IdentityInfo(const QString &caption, const QString &userName,
                 const QMap<MethodName,MechanismsList> &methods);

    /*!
     * Destructor
     */
    ~IdentityInfo();

    /*!
     * Sets the numeric identifier for the credentials record.
     * Calling this method makes only sense when handling the
     * Identity::credentialsStored() signal.
     * @param id The numeric identifier of the credentials.
     */
    void setId(const quint32 id);

    /*!
      * Returns the identity identifier.
      * @return Identifier for the identity
      */
    quint32 id() const;

    /*!
     * Sets the secret. When performing a challenge on the owner Identity object,
     * if the secret is set on its corresponding IdentityInfo, it will be added
     * to the parameter list that is passed to the corresponding authentication
     * plugin challenge implementation. By default a newly created IdentityInfo
     * does not contain a secret and has a policy of not storing any. If the
     * secret is set the default policy will be to store it. This behaviour can
     * also be set with IdentityInfo::setStoreSecret().
     *
     * @see PluginInterface::secretKey
     * @see PluginInterface::challenge
     * @param secret
     * @param storeSecret Whether the secret is stored or not
     */
    void setSecret(const QString &secret, const bool storeSecret = true);

    /*!
     * Gets the secret. If this object was retrieved from the database, the
     * returned secret might be an empty string.
     * @return The secret, when allowed, or an empty string.
     */
    QString secret() const;

    /*!
     * Returns whether secret is to be stored.
     * @return true Whether the secret is being stored or not.
     */
    bool isStoringSecret() const;

    /*!
     * Sets whether the secret is stored or not.
     * @param storeSecret Whether the secret must be stored in the DB.
     */
    void setStoreSecret(const bool storeSecret);

    /*!
     * Sets the username.
     *
     * @see userNameKey
     * @param userName Username
     */
    void setUserName(const QString &userName);

    /*!
     * Returns the username.
     * @return Username for the identity
     */
    const QString userName() const;

    /*!
     * Sets a human readable caption of the identity
     * @param caption Caption
     */
    void setCaption(const QString &caption);

    /*!
     * Returns a human-readable representation of the identity.
     * @return Human-readable representation of the identity.
     */
    const QString caption() const;

    /*!
     * Sets the realms, e.g. URL's with which the Identity using this
     * IdentityInfo shall work with.
     *
     * @param realms List of the realms to be set.
     */
    void setRealms(const QStringList &realms);

    /*!
     * Gets the realms, e.g. URL's with which the Identity using this
     * IdentityInfo works with.
     *
     * @return List of supported realms.
     */
    QStringList realms() const;

    /*!
     * Sets application token that owns identity, therefore defining the
     * applications that will be able to modify this specific set of credentials
     *
     * @param ownerToken owner token
     */
    void setOwner(const QString &ownerToken);

    /*!
     * Gets the owner application token that is defining the applications
     * that are able to modify this specific set of credentials.
     *
     * @attention This is accessible only to the owner application.
     *
     * @return The access control token which defines the applications
     * allowed to modify this set of credentials.
     */
    QString owner() const;

    /*!
     * Sets the list of access control system tokens, therefore
     * defining the applications that will be able to access this specific
     * set of credentials.
     *
     * @param accessControlList List of access control system tokens
     */
    void setAccessControlList(const QStringList &accessControlList);

    /*!
     * Sets the list of access control tokens, therefore defining the
     * applications that will be able to access this specific set of
     * credentials.
     *
     * @param accessControlList List of access control tokens
     */
    void setAccessControlList(const SecurityContextList &accessControlList);

    /*!
     * Gets the list of access control system tokens defining the
     * applications that are able to access this specific set of credentials.
     *
     * @attention This is accessible only to the owner application.
     *
     * @return The access control system tokens which defines the
     * applications allowed to access this set of credentials.
     */
    QStringList accessControlList() const;

    /*!
     * Gets the list of access control application tokens defining the
     * applications that are able to access this specific set of credentials.
     *
     * @attention This is accessible only to the owner application.
     *
     * @return The access control tokens which defines the applications allowed
     * to access this set of credentials.
     */
    SecurityContextList accessControlListFull() const;

    /*!
     * Sets the method into identity info.
     * If the given method is not included, a new one will be added. If it is
     * already set, the mechanism list assosiated to it is updated. an empty
     * list will clear the mechanisms.
     * These values are used to limit Identity to use the specified methods and
     * mechanisms.
     * @param method Method name to change
     * @param mechanismsList list of mechanisms that are allowed
     */
    void setMethod(const MethodName &method,
                   const MechanismsList &mechanismsList);

    /*!
     * Removes a method from identity info.
     * @param method Method name to remove
     */
    void removeMethod(const MethodName &method);

    /*!
     * Sets the type into identity info.
     * The type is used to generically identify where this identity is being
     * used.
     *
     * @attention If this method is not called, the IdentityInfo type will
     * default to SignOn::OtherIdentity.
     *
     * @param type Type we want to assign to this IdentityInfo
     */
    void setType(CredentialsType type);

    /*!
     * Retrieves the identity type from identity info.
     * @return The identity type for this IdentityInfo
     */
    CredentialsType type() const;

    /*!
     * Lists all methods in identity info.
     * @return Param method method name to remove.
     */
    QList<MethodName> methods() const;

    /*!
     * Lists the all mechanisms for certain method in identity info.
     * @param method Method name to list mechanisms
     * @return List of mechanisms
     */
    MechanismsList mechanisms(const MethodName &method) const;

    /*!
     * Sets the refcount into identity info.
     * The type is used to generically identify where this identity is being
     * used.
     *
     * @note Server can restrict changes to differ +-1 from previous.
     *
     * @param refCount Set refcount
     */
    void setRefCount(qint32 refCount);

    /*!
     * Retrieves the refcount from identity info.
     * @return Refcount for this IdentityInfo
     */
    qint32 refCount() const;

private:
    class IdentityInfoImpl *impl;
};

}  // namespace SignOn

Q_DECLARE_METATYPE(SignOn::IdentityInfo)

#endif /* IDENTITY_INFO_H */
