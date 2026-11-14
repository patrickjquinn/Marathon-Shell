// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/key.h"
#include "Crypto/key_p.h"

#define SAILFISH_SECRETS_SECRET_FILTERDATAFIELDTYPE QLatin1String("Type")
#define SAILFISH_SECRETS_SECRET_TYPECRYPTOKEY QLatin1String("CryptoKey")

using namespace Sailfish::Crypto;

//--------------------------------------------

KeyIdentifierPrivate::KeyIdentifierPrivate()
    : QSharedData()
{
}

KeyIdentifierPrivate::KeyIdentifierPrivate(const KeyIdentifierPrivate &other)
    : QSharedData(other)
    , m_name(other.m_name)
    , m_collectionName(other.m_collectionName)
    , m_storagePluginName(other.m_storagePluginName)
{
}


KeyIdentifierPrivate::~KeyIdentifierPrivate()
{
}

//--------------------------------------------

KeyPrivate::KeyPrivate()
    : QSharedData()
    , m_origin(Key::OriginUnknown)
    , m_algorithm(CryptoManager::AlgorithmUnknown)
    , m_operations(CryptoManager::OperationUnknown)
    , m_componentConstraints(Key::MetaData | Key::PublicKeyData)
    , m_size(0)
{
    m_filterData.insert(SAILFISH_SECRETS_SECRET_FILTERDATAFIELDTYPE, SAILFISH_SECRETS_SECRET_TYPECRYPTOKEY);
}

KeyPrivate::KeyPrivate(const KeyPrivate &other)
    : QSharedData(other)
    , m_filterData(other.m_filterData)
    , m_customParameters(other.m_customParameters)
    , m_publicKey(other.m_publicKey)
    , m_privateKey(other.m_privateKey)
    , m_secretKey(other.m_secretKey)
    , m_identifier(other.m_identifier)
    , m_origin(other.m_origin)
    , m_algorithm(other.m_algorithm)
    , m_operations(other.m_operations)
    , m_componentConstraints(other.m_componentConstraints)
    , m_size(other.m_size)
{
}

KeyPrivate::~KeyPrivate()
{
}

//--------------------------------------------

/*!
  \class Key::Identifier
  \brief An identifier for a key
  \inmodule SailfishCrypto
  \inheaderfile Crypto/key.h

  The identifier consists of the name (alias) of the key, along with
  the name of the collection in which the key is stored (note that the
  collection name can be empty if the key is stored as a standalone
  secret) and the plugin which stores that collection.

  Together, the key name, collection name and storage plugin name uniquely
  identify the key as a specific secret in the secrets storage.
 */

/*!
  \brief Constructs a new, empty identifier
 */
Key::Identifier::Identifier()
    : d_ptr(new KeyIdentifierPrivate)
{
}

/*!
  \brief Constructs a new identifier from the given key \a name, \a collectionName and \a storagePluginName
 */
Key::Identifier::Identifier(const QString &name, const QString &collectionName, const QString &storagePluginName)
        : d_ptr(new KeyIdentifierPrivate)
{
    d_ptr->m_name = name;
    d_ptr->m_collectionName = collectionName;
    d_ptr->m_storagePluginName = storagePluginName;
}

/*!
  \brief Constructs a copy of the \a other identifier
 */
