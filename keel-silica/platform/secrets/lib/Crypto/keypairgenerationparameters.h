// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_KEYPAIRGENERATIONPARAMETERS_H
#define LIBSAILFISHCRYPTO_KEYPAIRGENERATIONPARAMETERS_H

#include "Crypto/cryptoglobal.h"
#include "Crypto/cryptomanager.h"
#include "Crypto/key.h"

#include <QtCore/QByteArray>
#include <QtCore/QVariantMap>
#include <QtCore/QSharedDataPointer>
#include <QtCore/QMetaType>

namespace Sailfish {

namespace Crypto {

class KeyPairGenerationParametersPrivate;
class SAILFISH_CRYPTO_API KeyPairGenerationParameters {
    Q_GADGET
    Q_PROPERTY(KeyPairType keyPairType READ keyPairType WRITE setKeyPairType)
    Q_PROPERTY(QVariantMap customParameters READ customParameters WRITE setCustomParameters)

public:
    enum KeyPairType {
        KeyPairUnknown          = CryptoManager::AlgorithmUnknown,
        KeyPairCustom           = CryptoManager::AlgorithmCustom,
        KeyPairDh               = CryptoManager::AlgorithmDh,
        KeyPairDsa              = CryptoManager::AlgorithmDsa,
        KeyPairRsa              = CryptoManager::AlgorithmRsa,
        KeyPairEc               = CryptoManager::AlgorithmEc,
        LastKeyPairType         = CryptoManager::LastAlgorithm
    };
    Q_ENUM(KeyPairType)

    KeyPairGenerationParameters();
    KeyPairGenerationParameters(const KeyPairGenerationParameters &other);
    virtual ~KeyPairGenerationParameters();

    KeyPairGenerationParameters& operator=(const KeyPairGenerationParameters &other);

    virtual bool isValid() const;

    KeyPairType keyPairType() const;
    void setKeyPairType(KeyPairType keyPairType);

    QVariantMap customParameters() const;
    void setCustomParameters(const QVariantMap &params);

    QVariantMap subclassParameters() const;

protected:
    QSharedDataPointer<KeyPairGenerationParametersPrivate> d_ptr;
    friend class KeyPairGenerationParametersPrivate;
    friend class EcKeyPairGenerationParameters;
    friend class RsaKeyPairGenerationParameters;
    friend class DsaKeyPairGenerationParameters;
    friend class DhKeyPairGenerationParameters;
};

class SAILFISH_CRYPTO_API EcKeyPairGenerationParameters : public KeyPairGenerationParameters {
    Q_GADGET
    Q_PROPERTY(Sailfish::Crypto::CryptoManager::EllipticCurve ellipticCurve READ ellipticCurve WRITE setEllipticCurve)

public:
    EcKeyPairGenerationParameters();
    EcKeyPairGenerationParameters(const KeyPairGenerationParameters &other);
    EcKeyPairGenerationParameters(const EcKeyPairGenerationParameters &other) = default;
    ~EcKeyPairGenerationParameters();

    EcKeyPairGenerationParameters& operator=(const EcKeyPairGenerationParameters &other);
    bool isValid() const Q_DECL_OVERRIDE;

    Sailfish::Crypto::CryptoManager::EllipticCurve ellipticCurve() const;
    void setEllipticCurve(Sailfish::Crypto::CryptoManager::EllipticCurve curve);
};

class SAILFISH_CRYPTO_API RsaKeyPairGenerationParameters : public KeyPairGenerationParameters {
    Q_GADGET
    Q_PROPERTY(int modulusLength READ modulusLength WRITE setModulusLength)
    Q_PROPERTY(int numberPrimes READ numberPrimes WRITE setNumberPrimes)
    Q_PROPERTY(quint64 publicExponent READ publicExponent WRITE setPublicExponent)

public:
    RsaKeyPairGenerationParameters();
    RsaKeyPairGenerationParameters(const KeyPairGenerationParameters &other);
    RsaKeyPairGenerationParameters(const RsaKeyPairGenerationParameters &other) = default;
    ~RsaKeyPairGenerationParameters();

    RsaKeyPairGenerationParameters& operator=(const RsaKeyPairGenerationParameters &other);
    bool isValid() const Q_DECL_OVERRIDE;

    int modulusLength() const;
    void setModulusLength(int length);

    int numberPrimes() const;
    void setNumberPrimes(int primes);

