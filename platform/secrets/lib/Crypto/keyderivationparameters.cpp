// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/keyderivationparameters.h"
#include "Crypto/keyderivationparameters_p.h"

using namespace Sailfish::Crypto;

KeyDerivationParametersPrivate::KeyDerivationParametersPrivate()
    : QSharedData()
    , m_keyDerivationFunction(CryptoManager::KdfUnknown)
    , m_keyDerivationMac(CryptoManager::MacUnknown)
    , m_keyDerivationAlgorithm(CryptoManager::AlgorithmUnknown)
    , m_keyDerivationDigestFunction(CryptoManager::DigestUnknown)
    , m_memorySize(16384)
    , m_iterations(16384)
    , m_parallelism(1)
    , m_outputKeySize(256)
{
}

KeyDerivationParametersPrivate::KeyDerivationParametersPrivate(
        const KeyDerivationParametersPrivate &other)
    : QSharedData(other)
    , m_inputData(other.m_inputData)
    , m_salt(other.m_salt)
    , m_keyDerivationFunction(other.m_keyDerivationFunction)
    , m_keyDerivationMac(other.m_keyDerivationMac)
    , m_keyDerivationAlgorithm(other.m_keyDerivationAlgorithm)
    , m_keyDerivationDigestFunction(other.m_keyDerivationDigestFunction)
    , m_memorySize(other.m_memorySize)
    , m_iterations(other.m_iterations)
    , m_outputKeySize(other.m_outputKeySize)
    , m_customParameters(other.m_customParameters)
{
}

KeyDerivationParametersPrivate::~KeyDerivationParametersPrivate()
{
}

/*!
  \qmltype KeyDerivationParameters
  \brief Encapsulates parameters related to the derivation of a symmetric encryption key
  \inqmlmodule Sailfish.Crypto
  \instantiates Sailfish::Crypto::KeyDerivationParameters
*/

/*!
  \class KeyDerivationParameters
  \brief Encapsulates parameters related to the derivation of a symmetric encryption key
  \inmodule SailfishCrypto
  \inheaderfile Crypto/keyderivationparameters.h

  This class encapsulates a variety of parameters which will affect how
  the crypto plugin generates a key.  Usually, an instance of this class
  will be used when performing a GenerateStoredKeyRequest.

  Not all parameters exposed in this class are applicable to every type
  of key derivation function.  In many cases, only one or two of the
  parameters will be meaningful for use with a specific key derivation
  function.

  One example of a set of common key derivation parameters is:

  \code
  Sailfish::Crypto::KeyDerivationParameters kdfParams;
  kdfParams.setKeyDerivationFunction(Sailfish::Crypto::CryptoManager::KdfPkcs5Pbkdf2);
  kdfParams.setKeyDerivationMac(Sailfish::Crypto::CryptoManager::MacHmac);
  kdfParams.setKeyDerivationDigestFunction(Sailfish::Crypto::CryptoManager::DigestSha512);
  kdfParams.setIterations(16384);
  kdfParams.setSalt(randomBytes);     // 16 random bytes, e.g. GenerateRandomDataRequest
  kdfParams.setOutputKeySize(256);
  \endcode

  Another example is:

  \code
  Sailfish::Crypto::KeyDerivationParameters kdfParams;
  kdfParams.setKeyDerivationFunction(Sailfish::Crypto::CryptoManager::KdfArgon2d);
  kdfParams.setIterations(256);
  kdfParams.setMemorySize(16384);
  kdfParams.setParallelism(2);
  kdfParams.setSalt(randomBytes);     // 16 random bytes, e.g. GenerateRandomDataRequest
  kdfParams.setOutputKeySize(256);
  \endcode

  Note also that if the GenerateStoredKeyRequest specifies (via
  InteractionParameters) that the input data should be requested directly
  from the user by the secrets service, then any input data specified
  in the KeyDerivationParameters instance will be ignored.
  Otherwise, if the input data is not intended to be requested from
  the user, it can be provided directly via setInputData(), for example:

  \code
  kdfParams.setInputData(sessionId); // from remote service etc.
  kdfParams.setSalt(nonce);          // from remote service etc.
  \endcode
 */

/*!
  \brief Constructs a new, empty KeyDerivationParameters instance
 */