Key::Identifier::Identifier(const Key::Identifier &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Destroys the identifier
 */
Key::Identifier::~Identifier()
{
}

/*!
  \brief Assigns the \a other identifier to this identifier
 */
Key::Identifier& Key::Identifier::operator=(const Key::Identifier &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \brief Returns true if the key identifier consists of valid, non-empty components

  Note that this doesn't mean that the identifier does in fact identify
  a valid key stored by the system secrets service; rather, it means
  that if a key with the name() specified in this identifier is stored
  in a collection with the collectionName() specified in this identifier
  by the storage (or crypto storage) plugin identified by the storagePluginName()
  specified in this identifier, then this identifier would identify it.

  That is, if either name() or collectionName() or storagePluginName() is
  empty, the identifier is not considered valid.
 */
bool Key::Identifier::isValid() const
{
    return !d_ptr->m_name.isEmpty()
            && !d_ptr->m_collectionName.isEmpty()
            && !d_ptr->m_storagePluginName.isEmpty();
}

/*!
  \brief Returns the key name from the identifier
 */
QString Key::Identifier::name() const
{
    return d_ptr->m_name;
}

/*!
  \brief Sets the key name in the identifier to \a name
 */
void Key::Identifier::setName(const QString &name)
{
    d_ptr->m_name = name;
}

/*!
  \brief Returns the collection name from the identifier
 */
QString Key::Identifier::collectionName() const
{
    return d_ptr->m_collectionName;
}

/*!
  \brief Sets the collection name in the identifier to \a collectionName
 */
void Key::Identifier::setCollectionName(const QString &collectionName)
{
    d_ptr->m_collectionName = collectionName;
}

/*!
  \brief Returns the storage plugin name from the identifier
 */
QString Key::Identifier::storagePluginName() const
{
    return d_ptr->m_storagePluginName;
}

/*!
  \brief Sets the storage plugin name in the identifier to \a storagePluginName
 */
void Key::Identifier::setStoragePluginName(const QString &storagePluginName)
{
    d_ptr->m_storagePluginName = storagePluginName;
}

//--------------------------------------------

/*!
  \qmltype Key
  \brief An instance of a key which can be used for cryptographic operations.
  \inqmlmodule Sailfish.Crypto
  \instantiates Sailfish::Crypto::Key
*/

/*!
  \class Key
  \brief An instance of a key which can be used for cryptographic operations.
  \inmodule SailfishCrypto
  \inheaderfile Crypto/key.h

  The Key class encapsulates information about a
  cryptographic key, including metadata such as the cryptosystem algorithm
  the key is used with, the types of operations which may be performed
  with the key, and the parameters which are supported when performing
  operations with the key, as well as key data (private/public key data
  for asymmetric cryptosystems, and secret key data for symmetric cryptosystems).

  In many cases, client applications need never know the key data, as the
  key can be generated and stored securely, and then used securely by name reference,
  without the key data ever entering the client application process address space.

  See \l{GenerateStoredKeyRequest} for more information about securely generating
  a key which is stored by the system service, and see \a {GenerateKeyRequest} for
  more information about generating a key which is returned to the application.
 */

/*!
  \brief Constructs an empty key
 */
Key::Key()
    : d_ptr(new KeyPrivate)
{
}

/*!
  \brief Constructs a copy of the \a other key
 */
Key::Key(const Key &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Constructs a key which references a stored key with the given
  \a name from the given \a collection in the storage plugin with the
  given \a storagePluginName.

  A stored key is one which is stored securely by the Sailfish Crypto daemon,
  whose underlying secret data (e.g. private key or secret key data) will never
  be exposed to the client process.
 */
Key::Key(const QString &name, const QString &collection, const QString &storagePluginName)
    : d_ptr(new KeyPrivate)
{
    setIdentifier(Key::Identifier(name, collection, storagePluginName));
}

/*!
  \brief Destroys the key
 */
Key::~Key()
{
}

/*!
  \brief Assigns the \a other key to this key, and returns a reference to this key
 */
Key& Key::operator=(const Key &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \brief Returns the identifier of the stored key which this key references
 */
Key::Identifier Key::identifier() const
{
    return d_ptr->m_identifier;
}

/*!
  \brief Sets the identifier of the stored key which this key references to the given \a identifier
 */
void Key::setIdentifier(const Key::Identifier &identifier)
{
    d_ptr->m_identifier = identifier;
}

/*!
  \qmlproperty string Key::name
  \brief The name field from the identifier of the key
*/

/*!
  \brief Returns the name field from the identifier of the key
 */
QString Key::name() const
{
    return d_ptr->m_identifier.name();
}

/*!
  \brief Sets the name field in the identifier of the key to \a name
 */
void Key::setName(const QString &name)
{
    d_ptr->m_identifier.setName(name);
}

/*!
  \qmlproperty string Key::collectionName
  \brief The collection name field from the identifier of the key
*/

/*!
  \brief Returns the collection name field from the identifier of the key
 */
QString Key::collectionName() const
{
    return d_ptr->m_identifier.collectionName();
}

/*!
  \brief Sets the collection name field in the identifier of the key to \a cname
 */
void Key::setCollectionName(const QString &cname)
{
    d_ptr->m_identifier.setCollectionName(cname);
}

/*!
  \qmlproperty string Key::storagePluginName
  \brief The storage plugin name field from the identifier of the key
*/

/*!
  \brief Returns the storage plugin name field from the identifier of the key
 */
QString Key::storagePluginName() const
{
    return d_ptr->m_identifier.storagePluginName();
}

/*!
  \brief Sets the storage plugin name field in the identifier of the key to \a pname
 */
void Key::setStoragePluginName(const QString &pname)
{
    d_ptr->m_identifier.setStoragePluginName(pname);
}

/*!
  \qmlproperty enumeration Key::origin
  \brief Ynformation about the origin of the key
  \value OriginUnknown
  \value OriginImported
  \value OriginDevice
  \value OriginSecureDevice
*/

/*!
  \brief Returns information about the origin of the key
 */
Key::Origin Key::origin() const
{
    return d_ptr->m_origin;
}

/*!
  \brief Sets origin information for the key to the given \a origin
 */
void Key::setOrigin(Key::Origin origin)
{
    d_ptr->m_origin = origin;
}

/*!
  \qmlproperty enumeration Key::algorithm
  \brief the cryptosystem algorithm this key is intended to be used with
  \value AlgorithmUnknown
  \value AlgorithmCustom
  \value AlgorithmRsa
  \value AlgorithmDsa
  \value AlgorithmDh
  \value AlgorithmEc
  \value AlgorithmEcDsa
  \value AlgorithmEdDsa
  \value AlgorithmEcDh
  \value AlgorithmEcMqv
  \value AlgorithmAes
  \value AlgorithmGost
  \value AlgorithmTdea
  \value AlgorithmTdes  = AlgorithmTdea
  \value AlgorithmBlowfish
  \value AlgorithmSalsa
  \value AlgorithmSalsa20 = AlgorithmSalsa
  \value AlgorithmChaCha
  \value AlgorithmChaCha20 = AlgorithmChaCh
  \value AlgorithmRc4
  \value AlgorithmRc5
  \value AlgorithmRc6
  \value AlgorithmSquare
  \value AlgorithmSerpent
  \value AlgorithmPanama
*/

/*!
  \brief Returns the cryptosystem algorithm this key is intended to be used with
 */
CryptoManager::Algorithm Key::algorithm() const
{
    return d_ptr->m_algorithm;
}

/*!
  \brief Sets the cryptosystem algorithm this key is intended to be used with to \a algorithm
 */
void Key::setAlgorithm(CryptoManager::Algorithm algorithm)
{
    d_ptr->m_algorithm = algorithm;
}

/*!
  \qmlproperty flags Key::operations
  \brief The set of operations which are supported for this key
  \value OperationUnknown
  \value OperationCustom
  \value OperationSign
  \value OperationVerify
  \value OperationEncrypt
  \value OperationDecrypt
  \value OperationCalculateDigest
  \value OperationCalculateMac
  \value OperationDeriveKey
*/

/*!
  \brief Returns the set of operations which are supported for this key
 */
CryptoManager::Operations Key::operations() const
{
    return d_ptr->m_operations;
}

/*!
  \brief Sets the operations which are supported for this key to \a operations

  This should generally only be called by the client when specifying a template
  key as a parameter to a \l{GenerateStoredKeyRequest}.

  Some crypto storage plugins will enforce these as constraints, so that a
  key whose operations contains only \l{CryptoManager::OperationSign} and
  \l{CryptoManager::OperationVerify} will not be able to be used in
  encryption or decryption operations, for example.

  Please see the documentation for the crypto plugin you intend to use, for
  more information about whether it enforces such constraints.
 */
void Key::setOperations(CryptoManager::Operations operations)
{
    d_ptr->m_operations = operations;
}

/*!
  \qmlproperty flags Key::componentConstraints
  \brief The types of key components which the client is allowed to retrieve after the key has been stored
  \value NoData
  \value MetaData
  \value PublicKeyData
  \value PrivateKeyData
  \value SecretKeyData   = PrivateKeyData
*/


/*!
  \brief Returns the types of key components which the client is allowed to retrieve after the key has been stored
 */
Key::Components Key::componentConstraints() const
{
    return d_ptr->m_componentConstraints;
}

/*!
  \brief Sets the types of key components which the client is allowed to retrieve after the key has been stored to \a components

  This should generally only be called by the client when specifying a template
  key as a parameter to a \l{GenerateStoredKeyRequest}.  Clients are only able
  to retrieve the key components specified in the componentsConstraints() after
  the key has been stored.

  When a key is generated and stored, the client can specify constraints which
  should be enforced by the crypto storage plugin in which the key is stored.
  This allows the client to specify, for example, that no client (including
  itself) is allowed to retrieve the secret key data from the key, after the
  key has been stored, to ensure the security of the key is maintained.

  By default, only Key::MetaData and Key::PublicKeyData are included in the
  components constraints, and so any secret or private key data will NOT
  be able to be read back by clients, if the key is stored in a crypto plugin
  which enforces key component constraints.

  Note that only crypto storage plugins (that is, any plugin which implements both
  the Sailfish::Crypto::CryptoPlugin and the Sailfish::Secrets::EncryptedStoragePlugin
  interfaces) can enforce these key component constraints.  If the key is stored
  in any other type of storage plugin (e.g. a Sailfish::Secrets::StoragePlugin)
  then the key component constraints will not be enforced.

  Also note that whether the crypto storage plugin enforces the constraint or not
  is up to the plugin.  Please see the documentation for the plugin you intend
  to use, to see if it supports enforcing key component constraints.
 */
void Key::setComponentConstraints(Key::Components components)
{
    d_ptr->m_componentConstraints = components;
}

/*!
  \qmlproperty int Key::size
  \brief The security size, in bits, of the key.
*/

/*!
  \brief Returns the security size, in bits, of the key.

  Note that this will NOT necessarily be the data size of any of
  the key fields, depending on the type of algorithm the key
  is designed to be used for.

  For symmetric algorithm keys, the security size is generally also
  the data size (in bits) of the secret key.

  For asymmetric keys, the security size is generally the size
  of the modulus (in the case of RSA keys) or the curve group
  size (in the case of ECC keys), and the actual data size of
  the private and public key data may be much larger (for example,
  the private key data for an RSA key could include modulus,
  public exponent, private exponent, prime factors, reduced modulo
  factors, and inverse factor modulo, in order to avoid having to
  recalculate those pieces of data at every use - which altogether
  adds up to a much larger data size than the security size).

  As such, an RSA key with a security size of 2048 bits could
  have a data (storage) size of 1232 bytes (in PKCS#8 format).
 */
int Key::size() const
{
    return d_ptr->m_size;
}

/*!
  \brief Sets the security size, in bits, of the key to \a size

  Clients should call this when generating a key (either via
  GenerateKeyRequest or GeneratedStoredKeyRequest).

  Note that if the client also passes KeyDerivationParameters
  to such a request, the size specified here will be ignored, in
  favour of the output key size specified in those parameters.

  If no valid symmetric key derivation parameters are passed to
  the request, then the crypto plugin will generate a key appropriate
  for the specified algorithm according to this size (for symmetric
  algorithms, this means that the plugin will usually generate random
  data of the appropriate size).
 */
void Key::setSize(int size)
{
    d_ptr->m_size = size;
}

/*!
  \qmlproperty ArrayBuffer Key::publicKey
  \brief The public key data associated with this key (asymmetric cryptosystems only)
*/

/*!
  \brief Returns the public key data associated with this key (asymmetric cryptosystems only)
 */
QByteArray Key::publicKey() const
{
    return d_ptr->m_publicKey;
}

/*!
  \brief Sets the public key data associated with this key to \a key
 */
void Key::setPublicKey(const QByteArray &key)
{
    d_ptr->m_publicKey = key;
}

/*!
  \qmlproperty ArrayBuffer Key::privateKey
  \brief The private key data associated with this key (asymmetric cryptosystems only)
*/

/*!
  \brief Returns the private key data associated with this key (asymmetric cryptosystems only)
 */
QByteArray Key::privateKey() const
{
    return d_ptr->m_privateKey;
}

/*!
  \brief Sets the private key data associated with this key to \a key

  This field will be ignored if the algorithm specified for the key
  is that of a symmetric cryptosystem.
 */
void Key::setPrivateKey(const QByteArray &key)
{
    d_ptr->m_privateKey = key;
}

/*!
  \qmlproperty ArrayBuffer Key::secretKey
  \brief The private key data associated with this key (symmetric cryptosystems only)
*/

/*!
  \brief Returns the private key data associated with this key (symmetric cryptosystems only)
 */
QByteArray Key::secretKey() const
{
    return d_ptr->m_secretKey;
}

/*!
  \brief Sets the secret key data associated with this key to \a key

  This field will be ignored if the algorithm specified for the key
  is that of an asymmetric cryptosystem.
 */
void Key::setSecretKey(const QByteArray &key)
{
    d_ptr->m_secretKey = key;
}

/*!
  \qmlproperty Array Key::customParameters
  \brief The custom parameters associated with this key
*/

/*!
  \brief Returns the custom parameters associated with this key
 */
QVector<QByteArray> Key::customParameters() const
{
    return d_ptr->m_customParameters;
}

/*!
  \brief Sets the custom parameters associated with this key to \a parameters.

  Some cryptosystem providers (i.e. Sailfish Crypto API extension plugins)
  may require some custom parameters to be supplied when generating, storing
  or performing operations with keys.

  In general, these parameters will be ignored unless the extension plugin
  requires them for some operation.
 */
void Key::setCustomParameters(const QVector<QByteArray> &parameters)
{
    d_ptr->m_customParameters = parameters;
}

/*!
  \brief Returns the filter data associated with this key.

  Other clients can use the filter data to find this key,
  if they have permission to access it.  The filter data
  is a simple map of string field to string value.
 */
Key::FilterData Key::filterData() const
{
    return d_ptr->m_filterData;
}

/*!
  \qmlmethod string Key::filterData(string field)
  \brief Returns the filter data value for the given \a field.
*/

/*!
  \brief Returns the filter data value for the given \a field.
 */
QString Key::filterData(const QString &field) const
{
    return d_ptr->m_filterData.value(field);
}

/*!
  \brief Replaces the filter data in this key with the given \a data.

  Note that the field "Type" will always have the value "CryptoKey"
  and this field value cannot be overwritten.
 */
void Key::setFilterData(const Key::FilterData &data)
{
    Key::FilterData v(data);
    v.insert(SAILFISH_SECRETS_SECRET_FILTERDATAFIELDTYPE, SAILFISH_SECRETS_SECRET_TYPECRYPTOKEY);
    d_ptr->m_filterData = v;
}

/*!
  \qmlproperty Array Key::filterDataFields
  \brief Returns the fields (keys) of filter data associated with the secret
*/

/*!
  \brief Returns the fields (keys) of filter data associated with the secret
 */
QStringList Key::filterDataFields() const
{
    return d_ptr->m_filterData.keys();
}

/*!
  \qmlmethod void Key::setFilterData(string field, string value)
  \brief Sets filter data for the given \a field to the given \a value.
*/

/*!
  \brief Sets filter data for the given \a field to the given \a value.

  Note that the field "Type" will always have the value "CryptoKey"
  and this field value cannot be overwritten.
 */
void Key::setFilterData(const QString &field, const QString &value)
{
    if (field.compare(SAILFISH_SECRETS_SECRET_FILTERDATAFIELDTYPE, Qt::CaseInsensitive) != 0) {
        d_ptr->m_filterData.insert(field, value);
    }
}

/*!
  \qmlmethod bool Key::hasFilterData(string field)
  \brief Returns true if the key has a filter data value specified for the given \a field.
*/

/*!
  \brief Returns true if the key has a filter data value specified for the given \a field.

  Note that this function will always return true for the field "Type".
 */
bool Key::hasFilterData(const QString &field)
{
    return d_ptr->m_filterData.contains(field);
}

/*!
  \brief Returns true if the \a lhs identifier consists of the same name and collection name as the \a rhs identifier
 */
bool Sailfish::Crypto::operator==(const Key::Identifier &lhs, const Key::Identifier &rhs)
{
    return lhs.storagePluginName() == rhs.storagePluginName()
            && lhs.collectionName() == rhs.collectionName()
            && lhs.name() == rhs.name();
}

/*!
  \brief Returns false if the \a lhs identifier consists of the same name and collection name as the \a rhs identifier
 */
bool Sailfish::Crypto::operator!=(const Key::Identifier &lhs, const Key::Identifier &rhs)
{
    return !operator==(lhs, rhs);
}

/*!
  \brief Returns true if the \a lhs identifier should sort as less than the \a rhs identifier
 */
bool Sailfish::Crypto::operator<(const Key::Identifier &lhs, const Key::Identifier &rhs)
{
    if (lhs.storagePluginName() != rhs.storagePluginName())
        return lhs.storagePluginName() < rhs.storagePluginName();
    if (lhs.collectionName() != rhs.collectionName())
        return lhs.collectionName() < rhs.collectionName();
    return lhs.name() < rhs.name();
}

/*!
  \brief Returns true if the \a lhs key is equal to the \a rhs key
 */
bool Sailfish::Crypto::operator==(const Key &lhs, const Key &rhs)
{
    return lhs.filterData() == rhs.filterData()
        && lhs.customParameters() == rhs.customParameters()
        && lhs.publicKey() == rhs.publicKey()
        && lhs.privateKey() == rhs.privateKey()
        && lhs.secretKey() == rhs.secretKey()
        && lhs.identifier() == rhs.identifier()
        && lhs.origin() == rhs.origin()
        && lhs.algorithm() == rhs.algorithm()
        && lhs.operations() == rhs.operations()
        && lhs.size() == rhs.size();
}

/*!
  \brief Returns false if the \a lhs key is equal to the \a rhs key
 */
bool Sailfish::Crypto::operator!=(const Key &lhs, const Key &rhs)
{
    return !operator==(lhs, rhs);
}

/*!
  \brief Returns true if the \a lhs key should sort as less than the \a rhs key
 */
bool Sailfish::Crypto::operator<(const Key &lhs, const Key &rhs)
{
    if (lhs.size() != 0 && rhs.size() != 0 && lhs.size() != rhs.size()) {
        return lhs.size() < rhs.size();
    } else if (lhs.identifier() != rhs.identifier()) {
        return lhs.identifier() < rhs.identifier();
    } else if (lhs.publicKey() != rhs.publicKey()) {
        return lhs.publicKey() < rhs.publicKey();
    } else if (lhs.privateKey() != rhs.privateKey()) {
        return lhs.privateKey() < rhs.privateKey();
    } else if (lhs.secretKey() != rhs.secretKey()) {
        return lhs.secretKey() < rhs.secretKey();
    } else {
        return lhs.algorithm() < rhs.algorithm();
    }
}
