// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Crypto/keypairgenerationparameters.h"
#include "Crypto/keypairgenerationparameters_p.h"

#define EcKeyPairGenerationParametersEllipticCurve QStringLiteral("ellipticCurve")
#define RsaKeyPairGenerationParametersModulusLength QStringLiteral("modulusLength")
#define RsaKeyPairGenerationParametersNumberPrimes QStringLiteral("numberPrimes")
#define RsaKeyPairGenerationParametersPublicExponent QStringLiteral("publicExponent")
#define DsaKeyPairGenerationParametersModulusLength QStringLiteral("modulusLength")
#define DsaKeyPairGenerationParametersPrimeFactorLength QStringLiteral("primeFactorLength")
#define DsaKeyPairGenerationParametersGenerateFamilyParameters QStringLiteral("generateFamilyParameters")
#define DsaKeyPairGenerationParametersModulus QStringLiteral("modulus")
#define DsaKeyPairGenerationParametersPrimeFactor QStringLiteral("primeFactor")
#define DsaKeyPairGenerationParametersBase QStringLiteral("base")
#define DhKeyPairGenerationParametersModulusLength QStringLiteral("modulusLength")
#define DhKeyPairGenerationParametersPrivateExponentLength QStringLiteral("privateExponentLength")
#define DhKeyPairGenerationParametersGenerateFamilyParameters QStringLiteral("generateFamilyParameters")
#define DhKeyPairGenerationParametersModulus QStringLiteral("modulus")
#define DhKeyPairGenerationParametersBase QStringLiteral("base")

using namespace Sailfish::Crypto;

KeyPairGenerationParametersPrivate::KeyPairGenerationParametersPrivate()
    : QSharedData()
    , m_keyPairType(KeyPairGenerationParameters::KeyPairUnknown)
{
}

KeyPairGenerationParametersPrivate::KeyPairGenerationParametersPrivate(
        const KeyPairGenerationParametersPrivate &other)
    : QSharedData(other)
    , m_keyPairType(other.m_keyPairType)
    , m_customParameters(other.m_customParameters)
    , m_subclassParameters(other.m_subclassParameters)
{
}

KeyPairGenerationParametersPrivate::~KeyPairGenerationParametersPrivate()
{
}

QVariantMap KeyPairGenerationParametersPrivate::subclassParameters(
        const KeyPairGenerationParameters &kpgParams)
{
    return kpgParams.d_ptr->m_subclassParameters;
}

void KeyPairGenerationParametersPrivate::setSubclassParameters(
        KeyPairGenerationParameters &kpgParams, const QVariantMap &params)
{
    kpgParams.d_ptr->m_subclassParameters = params;
}

/*!
  \qmltype KeyPairGenerationParameters
  \brief Encapsulates parameters related to the generation of an asymmetric cryptographic key pair
  \inqmlmodule Sailfish.Crypto
  \instantiates Sailfish::Crypto::KeyPairGenerationParameters
*/

/*!
  \class KeyPairGenerationParameters
  \brief Encapsulates parameters related to the generation of an asymmetric cryptographic key pair
  \inmodule SailfishCrypto
  \inheaderfile Crypto/keypairgenerationparameters.h

  This class encapsulates a variety of parameters which will affect how
  the crypto plugin generates a key pair when fulfilling a
  GenerateStoredKeyRequest.

  This base class is only useful for plugin-specific key-pair generation
  (where the keyPairType() is specified to be
  KeyPairGenerationParameters::KeyPairCustom and the client has specified
  a variety of customParameters()).

  Most clients will want to use one of the derived types such as
  EcKeyPairGenerationParameters, RsaKeyPairGenerationParameters,
  DsaKeyPairGenerationParameters or DhKeyPairGenerationParameters.
 */

/*!
  \brief Constructs a new, empty KeyPairGenerationParameters instance
 */
KeyPairGenerationParameters::KeyPairGenerationParameters()
    : d_ptr(new KeyPairGenerationParametersPrivate)
{
}

