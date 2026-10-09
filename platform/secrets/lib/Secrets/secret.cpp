// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/secret.h"
#include "Secrets/secret_p.h"

using namespace Sailfish::Secrets;

//--------------------------------------------

SecretIdentifierPrivate::SecretIdentifierPrivate()
    : QSharedData()
{
}

SecretIdentifierPrivate::SecretIdentifierPrivate(const SecretIdentifierPrivate &other)
    : QSharedData(other)
    , m_name(other.m_name)
    , m_collectionName(other.m_collectionName)
    , m_storagePluginName(other.m_storagePluginName)
{
}


SecretIdentifierPrivate::~SecretIdentifierPrivate()
{
}

//--------------------------------------------

SecretPrivate::SecretPrivate()
    : QSharedData()
{
}

SecretPrivate::SecretPrivate(const SecretPrivate &other)
    : QSharedData(other)
    , m_filterData(other.m_filterData)
    , m_identifier(other.m_identifier)
    , m_data(other.m_data)
{
}

SecretPrivate::~SecretPrivate()
{
}

//--------------------------------------------

/*!
  \class Secret::Identifier
  \brief An identifier for a secret
  \inmodule SailfishSecrets
  \inheaderfile Secrets/secret.h

  The identifier consists of the name (alias) of the secret, along with
  the name of the collection in which the secret is stored (note that the
  collection name can be empty if the secret is stored as a standalone
  secret) and the name of the storage plugin which stores the collection.

  Together, the secret name, collection name and storage plugin name
  uniquely identify the secret in the secrets storage.
 */

/*!
  \brief Constructs a new, empty identifier
 */
Secret::Identifier::Identifier()
    : d_ptr(new SecretIdentifierPrivate)
{
}

/*!
  \brief Constructs a new identifier from the given secret \a name, \a collectionName and \a storagePluginName
 */
Secret::Identifier::Identifier(const QString &name, const QString &collectionName, const QString &storagePluginName)
        : d_ptr(new SecretIdentifierPrivate)
{
    d_ptr->m_name = name;
    d_ptr->m_collectionName = collectionName;
    d_ptr->m_storagePluginName = storagePluginName;
}

/*!
  \brief Constructs a copy of the \a other identifier
 */