    quint64 publicExponent() const;
    void setPublicExponent(quint64 exponent);
};

class SAILFISH_CRYPTO_API DsaKeyPairGenerationParameters : public KeyPairGenerationParameters {
    Q_GADGET
    Q_PROPERTY(int modulusLength READ modulusLength WRITE setModulusLength)
    Q_PROPERTY(int primeFactorLength READ primeFactorLength WRITE setPrimeFactorLength)
    Q_PROPERTY(bool generateFamilyParameters READ generateFamilyParameters WRITE setGenerateFamilyParameters)
    Q_PROPERTY(QByteArray modulus READ modulus WRITE setModulus)
    Q_PROPERTY(QByteArray primeFactor READ primeFactor WRITE setPrimeFactor)
    Q_PROPERTY(QByteArray base READ base WRITE setBase)

public:
    DsaKeyPairGenerationParameters();
    DsaKeyPairGenerationParameters(const KeyPairGenerationParameters &other);
    DsaKeyPairGenerationParameters(const DsaKeyPairGenerationParameters &other) = default;
    ~DsaKeyPairGenerationParameters();

    DsaKeyPairGenerationParameters& operator=(const DsaKeyPairGenerationParameters &other);
    bool isValid() const Q_DECL_OVERRIDE;

    int modulusLength() const;
    void setModulusLength(int length);

    int primeFactorLength() const;
    void setPrimeFactorLength(int length);

    bool generateFamilyParameters() const;
    void setGenerateFamilyParameters(bool generate);

    // prime p
    QByteArray modulus() const;
    void setModulus(const QByteArray &p);

    // sub-prime q
    QByteArray primeFactor() const;
    void setPrimeFactor(const QByteArray &q);

    // generator g
    QByteArray base() const;
    void setBase(const QByteArray &g);
};

class SAILFISH_CRYPTO_API DhKeyPairGenerationParameters : public KeyPairGenerationParameters {
    Q_GADGET
    Q_PROPERTY(int modulusLength READ modulusLength WRITE setModulusLength)
    Q_PROPERTY(int privateExponentLength READ privateExponentLength WRITE setPrivateExponentLength)
    Q_PROPERTY(bool generateFamilyParameters READ generateFamilyParameters WRITE setGenerateFamilyParameters)
    Q_PROPERTY(QByteArray modulus READ modulus WRITE setModulus)
    Q_PROPERTY(QByteArray base READ base WRITE setBase)

public:
    DhKeyPairGenerationParameters();
    DhKeyPairGenerationParameters(const KeyPairGenerationParameters &other);
    DhKeyPairGenerationParameters(const DhKeyPairGenerationParameters &other) = default;
    ~DhKeyPairGenerationParameters();

    DhKeyPairGenerationParameters& operator=(const DhKeyPairGenerationParameters &other);
    bool isValid() const Q_DECL_OVERRIDE;

    int modulusLength() const;
    void setModulusLength(int length);

    int privateExponentLength() const;
    void setPrivateExponentLength(int length);

    bool generateFamilyParameters() const;
    void setGenerateFamilyParameters(bool generate);

    // prime p
    QByteArray modulus() const;
    void setModulus(const QByteArray &p);

    // generator g
    QByteArray base() const;
    void setBase(const QByteArray &g);
};

bool operator==(const Sailfish::Crypto::KeyPairGenerationParameters &lhs, const Sailfish::Crypto::KeyPairGenerationParameters &rhs) SAILFISH_CRYPTO_API;
bool operator!=(const Sailfish::Crypto::KeyPairGenerationParameters &lhs, const Sailfish::Crypto::KeyPairGenerationParameters &rhs) SAILFISH_CRYPTO_API;
bool operator<(const Sailfish::Crypto::KeyPairGenerationParameters &lhs, const Sailfish::Crypto::KeyPairGenerationParameters &rhs) SAILFISH_CRYPTO_API;

} // Crypto

} // Sailfish

Q_DECLARE_METATYPE(Sailfish::Crypto::KeyPairGenerationParameters::KeyPairType);

Q_DECLARE_METATYPE(Sailfish::Crypto::KeyPairGenerationParameters);
Q_DECLARE_TYPEINFO(Sailfish::Crypto::KeyPairGenerationParameters, Q_MOVABLE_TYPE);

Q_DECLARE_METATYPE(Sailfish::Crypto::EcKeyPairGenerationParameters);
Q_DECLARE_TYPEINFO(Sailfish::Crypto::EcKeyPairGenerationParameters, Q_MOVABLE_TYPE);

Q_DECLARE_METATYPE(Sailfish::Crypto::RsaKeyPairGenerationParameters);
Q_DECLARE_TYPEINFO(Sailfish::Crypto::RsaKeyPairGenerationParameters, Q_MOVABLE_TYPE);

Q_DECLARE_METATYPE(Sailfish::Crypto::DsaKeyPairGenerationParameters);
Q_DECLARE_TYPEINFO(Sailfish::Crypto::DsaKeyPairGenerationParameters, Q_MOVABLE_TYPE);

Q_DECLARE_METATYPE(Sailfish::Crypto::DhKeyPairGenerationParameters);
Q_DECLARE_TYPEINFO(Sailfish::Crypto::DhKeyPairGenerationParameters, Q_MOVABLE_TYPE);

#endif // LIBSAILFISHCRYPTO_KEYPAIRGENERATIONPARAMETERS_H