/*!
  \brief Constructs a copy of the \a other KeyPairGenerationParameters instance
 */
KeyPairGenerationParameters::KeyPairGenerationParameters(
        const KeyPairGenerationParameters &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Destroys the KeyPairGenerationParameters instance
 */
KeyPairGenerationParameters::~KeyPairGenerationParameters()
{
}

/*!
  \brief Assigns the \a other KeyPairGenerationParameters instance to this
 */
KeyPairGenerationParameters&
KeyPairGenerationParameters::operator=(
        const KeyPairGenerationParameters &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \brief Returns true if enough parameters have been provided so that the plugin can generate a key pair

  This is assumed to be true if the keyPairType() is
  KeyPairGenerationParameters::KeyPairCustom and some customParameters()
  exist, otherwise the validity of the parameters depends on the type of
  key pair to be generated and the specific values specified as parameters
  for generating that type of key pair.

  Note that this function cannot determine whether the individual parameters
  themselves are valid or invalid, as no assumptions about parameter validity
  are encoded within the client API; hence the plugin may still return an
  error for parameters which are deemed valid (since they exist) but
  are erroneously specified (e.g. a prime number which isn't prime).
 */
bool KeyPairGenerationParameters::isValid() const
{
    if (keyPairType() == KeyPairGenerationParameters::KeyPairCustom
            && !customParameters().isEmpty()) {
        return true;
    } else if (keyPairType() == KeyPairGenerationParameters::KeyPairEc) {
        return EcKeyPairGenerationParameters(*this).isValid();
    } else if (keyPairType() == KeyPairGenerationParameters::KeyPairRsa) {
        return RsaKeyPairGenerationParameters(*this).isValid();
    } else if (keyPairType() == KeyPairGenerationParameters::KeyPairDsa) {
        return DsaKeyPairGenerationParameters(*this).isValid();
    } else if (keyPairType() == KeyPairGenerationParameters::KeyPairDh) {
        return DhKeyPairGenerationParameters(*this).isValid();
    }

    return false;
}

/*!
  \qmlproperty enumeration KeyPairGenerationParameters::keyPairType
  \brief The type of key pair which should be generated
  \value KeyPairUnknown          = CryptoManager::AlgorithmUnknown
  \value KeyPairCustom           = CryptoManager::AlgorithmCustom
  \value KeyPairDh               = CryptoManager::AlgorithmDh
  \value KeyPairDsa              = CryptoManager::AlgorithmDsa
  \value KeyPairRsa              = CryptoManager::AlgorithmRsa
  \value KeyPairEc               = CryptoManager::AlgorithmEc
*/

/*!
  \brief Returns the type of key pair which should be generated
 */
KeyPairGenerationParameters::KeyPairType KeyPairGenerationParameters::keyPairType() const
{
    return d_ptr->m_keyPairType;
}

/*!
  \brief Sets the type of key pair which should be generated to \a type
 */
void KeyPairGenerationParameters::setKeyPairType(KeyPairGenerationParameters::KeyPairType type)
{
    d_ptr->m_keyPairType = type;
}

/*!
  \qmlproperty object KeyPairGenerationParameters::customParameters
  \brief The plugin-specific custom parameters which will be used during key generation
*/

/*!
  \brief Returns the plugin-specific custom parameters which will be used during key generation
 */
QVariantMap KeyPairGenerationParameters::customParameters() const
{
    return d_ptr->m_customParameters;
}

/*!
  \brief Returns the algorithm-specific parameters which will be used during key generation
 */
QVariantMap KeyPairGenerationParameters::subclassParameters() const
{
    return d_ptr->m_subclassParameters;
}

/*!
  \brief Sets the plugin-specific custom parameters to be used during key generation to \a params
 */
void KeyPairGenerationParameters::setCustomParameters(const QVariantMap &params)
{
    d_ptr->m_customParameters = params;
}

/*!
  \class EcKeyPairGenerationParameters
  \brief Encapsulates parameters related to the generation of an asymmetric
         cryptographic key pair based on an elliptic curve
  \inmodule SailfishCrypto
  \inheaderfile Crypto/keypairgenerationparameters.h

  This class encapsulates a variety of parameters which will affect how
  the crypto plugin generates a key pair.  Usually, an instance of this class
  will be used when performing a GenerateStoredKeyRequest.

  An example of parameters to generate an elliptic curve key pair for use in
  ECDSA and ECDH operations follows:

  \code
  Sailfish::Crypto::EcKeyPairGenerationParameters eckpgParams;
  eckpgParams.setEllipticCurve(Sailfish::Crypto::CryptoManager::Curve25519);
  \endcode

  The security size of the generated key will depend on the size of the field
  over which the curve is defined.  For example, Curve25519 is a 255-bit
  elliptic curve requiring 252-bit private keys (usually encoded as 256-bit
  values with four fixed bits), providing security approximately equivalent
  to using a 128-bit symmetric cipher key, or 3072 bit RSA key.

  Support for different curves is entirely plugin-specific; please see the
  documentation for the crypto plugin you intend to use for more information
  about the different curves which are supported, and what (if any) custom
  parameters may be supported.
 */

/*!
  \brief Constructs a new instance of EcKeyPairGenerationParameters
 */
EcKeyPairGenerationParameters::EcKeyPairGenerationParameters()
    : KeyPairGenerationParameters()
{
    setKeyPairType(KeyPairGenerationParameters::KeyPairEc);
    setEllipticCurve(CryptoManager::CurveSecp384r1);
}

/*!
  \brief Constructs a copy of the \a other KeyPairGenerationParameters instance
 */
EcKeyPairGenerationParameters::EcKeyPairGenerationParameters(
        const KeyPairGenerationParameters &other)
    : KeyPairGenerationParameters(other)
{
}

/*!
  \brief Destroys the EcKeyPairGenerationParameters instance
 */
EcKeyPairGenerationParameters::~EcKeyPairGenerationParameters()
{
}

/*!
  \brief Assigns the \a other EcKeyPairGenerationParameters to this instance
 */
EcKeyPairGenerationParameters& EcKeyPairGenerationParameters::operator=(
        const EcKeyPairGenerationParameters &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

bool EcKeyPairGenerationParameters::isValid() const
{
    if (keyPairType() == KeyPairGenerationParameters::KeyPairEc) {
        return ellipticCurve() != CryptoManager::CurveUnknown;
    }

    return KeyPairGenerationParameters::isValid();
}

/*!
  \brief Returns the elliptic curve which should be used to calculate the key pair
 */
CryptoManager::EllipticCurve
EcKeyPairGenerationParameters::ellipticCurve() const
{
    return static_cast<CryptoManager::EllipticCurve>(
                d_ptr->m_subclassParameters.value(EcKeyPairGenerationParametersEllipticCurve).toInt());
}

/*!
  \brief Sets the elliptic curve which should be used to calculate the key pair to \a curve
 */
void EcKeyPairGenerationParameters::setEllipticCurve(
        CryptoManager::EllipticCurve curve)
{
    d_ptr->m_subclassParameters.insert(EcKeyPairGenerationParametersEllipticCurve,
                                       static_cast<int>(curve));
}


/*!
  \class RsaKeyPairGenerationParameters
  \brief Encapsulates parameters related to the generation of an asymmetric
         cryptographic key pair based on the RSA algorithm
  \inmodule SailfishCrypto
  \inheaderfile Crypto/keypairgenerationparameters.h

  This class encapsulates a variety of parameters which will affect how
  the crypto plugin generates a key pair.  Usually, an instance of this class
  will be used when performing a GenerateStoredKeyRequest.

  An example of parameters to generate a 4096-bit RSA key pair follows.
  Note that the default public exponent is defined as 65537 and the default
  number of primes is 2, so the last two lines are not required but are
  included for illustration purposes.

  \code
  Sailfish::Crypto::RsaKeyPairGenerationParameters rsakpgParams;
  rsakpgParams.setModulusLength(4096);
  rsakpgParams.setPublicExponent(65537);
  rsakpgParams.setNumberPrimes(2);
  \endcode
 */

/*!
  \brief Constructs a new, default RsaKeyPairGenerationParameters instance
 */
RsaKeyPairGenerationParameters::RsaKeyPairGenerationParameters()
    : KeyPairGenerationParameters()
{
    setKeyPairType(KeyPairGenerationParameters::KeyPairRsa);
    setModulusLength(4096);
    setNumberPrimes(2);
    setPublicExponent(65537);
}

/*!
  \brief Constructs a copy of the \a other KeyPairGenerationParameters instance
 */
RsaKeyPairGenerationParameters::RsaKeyPairGenerationParameters(
        const KeyPairGenerationParameters &other)
    : KeyPairGenerationParameters(other)
{
}

/*!
  \brief Destroys the RsaKeyPairGenerationParameters instance
 */
RsaKeyPairGenerationParameters::~RsaKeyPairGenerationParameters()
{
}

/*!
  \brief Assigns the \a other RsaKeyPairGenerationParameters to this instance
 */
RsaKeyPairGenerationParameters& RsaKeyPairGenerationParameters::operator=(const RsaKeyPairGenerationParameters &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

bool RsaKeyPairGenerationParameters::isValid() const
{
    if (keyPairType() == KeyPairGenerationParameters::KeyPairRsa) {
        return modulusLength() > 0 && numberPrimes() >= 2 && publicExponent() >= 3;
    }
    return KeyPairGenerationParameters::isValid();
}

/*!
  \brief Returns the modulus length of the RSA key pair to be generated

  This defines the security size of the output key.
 */
int RsaKeyPairGenerationParameters::modulusLength() const
{
    return d_ptr->m_subclassParameters.value(RsaKeyPairGenerationParametersModulusLength).toInt();
}

/*!
  \brief Sets the modulus length of the RSA key pair to be generated to \a length
 */
void RsaKeyPairGenerationParameters::setModulusLength(int length)
{
    d_ptr->m_subclassParameters.insert(RsaKeyPairGenerationParametersModulusLength,
                                       QVariant::fromValue<int>(length));
}

/*!
  \brief Sets the number of prime factors in the key as per RFC3447

  The default value is 2.  Having more than this reduces the security
  of the key but allows faster performance during operations.
 */
int RsaKeyPairGenerationParameters::numberPrimes() const
{
    return d_ptr->m_subclassParameters.value(RsaKeyPairGenerationParametersNumberPrimes).toInt();
}

/*!
  \brief Sets the number of prime factors in the key as per RFC3447 to \a primes
 */
void RsaKeyPairGenerationParameters::setNumberPrimes(int primes)
{
    d_ptr->m_subclassParameters.insert(RsaKeyPairGenerationParametersNumberPrimes,
                                       QVariant::fromValue<int>(primes));
}

/*!
  \brief Returns the public exponent to use when generating the key

  The default value is 65537.  Other common values include 3, 5, 7,
  17, and 257, although any prime number is sufficient.
 */
quint64 RsaKeyPairGenerationParameters::publicExponent() const
{
    return d_ptr->m_subclassParameters.value(RsaKeyPairGenerationParametersPublicExponent).toULongLong();
}

/*!
  \brief Sets the public exponent to use when generating the key to \a exponent
 */
void RsaKeyPairGenerationParameters::setPublicExponent(quint64 exponent)
{
    d_ptr->m_subclassParameters.insert(RsaKeyPairGenerationParametersPublicExponent,
                                       QVariant::fromValue<quint64>(exponent));
}


/*!
  \class DsaKeyPairGenerationParameters
  \brief Encapsulates parameters related to the generation of an asymmetric
         cryptographic key pair based on the DSA algorithm
  \inmodule SailfishCrypto
  \inheaderfile Crypto/keypairgenerationparameters.h

  This class encapsulates a variety of parameters which will affect how
  the crypto plugin generates a key pair.  Usually, an instance of this class
  will be used when performing a GenerateStoredKeyRequest.

  An example of parameters to generate a 3072-bit DSA key pair using the
  key family parameters specified in FIPS-186-3 follows:

  \code
  Sailfish::Crypto::DsaKeyPairGenerationParameters dsakpgParams;
  dsakpgParams.setModulusLength(3072);
  dsakpgParams.setPrimeFactorLength(256);
  dsakpgParams.setGenerateFamilyParameters(false);
  \endcode

  Alternatively, the algorithm parameters may be specified explicitly
  via setting the modulus(), primeFactor() and base() values:

  \code
  Sailfish::Crypto::DsaKeyPairGenerationParameters dsakpgParams;
  dsakpgParams.setModulus(modulusData);
  dsakpgParams.setPrimeFactor(primeFactorData);
  dsakpgParams.setBase(baseData);
  \endcode
 */

/*!
  \brief Constructs a new DsaKeyPairGenerationParameters instance
 */
DsaKeyPairGenerationParameters::DsaKeyPairGenerationParameters()
    : KeyPairGenerationParameters()
{
    setKeyPairType(KeyPairGenerationParameters::KeyPairDsa);
    setModulusLength(3072);
    setPrimeFactorLength(256);
    setGenerateFamilyParameters(false);
}

/*!
  \brief Constructs a copy of the \a other instance
 */
DsaKeyPairGenerationParameters::DsaKeyPairGenerationParameters(
        const KeyPairGenerationParameters &other)
    : KeyPairGenerationParameters(other)
{
}

/*!
  \brief Destroys the instance
 */
DsaKeyPairGenerationParameters::~DsaKeyPairGenerationParameters()
{
}

/*!
  \brief Assigns the \a other parameters to this instance
 */
DsaKeyPairGenerationParameters&
DsaKeyPairGenerationParameters::operator=(const DsaKeyPairGenerationParameters &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \brief Returns true if the parameters contains either a valid modulus, prime factor, and base,
         or alternatively a valid modulus length and prime factor length.
 */
bool DsaKeyPairGenerationParameters::isValid() const
{
    if (!modulus().isEmpty() && !primeFactor().isEmpty() && !base().isEmpty())
        return true;

    if (modulusLength() > 0 && primeFactorLength() > 0)
        return true;

    return false;
}

/*!
  \brief Returns the modulus length of the DSA key pair to be generated

  This defines the security size of the output key.

  Note that this parameter is only meaningful if the client has not
  provided explicit values for the modulus(), primeFactor() and base().
 */
int DsaKeyPairGenerationParameters::modulusLength() const
{
    return d_ptr->m_subclassParameters.value(DsaKeyPairGenerationParametersModulusLength).toInt();
}

/*!
  \brief Sets the modulus length of the DSA key pair to be generated to \a length
 */
void DsaKeyPairGenerationParameters::setModulusLength(int length)
{
    d_ptr->m_subclassParameters.insert(DsaKeyPairGenerationParametersModulusLength,
                                       QVariant::fromValue<int>(length));
}

/*!
  \brief Returns the prime factor length of the DSA key pair to be generated

  This is the length (in bits) of the prime-factor (q).
  Note that FIPS 186-3 specifies some standard prime factor lengths for
  certain modulus lengths, along with standardised key family parameters.

  Note that this parameter is only meaningful if the client has not
  provided explicit values for the modulus(), primeFactor() and base().
 */
int DsaKeyPairGenerationParameters::primeFactorLength() const
{
    return d_ptr->m_subclassParameters.value(DsaKeyPairGenerationParametersPrimeFactorLength).toInt();
}

/*!
  \brief Sets the prime factor length of the DSA key pair to be generated to \a length
 */
void DsaKeyPairGenerationParameters::setPrimeFactorLength(int length)
{
    d_ptr->m_subclassParameters.insert(DsaKeyPairGenerationParametersPrimeFactorLength,
                                       QVariant::fromValue<int>(length));
}

/*!
  \brief Returns true if the key should be generated using randomly-generated key family parameters

  The individual parameters (modulus (prime p), prime factor (subprime q),
  and base (generator g)) define the key family.  In order for the
  algorithm to work, both parties need to use the same parameters in
  order for their (randomly generated public and private) keys to belong
  to the same family (and thus work).

  If this value is true, the client wants the plugin to generate a key
  pair using randomly generated key family parameters; otherwise,
  the client wants the plugin to generate a key pair using the standard
  key family values specified in FIPS 186-3.

  This value is only meaningful if the client has provided a modulusLength()
  and primeFactorLength(), and is ignored if the client has instead
  provided a modulus(), primeFactor() and base().
 */
bool DsaKeyPairGenerationParameters::generateFamilyParameters() const
{
    return d_ptr->m_subclassParameters.value(DsaKeyPairGenerationParametersGenerateFamilyParameters).toBool();
}

/*!
  \brief Sets whether the key should be generated using randomly-generated key family parameters to \a generate
 */
void DsaKeyPairGenerationParameters::setGenerateFamilyParameters(bool generate)
{
    d_ptr->m_subclassParameters.insert(DsaKeyPairGenerationParametersGenerateFamilyParameters,
                                       QVariant::fromValue<bool>(generate));
}

/*!
  \brief Returns the modulus to be used when generating the key pair

  The modulus is also known as the large prime P.
 */
QByteArray DsaKeyPairGenerationParameters::modulus() const
{
    return d_ptr->m_subclassParameters.value(DsaKeyPairGenerationParametersModulus).toByteArray();
}

/*!
  \brief Sets the modulus to be used when generating the key pair to \a p
 */
void DsaKeyPairGenerationParameters::setModulus(const QByteArray &p)
{
    d_ptr->m_subclassParameters.insert(DsaKeyPairGenerationParametersModulus,
                                       QVariant::fromValue<QByteArray>(p));
}

/*!
  \brief Returns the prime factor to be used when generating the key pair

  The prime factor is also known as the small prime Q.
 */
QByteArray DsaKeyPairGenerationParameters::primeFactor() const
{
    return d_ptr->m_subclassParameters.value(DsaKeyPairGenerationParametersPrimeFactor).toByteArray();
}

/*!
  \brief Sets the prime factor to be used when generating the key pair to \a q
 */
void DsaKeyPairGenerationParameters::setPrimeFactor(const QByteArray &q)
{
    d_ptr->m_subclassParameters.insert(DsaKeyPairGenerationParametersPrimeFactor,
                                       QVariant::fromValue<QByteArray>(q));
}

/*!
  \brief Returns the base generator to be used when generating the key pair

  The base is also known as the generator G.
 */
QByteArray DsaKeyPairGenerationParameters::base() const
{
    return d_ptr->m_subclassParameters.value(DsaKeyPairGenerationParametersBase).toByteArray();
}

/*!
  \brief Sets the base generator to be used when generating the key pair to \a g
 */
void DsaKeyPairGenerationParameters::setBase(const QByteArray &g)
{
    d_ptr->m_subclassParameters.insert(DsaKeyPairGenerationParametersBase,
                                       QVariant::fromValue<QByteArray>(g));
}

/*!
  \class DhKeyPairGenerationParameters
  \brief Encapsulates parameters related to the generation of an asymmetric
         cryptographic key pair based on the Diffie-Hellman algorithm
  \inmodule SailfishCrypto
  \inheaderfile Crypto/keypairgenerationparameters.h

  This class encapsulates a variety of parameters which will affect how
  the crypto plugin generates a key pair.  Usually, an instance of this class
  will be used when performing a GenerateStoredKeyRequest.

  An example of parameters to generate a 3072-bit DH key pair using the
  key family parameters specified in FIPS-186-3 follows:

  \code
  Sailfish::Crypto::DhKeyPairGenerationParameters dhkpgParams;
  dhkpgParams.setModulusLength(3072);
  dhkpgParams.setPrivateExponentLength(256);
  dhkpgParams.setGenerateFamilyParameters(false);
  \endcode

  Alternatively, the algorithm parameters may be specified explicitly
  via setting the modulus() and base() values:

  \code
  Sailfish::Crypto::DhKeyPairGenerationParameters dhkpgParams;
  dhkpgParams.setModulus(modulusData);
  dhkpgParams.setBase(baseData);
  \endcode
 */

/*!
  \brief Constructs a new DhKeyPairGenerationParameters instance
 */
DhKeyPairGenerationParameters::DhKeyPairGenerationParameters()
    : KeyPairGenerationParameters()
{
    setKeyPairType(KeyPairGenerationParameters::KeyPairDh);
    setModulusLength(3072);
    setPrivateExponentLength(256);
    setGenerateFamilyParameters(false);
}

/*!
  \brief Constructs a copy of the \a other parameters
 */
DhKeyPairGenerationParameters::DhKeyPairGenerationParameters(
        const KeyPairGenerationParameters &other)
    : KeyPairGenerationParameters(other)
{
}

/*!
  \brief Destroys the parameters instance
 */
DhKeyPairGenerationParameters::~DhKeyPairGenerationParameters()
{
}

/*!
  \brief Assigns the \a other parameters to this instance
 */
DhKeyPairGenerationParameters&
DhKeyPairGenerationParameters::operator=(
        const DhKeyPairGenerationParameters &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

bool DhKeyPairGenerationParameters::isValid() const
{
    if (!modulus().isEmpty() && !base().isEmpty())
        return true;

    if (modulusLength() > 0 && privateExponentLength() > 0)
        return true;

    return false;
}

/*!
  \brief Returns the modulus length of the DH key pair to be generated

  This defines the security size of the output key.

  Note that this parameter is only meaningful if the client has not
  provided explicit values for the modulus() and base().
 */
int DhKeyPairGenerationParameters::modulusLength() const
{
    return d_ptr->m_subclassParameters.value(DhKeyPairGenerationParametersModulusLength).toInt();
}

/*!
  \brief Sets the modulus length of the DH key pair to be generated to \a length
 */
void DhKeyPairGenerationParameters::setModulusLength(int length)
{
    d_ptr->m_subclassParameters.insert(DhKeyPairGenerationParametersModulusLength,
                                       QVariant::fromValue<int>(length));
}

/*!
  \brief Returns the private exponent length of the DH key pair to be generated

  This is the length (in bits) of the private exponent which will be generated
  by the base (generator).

  Note that this parameter is only meaningful if the client has not
  provided explicit values for the modulus() and base().
 */
int DhKeyPairGenerationParameters::privateExponentLength() const
{
    return d_ptr->m_subclassParameters.value(DhKeyPairGenerationParametersPrivateExponentLength).toInt();
}

/*!
  \brief Sets the private exponent length of the DH key pair to be generated to \a length
 */
void DhKeyPairGenerationParameters::setPrivateExponentLength(int length)
{
    d_ptr->m_subclassParameters.insert(DhKeyPairGenerationParametersPrivateExponentLength,
                                       QVariant::fromValue<int>(length));
}

/*!
  \brief Returns true if the key should be generated using randomly-generated key family parameters

  The individual parameters (modulus (prime p), private exponent (prime q),
  and base (generator g)) define the key family.  In order for the
  algorithm to work, both parties need to use the same parameters in
  order for their (randomly generated public and private) keys to belong
  to the same family (and thus work).

  If this value is true, the client wants the plugin to generate a key
  pair using randomly generated key family parameters; otherwise,
  the client wants the plugin to generate a key pair using the standard
  key family values specified in FIPS 186-3.

  This value is only meaningful if the client has provided a modulusLength()
  and privateExponentLength(), and is ignored if the client has instead
  provided a modulus() and base().
 */
bool DhKeyPairGenerationParameters::generateFamilyParameters() const
{
    return d_ptr->m_subclassParameters.value(DhKeyPairGenerationParametersGenerateFamilyParameters).toBool();
}

/*!
  \brief Sets whether the key should be generated using randomly-generated key family parameters to \a generate
 */
void DhKeyPairGenerationParameters::setGenerateFamilyParameters(bool generate)
{
    d_ptr->m_subclassParameters.insert(DsaKeyPairGenerationParametersGenerateFamilyParameters,
                                       QVariant::fromValue<bool>(generate));
}

/*!
  \brief Returns the modulus to be used when generating the key pair

  The modulus is also known as the large prime P.
 */
QByteArray DhKeyPairGenerationParameters::modulus() const
{
    return d_ptr->m_subclassParameters.value(DhKeyPairGenerationParametersModulus).toByteArray();
}

/*!
  \brief Sets the modulus to be used when generating the key pair to \a p
 */
void DhKeyPairGenerationParameters::setModulus(const QByteArray &p)
{
    d_ptr->m_subclassParameters.insert(DhKeyPairGenerationParametersModulus,
                                       QVariant::fromValue<QByteArray>(p));
}

/*!
  \brief Returns the base generator to be used when generating the key pair

  The base is also known as the generator G.
 */
QByteArray DhKeyPairGenerationParameters::base() const
{
    return d_ptr->m_subclassParameters.value(DhKeyPairGenerationParametersBase).toByteArray();
}

/*!
  \brief Sets the base generator to be used when generating the key pair \a g
 */
void DhKeyPairGenerationParameters::setBase(const QByteArray &g)
{
    d_ptr->m_subclassParameters.insert(DhKeyPairGenerationParametersBase,
                                       QVariant::fromValue<QByteArray>(g));
}

/*!
  \brief Returns true if the \a lhs parameters are equal to the \a rhs parameters
 */
bool Sailfish::Crypto::operator==(const KeyPairGenerationParameters &lhs, const KeyPairGenerationParameters &rhs)
{
    return lhs.keyPairType() == rhs.keyPairType()
            && lhs.customParameters() == rhs.customParameters()
            && lhs.subclassParameters() == rhs.subclassParameters();
}

/*!
  \brief Returns false if the \a lhs parameters are equal to the \a rhs parameters
 */
bool Sailfish::Crypto::operator!=(const KeyPairGenerationParameters &lhs, const KeyPairGenerationParameters &rhs)
{
    return !operator==(lhs, rhs);
}

/*!
  \brief Returns true if the \a lhs parameters should sort as less than the \a rhs parameters
 */
bool Sailfish::Crypto::operator<(const KeyPairGenerationParameters &lhs, const KeyPairGenerationParameters &rhs)
{
    if (lhs.keyPairType() != rhs.keyPairType())
        return lhs.keyPairType() < rhs.keyPairType();

    if (lhs.customParameters().keys() != rhs.customParameters().keys())
        return lhs.customParameters().keys() < rhs.customParameters().keys();

    for (const auto &key : lhs.customParameters().keys()) {
        if (lhs.customParameters().value(key) != rhs.customParameters().value(key)) {
            // Modified by Shipwright for Qt 6: QVariant has no operator<.
            return QVariant::compare(lhs.customParameters().value(key), rhs.customParameters().value(key)) == QPartialOrdering::Less;
        }
    }

    if (lhs.subclassParameters().keys() != rhs.subclassParameters().keys())
        return lhs.subclassParameters().keys() < rhs.subclassParameters().keys();

    for (const auto &key : lhs.subclassParameters().keys()) {
        if (lhs.subclassParameters().value(key) != rhs.subclassParameters().value(key)) {
            // Modified by Shipwright for Qt 6: QVariant has no operator<.
            return QVariant::compare(lhs.subclassParameters().value(key), rhs.subclassParameters().value(key)) == QPartialOrdering::Less;
        }
    }

    return false;
}