Secret::Identifier::Identifier(const Secret::Identifier &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Destroys the identifier
 */
Secret::Identifier::~Identifier()
{
}

/*!
  \brief Assigns the \a other identifier to this identifier
 */
Secret::Identifier& Secret::Identifier::operator=(const Secret::Identifier &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \brief Returns true if the secret name is not empty

  Note that this doesn't mean that the identifier does in fact identify
  a valid secret stored by the system secrets service; rather, it means
  that if a secret with that name does exist, then this identifier
  would identify it.
 */
bool Secret::Identifier::isValid() const
{
    return !d_ptr->m_name.isEmpty() && !d_ptr->m_storagePluginName.isEmpty();
}

/*!
  \brief Returns true if the collection name is empty

  A standalone secret is a secret which is not stored in a collection,
  but instead is stored "standalone".

  Note that standalone secrets are usually less-secure than collection
  stored secrets, as they are likely to be stored in a database which
  is not block-level encrypted.
 */
bool Secret::Identifier::identifiesStandaloneSecret() const
{
    return d_ptr->m_collectionName.isEmpty();
}

/*!
  \brief Returns the secret name from the identifier
 */
QString Secret::Identifier::name() const
{
    return d_ptr->m_name;
}

/*!
  \brief Sets the secret name in the identifier to \a name
 */
void Secret::Identifier::setName(const QString &name)
{
    d_ptr->m_name = name;
}

/*!
  \brief Returns the collection name from the identifier
 */
QString Secret::Identifier::collectionName() const
{
    return d_ptr->m_collectionName;
}

/*!
  \brief Sets the collection name in the identifier to \a collectionName
 */
void Secret::Identifier::setCollectionName(const QString &collectionName)
{
    d_ptr->m_collectionName = collectionName;
}

/*!
  \brief Returns the storage plugin name from the identifier
 */
QString Secret::Identifier::storagePluginName() const
{
    return d_ptr->m_storagePluginName;
}

/*!
  \brief Sets the storage plugin name in the identifier to \a storagePluginName
 */
void Secret::Identifier::setStoragePluginName(const QString &storagePluginName)
{
    d_ptr->m_storagePluginName = storagePluginName;
}

//--------------------------------------------

/*!
  \qmltype Secret
  \inqmlmodule Sailfish.Secrets
  \brief An instance of a secret
*/

/*!
  \class Secret
  \brief An instance of a secret
  \inmodule SailfishSecrets
  \inheaderfile Secrets/secret.h

  The Secret class encapsulates a piece of data stored by an application
  with the system secrets storage service.  Each secret is identified by
  its name (alias) along with the name of the collection in which the
  secret is stored (the collection name is optional if the secret is
  stored standalone).
 */

/*!
  \brief Constructs an empty secret with an unknown type
 */
Secret::Secret()
    : d_ptr(new SecretPrivate)
{
    setType(TypeUnknown);
}

/*!
  \brief Constructs a copy of the \a other secret
 */
Secret::Secret(const Secret &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Constructs a secret which references a secret stored in the given \a storagePlugin with the given \a name from the given \a collection.
 */
Secret::Secret(const QString &name, const QString &collection, const QString &storagePlugin)
    : d_ptr(new SecretPrivate)
{
    setIdentifier(Secret::Identifier(name, collection, storagePlugin));
    setType(TypeUnknown);
}

/*!
  \brief Constructs a secret which references a stored secret with the given \a ident
 */
Secret::Secret(const Secret::Identifier &ident)
    : d_ptr(new SecretPrivate)
{
    setIdentifier(ident);
    setType(TypeUnknown);
}

/*!
  \brief Constructs a secret from the given secret data \a blob tagged with the given \a filterData
 */
Secret::Secret(const QByteArray &blob, const Secret::FilterData &filterData)
    : d_ptr(new SecretPrivate)
{
    setFilterData(filterData);
    setData(blob);
    setType(TypeBlob);
}

/*!
  \brief Destroys the secret
 */
Secret::~Secret()
{
}

/*!
  \brief Assigns the \a other secret to this secret
 */
Secret& Secret::operator=(const Secret &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \qmlproperty string Secret::type
  \brief The type of the secret
*/

/*!
  \brief Returns the type of the secret

  This metadata is informational only, and doesn't affect its storage.
 */
QString Secret::type() const
{
    return d_ptr->m_filterData.value(FilterDataFieldType, TypeUnknown);
}

/*!
  \brief Sets the type of the secret to the given \a type
 */
void Secret::setType(const QString &type)
{
    d_ptr->m_filterData.insert(FilterDataFieldType, type);
}

/*!
  \brief Returns the identifier of the secret
 */
Secret::Identifier Secret::identifier() const
{
    return d_ptr->m_identifier;
}

/*!
  \brief Sets the identifier of the secret to the given \a identifier
 */
void Secret::setIdentifier(const Secret::Identifier &identifier)
{
    d_ptr->m_identifier = identifier;
}

/*!
  \qmlproperty string Secret::name
  \brief The name field from the identifier of the secret
*/

/*!
  \brief Returns the name field from the identifier of the secret
 */
QString Secret::name() const
{
    return d_ptr->m_identifier.name();
}

/*!
  \brief Sets the name field in the identifier of the secret to \a name
 */
void Secret::setName(const QString &name)
{
    d_ptr->m_identifier.setName(name);
}

/*!
  \qmlproperty string Secret::collectionName
  \brief The collection name field from the identifier of the secret
*/

/*!
  \brief Returns the collection name field from the identifier of the secret
 */
QString Secret::collectionName() const
{
    return d_ptr->m_identifier.collectionName();
}

/*!
  \brief Sets the collection name field in the identifier of the secret to \a cname
 */
void Secret::setCollectionName(const QString &cname)
{
    d_ptr->m_identifier.setCollectionName(cname);
}

/*!
  \qmlproperty string Secret::storagePluginName
  \brief The storage plugin name field from the identifier of the secret
*/

/*!
  \brief Returns the storage plugin name field from the identifier of the secret
 */
QString Secret::storagePluginName() const
{
    return d_ptr->m_identifier.storagePluginName();
}

/*!
  \brief Sets the storage plugin name field in the identifier of the secret to \a pname
 */
void Secret::setStoragePluginName(const QString &pname)
{
    d_ptr->m_identifier.setStoragePluginName(pname);
}

/*!
  \qmlproperty ArrayBuffer Secret::data
  \brief This is the data which will be stored securely by the secrets service
*/

/*!
  \brief Returns the secret data from the secret

  This is the data which will be stored securely by the secrets service
 */
QByteArray Secret::data() const
{
    return d_ptr->m_data;
}

/*!
  \brief Sets the secret data in the secret to \a data
 */
void Secret::setData(const QByteArray &data)
{
    d_ptr->m_data = data;
}

/*!
  \brief Returns the filter data associated with the secret

  This filter data may be used by other clients to find the secret
 */
Secret::FilterData Secret::filterData() const
{
    return d_ptr->m_filterData;
}

/*!
  \brief Sets the filter data associated with the secret to \a filterData
 */
void Secret::setFilterData(const Secret::FilterData &filterData)
{
    d_ptr->m_filterData = filterData;
}

/*!
  \qmlproperty array Secret::filterDataFields
  \brief Returns the fields (keys) of filter data associated with the secret
*/

/*!
  \brief Returns the fields (keys) of filter data associated with the secret
 */
QStringList Secret::filterDataFields() const
{
    return d_ptr->m_filterData.keys();
}

/*!
  \qmlmethod string Secret::filterData(string field)
  \brief Returns the filter data value associated with the secret for the given filter \a field
*/

/*!
  \brief Returns the filter data value associated with the secret for the given filter \a field
 */
QString Secret::filterData(const QString &field) const
{
    return d_ptr->m_filterData.value(field);
}

/*!
  \qmlmethod void Secret::setFilterData(string field, string value)
  \brief Sets the filter data value associated with the secret for the given filter \a field to \a value
*/

/*!
  \brief Sets the filter data value associated with the secret for the given filter \a field to \a value
 */
void Secret::setFilterData(const QString &field, const QString &value)
{
    d_ptr->m_filterData.insert(field, value);
}

/*!
  \qmlmethod bool Secret::hasFilterData(string field)
  \brief Returns true if the secret has filter data associated with it for the given filter \a field
*/

/*!
  \brief Returns true if the secret has filter data associated with it for the given filter \a field
 */
bool Secret::hasFilterData(const QString &field) const
{
    return d_ptr->m_filterData.contains(field);
}

/*!
  \brief Returns true if the \a lhs identifier consists of the same name and collection name as the \a rhs identifier
 */
bool Sailfish::Secrets::operator==(const Secret::Identifier &lhs, const Secret::Identifier &rhs)
{
    return lhs.collectionName() == rhs.collectionName()
            && lhs.name() == rhs.name();
}

/*!
  \brief Returns false if the \a lhs identifier consists of the same name and collection name as the \a rhs identifier
 */
bool Sailfish::Secrets::operator!=(const Secret::Identifier &lhs, const Secret::Identifier &rhs)
{
    return !operator==(lhs, rhs);
}

/*!
  \brief Returns true if the \a lhs identifier should sort as less than the \a rhs identifier
 */
bool Sailfish::Secrets::operator<(const Secret::Identifier &lhs, const Secret::Identifier &rhs)
{
    if (lhs.collectionName() != rhs.collectionName())
        return lhs.collectionName() < rhs.collectionName();
    return lhs.name() < rhs.name();
}

/*!
  \brief Returns true if the \a lhs secret is equal to the \a rhs secret
 */
bool Sailfish::Secrets::operator==(const Secret &lhs, const Secret &rhs)
{
    return lhs.identifier() == rhs.identifier()
            && lhs.data() == rhs.data()
            && lhs.filterData() == rhs.filterData();
}

/*!
  \brief Returns false if the \a lhs secret is equal to the \a rhs secret
 */
bool Sailfish::Secrets::operator!=(const Secret &lhs, const Secret &rhs)
{
    return !operator==(lhs, rhs);
}

/*!
  \brief Returns true if the \a lhs secret should sort as less than the \a rhs secret
 */
bool Sailfish::Secrets::operator<(const Secret &lhs, const Secret &rhs)
{
    if (lhs.type() != rhs.type())
        return lhs.type() < rhs.type();

    if (lhs.data() != rhs.data())
        return lhs.data() < rhs.data();

    return lhs.filterData().size() < rhs.filterData().size();
}