KeyDerivationParameters::KeyDerivationParameters()
    : d_ptr(new KeyDerivationParametersPrivate)
{
}

/*!
  \brief Constructs a copy of the \a other KeyDerivationParameters instance
 */
KeyDerivationParameters::KeyDerivationParameters(
        const KeyDerivationParameters &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Destroys the KeyDerivationParameters instance
 */
KeyDerivationParameters::~KeyDerivationParameters()
{
}

/*!
  \brief Assigns the \a other KeyDerivationParameters instance to this
 */
KeyDerivationParameters&
KeyDerivationParameters::operator=(
        const KeyDerivationParameters &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \brief Returns true if the key derivation function and output key size are valid.
 */
bool KeyDerivationParameters::isValid() const
{
    return keyDerivationFunction() != CryptoManager::KdfUnknown
            && outputKeySize() > 0 && outputKeySize() <= 65536;
}

/*!
  \qmlproperty ArrayBuffer KeyDerivationParameters::inputData
  \brief The input data which will be used by the key derivation function to generate the output key
*/

/*!
  \brief Returns the input data which will be used by the key derivation function to generate the output key

  For example, often a passphrase is used to generate a key.
  This parameter is optional for some key derivation functions.
 */
QByteArray KeyDerivationParameters::inputData() const
{
    return d_ptr->m_inputData;
}

/*!
  \brief Sets the input data to \a data
 */
void KeyDerivationParameters::setInputData(const QByteArray &data)
{
    d_ptr->m_inputData = data;
}

/*!
  \qmlproperty ArrayBuffer KeyDerivationParameters::salt
  \brief The salt which will be used during key derivation
 */

/*!
  \brief Returns the salt which will be used during key derivation

  The salt should be unique and preferably random.
  The salt is not secret and can be stored publicly,
  and offers some protection against precalculation
  attacks, by adding randomness to the input data.

  For generating a symmetric key from a passphrase,
  many key derivation function implementations suggest
  providing 16 bytes of salt data.
 */
QByteArray KeyDerivationParameters::salt() const
{
    return d_ptr->m_salt;
}

/*!
  \brief Sets the salt to be used during key derivation to \a salt
 */
void KeyDerivationParameters::setSalt(const QByteArray &salt)
{
    d_ptr->m_salt = salt;
}

/*!
  \qmlproperty enumeration KeyDerivationParameters::keyDerivationFunction
  \brief The key derivation function which should be used to derive the key
  \value KdfUnknown
  \value KdfCustom
  \value KdfPkcs5Pbkdf2
  \value KdfHkdf
  \value KdfBcrypt
  \value KdfScrypt
  \value KdfArgon2
  \value KdfArgon2d          = KdfArgon2
  \value KdfArgon2i
  \value KdfArgon2id
  \value KdfLyra2
*/

/*!
  \brief Returns the key derivation function which should be used to derive the key

  A key derivation function is a form of hash function which
  is intentionally slow to calculate, and has certain randomness
  characteristics which provide security against bruteforce
  attacks.

  Some key derivation functions (such as
  \l{CryptoManager::KdfPkcs5Pbkdf2}) require certain parameters to
  be specified (e.g. iterations(), and either
  keyDerivationMac() and keyDerivationDigestFunction(), or
  keyDerivationMac() and keyDerivationAlgorithm()), while
  others (such as \l{CryptoManager::KdfArgon2d}) require
  different parameters (e.g. iterations(), parallelism() and memorySize()).
 */
CryptoManager::KeyDerivationFunction
KeyDerivationParameters::keyDerivationFunction() const
{
    return d_ptr->m_keyDerivationFunction;
}

/*!
  \brief Sets the key derivation function which will be used to derive a key to \a kdf
 */
void KeyDerivationParameters::setKeyDerivationFunction(
        CryptoManager::KeyDerivationFunction kdf)
{
    d_ptr->m_keyDerivationFunction = kdf;
}

/*!
  \qmlproperty enumeration KeyDerivationParameters::keyDerivationMac
  \brief The message authentication code function which will be used by the key derivation function
  \value MacUnknown
  \value MacCustom
  \value MacHmac
  \value MacCmac
  \value MacVmac
  \value MacPoly1305
*/

/*!
  \brief Returns the message authentication code function which will be used by the key derivation function

  Some key derivation functions work by applying a MAC function multiple
  times, and in some cases (e.g. \l{CryptoManager::KdfPkcs5Pbkdf2}) the
  client can choose which specific MAC function should be used.

  One example of a common parameter selection is to use
  \l{CryptoManager::KdfPkcs5Pbkdf2} as the key derivation function,
  with \l{CryptoManager::MacHmac} as the MAC function, and
  \l{CryptoManager::DigestSha512} as the HMAC digest function.
 */
CryptoManager::MessageAuthenticationCode
KeyDerivationParameters::keyDerivationMac() const
{
    return d_ptr->m_keyDerivationMac;
}

/*!
  \brief Sets the message authentication code function which will be used by the key derivation function to \a mac

  Note: not all key derivation functions use a message authentication code
  function to derive the key, and of those that do, not many allow the
  MAC function to be specified by the client.
 */
void KeyDerivationParameters::setKeyDerivationMac(
        CryptoManager::MessageAuthenticationCode mac)
{
    d_ptr->m_keyDerivationMac = mac;
}

/*!
  \qmlproperty enumeration KeyDerivationParameters::keyDerivationAlgorithm
  \brief The algorithm which will be used by the key derivation function
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
  \value AlgorithmTdes           = AlgorithmTdea
  \value AlgorithmBlowfish
  \value AlgorithmSalsa
  \value AlgorithmSalsa20        = AlgorithmSalsa
  \value AlgorithmChaCha
  \value AlgorithmChaCha20       = AlgorithmChaCha
  \value AlgorithmRc4
  \value AlgorithmRc5
  \value AlgorithmRc6
  \value AlgorithmSquare
  \value AlgorithmSerpent
  \value AlgorithmPanama
*/

/*!
  \brief Returns the algorithm which will be used by the key derivation function

  Some key derivation functions work by applying a symmetric cipher
  algorithm multiple times (for example bcrypt which uses the Blowfish
  cipher), and in some of these cases the client can choose
  which specific algorithm should be used.

  Some other key derivation functions work by applying a MAC function
  multiple times (for example PBKDF2), and in some of these cases the
  MAC function works by applying a symmetric cipher algorithm multiple
  times, and in some of these cases the client can choose which algorithm
  should be used by the MAC function.

  One example of a common parameter selection is to use
  \l{CryptoManager::KdfPkcs5Pbkdf2} as the key derivation function,
  with \l{CryptoManager::MacPoly1305} as the MAC function, and
  \l{CryptoManager::AlgorithmAes} as the Poly1305 cipher algorithm.
 */
CryptoManager::Algorithm
KeyDerivationParameters::keyDerivationAlgorithm() const
{
    return d_ptr->m_keyDerivationAlgorithm;
}

/*!
  \brief Sets the key derivation algorithm to be used to \a algo

  Note: generally only symmetric cipher algorithms are valid
  for key derivation operations, and not all key derivation
  functions allow the algorithm to be parametrised.
 */
void KeyDerivationParameters::setKeyDerivationAlgorithm(
        CryptoManager::Algorithm algo)
{
    d_ptr->m_keyDerivationAlgorithm = algo;
}

/*!
  \qmlproperty enumeration KeyDerivationParameters::keyDerivationDigestFunction
  \brief The digest function which will be used by the key derivation function
  \value DigestUnknown
  \value DigestCustom
  \value DigestMd5
  \value DigestSha1
  \value DigestSha2_224
  \value DigestSha2_256
  \value DigestSha256        = DigestSha2_256
  \value DigestSha2_384
  \value DigestSha2_512
  \value DigestSha512        = DigestSha2_512
  \value DigestSha2_512_224
  \value DigestSha2_512_256
  \value DigestSha3_224
  \value DigestSha3_256
  \value DigestSha3_384
  \value DigestSha3_512
  \value DigestShake128
  \value DigestShake256
  \value DigestGost_94
  \value DigestGost_2012_256
  \value DigestGost_2012_512
  \value DigestBlake
  \value DigestBlake2
  \value DigestBlake2b
  \value DigestBlake2s
  \value DigestWhirlpool
  \value DigestRipeMd
  \value DigestRipeMd128_256
  \value DigestRipeMd160
  \value DigestRipeMd320
  \value DigestTiger
  \value DigestTiger128
  \value DigestTiger160
  \value DigestTiger192
  \value DigestTiger2
  \value DigestTiger2_128
  \value DigestTiger2_160
  \value DigestTiger2_192
  \value DigestRadioGatun
*/

/*!
  \brief Returns the digest function which will be used by the key derivation function

  Some key derivation functions work by applying a digest function
  multiple times (for example Argon2 which uses the Blake2 function), and
  in some of these cases the client can choose which specific digest
  function should be used.

  Some other key derivation functions work by applying a MAC function
  multiple times (for example PBKDF2), and in some of these cases the
  MAC function works by applying a digest function multiple times, and in
  some of these cases the client can choose which digest function should be
  used by the MAC function.

  One example of a common parameter selection is to use
  \l{CryptoManager::KdfPkcs5Pbkdf2} as the key derivation function,
  with \l{CryptoManager::MacHmac} as the MAC function, and
  \l{CryptoManager::DigestSha512} as the HMAC digest function.
 */
CryptoManager::DigestFunction
KeyDerivationParameters::keyDerivationDigestFunction() const
{
    return d_ptr->m_keyDerivationDigestFunction;
}

/*!
  \brief Sets the key derivation digest function to \a func

  Note: not all key derivation functions use a digest function or a
  message authentication code function to derive the key, and of those
  that do, not many allow the digest function to be specified by the
  client.
 */
void KeyDerivationParameters::setKeyDerivationDigestFunction(
        CryptoManager::DigestFunction func)
{
    d_ptr->m_keyDerivationDigestFunction = func;
}

/*!
  \qmlproperty int KeyDerivationParameters::memorySize
  \brief The memory size parameter to be used when deriving the key
*/

/*!
  \brief Returns the memory size parameter to be used when deriving the key

  Some key derivation functions (e.g. Argon2) allow clients to provide
  a memory size parameter which modifies the operation of the function
  to make the output more resilient to bruteforce attack.

  Please see the documentation for the plugin providing the
  KDF you wish to use, to see whether this parameter is
  applicable for your case.

  Also, the meaning (and units) of this parameter can be different
  depending on the key derivation function (e.g. Argon2 vs scrypt),
  so please see the documentation for your plugin for more information.
 */
qint64 KeyDerivationParameters::memorySize() const
{
    return d_ptr->m_memorySize;
}

/*!
  \brief Sets the memory size parameter to be used when deriving the key to \a size
 */
void KeyDerivationParameters::setMemorySize(qint64 size)
{
    d_ptr->m_memorySize = size;
}

/*!
  \qmlproperty int KeyDerivationParameters::iterations
  \brief The number of iterations of the hash function or cipher to be used when deriving the key
*/

/*!
  \brief Returns the number of iterations of the hash function or cipher to be used when deriving the key

  Some key derivation functions (e.g. Argon2) allow clients to provide
  an iterations parameter which modifies the operation of the function
  to make the output more resilient to bruteforce attack.

  Please see the documentation for the plugin providing the
  KDF you wish to use, to see whether this parameter is
  applicable for your case.
 */
int KeyDerivationParameters::iterations() const
{
    return d_ptr->m_iterations;
}

/*!
  \brief Sets the number of iterations of the hash function or cipher to be used when deriving the key to \a iterations
 */
void KeyDerivationParameters::setIterations(int iterations)
{
    d_ptr->m_iterations = iterations;
}

/*!
  \qmlproperty int KeyDerivationParameters::parallelism
  \brief The amount of parallelism (threads) to be used when deriving the key
*/

/*!
  \brief Returns the amount of parallelism (threads) to be used when deriving the key

  Some key derivation functions (e.g. Argon2) allow clients to provide
  a parallelism parameter which modifies the operation of the function
  to make the output more resilient to bruteforce attack.

  Please see the documentation for the plugin providing the
  KDF you wish to use, to see whether this parameter is
  applicable for your case.
 */
int KeyDerivationParameters::parallelism() const
{
    return d_ptr->m_parallelism;
}

/*!
  \brief Sets the amount of parallelism to be used when deriving the key to \a parallelism
 */
void KeyDerivationParameters::setParallelism(int parallelism)
{
    d_ptr->m_parallelism = parallelism;
}

/*!
  \qmlproperty int KeyDerivationParameters::outputKeySize
  \brief The security size (in bits) of the output key
*/

/*!
  \brief Returns the security size (in bits) of the output key

  Note that the security size is not necessarily the same as the
  data (storage) size, although for symmetric ciphers those
  usually are the same.
 */
int KeyDerivationParameters::outputKeySize() const
{
    return d_ptr->m_outputKeySize;
}

/*!
  \brief Sets the required security size (in bits) of the output key to \a size
 */
void KeyDerivationParameters::setOutputKeySize(int size)
{
    d_ptr->m_outputKeySize = size;
}

/*!
  \qmlproperty object KeyDerivationParameters::customParameters
  \brief The plugin-specific custom parameters which will be used during key generation
*/

/*!
  \brief Returns the plugin-specific custom parameters which will be used during key generation
 */
QVariantMap KeyDerivationParameters::customParameters() const
{
    return d_ptr->m_customParameters;
}

/*!
  \brief Sets the plugin-specific custom parameters to be used during key generation to \a params
 */
void KeyDerivationParameters::setCustomParameters(const QVariantMap &params)
{
    d_ptr->m_customParameters = params;
}

/*!
  \brief Returns true if the \a lhs parameters are equal to the \a rhs parameters.

  If the parameters are equal, a key derived from the \a lhs should be exactly
  equal to a key derived from the \a rhs.
 */
bool Sailfish::Crypto::operator==(const KeyDerivationParameters &lhs, const KeyDerivationParameters &rhs)
{
    return lhs.inputData() == rhs.inputData()
            && lhs.salt() == rhs.salt()
            && lhs.keyDerivationFunction() == rhs.keyDerivationFunction()
            && lhs.keyDerivationMac() == rhs.keyDerivationMac()
            && lhs.keyDerivationAlgorithm() == rhs.keyDerivationAlgorithm()
            && lhs.keyDerivationDigestFunction() == rhs.keyDerivationDigestFunction()
            && lhs.memorySize() == rhs.memorySize()
            && lhs.iterations() == rhs.iterations()
            && lhs.parallelism() == rhs.parallelism()
            && lhs.outputKeySize() == rhs.outputKeySize()
            && lhs.customParameters() == rhs.customParameters();
}

/*!
  \brief Returns false if the \a lhs parameters are equal to the \a rhs parameters.
 */
bool Sailfish::Crypto::operator!=(const Sailfish::Crypto::KeyDerivationParameters &lhs, const Sailfish::Crypto::KeyDerivationParameters &rhs)
{
    return !operator==(lhs, rhs);
}

/*!
  \brief Returns true if the \a lhs parameters should sort as less than the \a rhs parameters.
 */
bool Sailfish::Crypto::operator<(const Sailfish::Crypto::KeyDerivationParameters &lhs, const Sailfish::Crypto::KeyDerivationParameters &rhs)
{
    if (lhs.outputKeySize() != rhs.outputKeySize())
        return lhs.outputKeySize() < rhs.outputKeySize();

    if (lhs.keyDerivationFunction() != rhs.keyDerivationFunction())
        return lhs.keyDerivationFunction() < rhs.keyDerivationFunction();

    if (lhs.keyDerivationMac() != rhs.keyDerivationMac())
        return lhs.keyDerivationMac() < rhs.keyDerivationMac();

    if (lhs.keyDerivationAlgorithm() != rhs.keyDerivationAlgorithm())
        return lhs.keyDerivationAlgorithm() < rhs.keyDerivationAlgorithm();

    if (lhs.keyDerivationDigestFunction() != rhs.keyDerivationDigestFunction())
        return lhs.keyDerivationDigestFunction() < rhs.keyDerivationDigestFunction();

    if (lhs.memorySize() != rhs.memorySize())
        return lhs.memorySize() < rhs.memorySize();

    if (lhs.iterations() != rhs.iterations())
        return lhs.iterations() < rhs.iterations();

    if (lhs.parallelism() != rhs.parallelism())
        return lhs.parallelism() < rhs.parallelism();

    if (lhs.salt() != rhs.salt())
        return lhs.salt() < rhs.salt();

    if (lhs.inputData() != rhs.inputData())
        return lhs.inputData() < rhs.inputData();

    return lhs.customParameters().keys() < rhs.customParameters().keys();
}
