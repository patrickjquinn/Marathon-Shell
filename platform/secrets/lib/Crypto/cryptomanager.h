// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_CRYPTOMANAGER_H
#define LIBSAILFISHCRYPTO_CRYPTOMANAGER_H

#include "Crypto/cryptoglobal.h"

#include <QtCore/QObject>
#include <QtCore/QString>

namespace Sailfish {

namespace Crypto {

class CryptoManagerPrivate;
class SAILFISH_CRYPTO_API CryptoManager : public QObject
{
    Q_OBJECT

public:
    static const QString DefaultCryptoPluginName;
    static const QString DefaultCryptoStoragePluginName;

    enum Algorithm {
        AlgorithmUnknown        = 0,
        AlgorithmCustom         = 1,
    FirstAsymmetricAlgorithm    = 10,
        AlgorithmRsa            = 10,
        AlgorithmDsa            = 20,
        AlgorithmDh             = 30,
        AlgorithmEc             = 40,
        AlgorithmEcDsa,
        AlgorithmEdDsa,
        AlgorithmEcDh,
        AlgorithmEcMqv,
    LastAsymmetricAlgorithm     = 255,
    FirstSymmetricAlgorithm,
        AlgorithmAes            = 260,
        AlgorithmGost           = 270,
        AlgorithmTdea           = 280,
        AlgorithmTdes           = AlgorithmTdea,
        AlgorithmBlowfish       = 290,
        AlgorithmSalsa          = 300,
        AlgorithmSalsa20        = AlgorithmSalsa,
        AlgorithmChaCha         = 310,
        AlgorithmChaCha20       = AlgorithmChaCha,
        AlgorithmRc4            = 320,
        AlgorithmRc5            = 330,
        AlgorithmRc6            = 340,
        AlgorithmSquare         = 350,
        AlgorithmSerpent        = 360,
        AlgorithmPanama         = 370,
    LastSymmetricAlgorithm      = 4095, // reserve
    LastAlgorithm               = LastSymmetricAlgorithm // reserve
    };
    Q_ENUM(Algorithm)

    enum BlockMode {
        BlockModeUnknown    = 0,
        BlockModeCustom,
        BlockModeEcb,
        BlockModeCbc,
        BlockModePcbc,
        BlockModeCfb1,
        BlockModeCfb8,
        BlockModeCfb128,
        BlockModeOfb,
        BlockModeCtr,
        BlockModeGcm,
        BlockModeLrw,
        BlockModeXex,
        BlockModeXts,
        BlockModeCmc,
        BlockModeEme,
        BlockModeCcm,
        LastBlockMode       = 255 // reserve
    };
    Q_ENUM(BlockMode)

    enum EncryptionPadding {
        EncryptionPaddingUnknown    = 0,
        EncryptionPaddingCustom,
        EncryptionPaddingNone,
        EncryptionPaddingPkcs7,
        EncryptionPaddingRsaOaep,
        EncryptionPaddingRsaOaepMgf1,
        EncryptionPaddingRsaPkcs1,
        EncryptionPaddingAnsiX923,
        LastEncryptionPadding       = 255 // reserve
    };
    Q_ENUM(EncryptionPadding)

    enum SignaturePadding {
        SignaturePaddingUnknown     = 0,
        SignaturePaddingCustom,
        SignaturePaddingNone,
        SignaturePaddingRsaPss,
        SignaturePaddingRsaPkcs1    = EncryptionPaddingRsaPkcs1,
        SignaturePaddingAnsiX923    = EncryptionPaddingAnsiX923,
        LastSignaturePadding        = 255 // reserve
    };
    Q_ENUM(SignaturePadding)

    enum DigestFunction {
        DigestUnknown       = 0,
        DigestCustom        = 1,
        DigestMd5           = 5,
        DigestSha1          = 10,
        DigestSha2_224      = 20,
        DigestSha2_256      = 21,
        DigestSha256        = DigestSha2_256,
        DigestSha2_384      = 22,
        DigestSha2_512      = 23,
        DigestSha512        = DigestSha2_512,
        DigestSha2_512_224  = 24,
        DigestSha2_512_256  = 25,
        DigestSha3_224      = 30,
        DigestSha3_256,
        DigestSha3_384,
        DigestSha3_512,
        DigestShake128,
        DigestShake256,
        DigestGost_94       = 40,
        DigestGost_2012_256,
        DigestGost_2012_512,
        DigestBlake         = 50,
        DigestBlake2,
        DigestBlake2b,
        DigestBlake2s,
        DigestWhirlpool     = 60,
        DigestRipeMd        = 70,
        DigestRipeMd128_256,
        DigestRipeMd160,
        DigestRipeMd320,
        DigestTiger         = 80,
        DigestTiger128,
        DigestTiger160,
        DigestTiger192,
        DigestTiger2,
        DigestTiger2_128,
        DigestTiger2_160,
        DigestTiger2_192,
        DigestRadioGatun    = 90,
        LastDigestFunction  = 4095 // reserve
    };
    Q_ENUM(DigestFunction)

    enum MessageAuthenticationCode {
        MacUnknown          = 0,
        MacCustom           = 1,
        MacHmac             = 10,
        MacCmac             = 20,
        MacVmac             = 30,
        MacPoly1305         = 40,
        LastMac             = 255 // reserve
    };
    Q_ENUM(MessageAuthenticationCode)

    enum KeyDerivationFunction {
        KdfUnknown          = 0,
        KdfCustom           = 1,
        KdfPkcs5Pbkdf2      = 10,
        KdfHkdf             = 20,
        KdfBcrypt           = 30,
        KdfScrypt           = 40,
        KdfArgon2           = 50,
        KdfArgon2d          = KdfArgon2,
        KdfArgon2i          = 51,
        KdfArgon2id         = 52,
        KdfLyra2            = 60,
        LastKdf             = 255 // reserve
    };
    Q_ENUM(KeyDerivationFunction)

    enum EllipticCurve {
        CurveUnknown            = 0,

        // SECT curves
        CurveSect163k1          = 10,
        CurveSect163r1,
        CurveSect163r2,
        CurveSect193r1,
        CurveSect193r2,
        CurveSect233k1,
        CurveSect233r1,
        CurveSect239k1,
        CurveSect283k1,
        CurveSect283r1,
        CurveSect409k1,
        CurveSect409r1,
        CurveSect571k1,
        CurveSect571r1,

        // SECP curves
        CurveSecp160k1          = 50,
        CurveSecp160r1,
        CurveSecp160r2,
        CurveSecp192k1,
        CurveSecp192r1,
        CurveSecp224k1,
        CurveSecp224r1,
        CurveSecp256k1,
        CurveSecp256r1,
        CurveSecp384r1,
        CurveSecp521r1,

        // NIST curves
        CurveNistK163           = CurveSect163k1,
        CurveNistB163           = CurveSect163r2,
        CurveNistK233           = CurveSect233k1,
        CurveNistB233           = CurveSect233r1,
        CurveNistK283           = CurveSect283k1,
        CurveNistB283           = CurveSect283r1,
        CurveNistK409           = CurveSect409k1,
        CurveNistB409           = CurveSect409r1,
        CurveNistK571           = CurveSect571k1,
        CurveNistB571           = CurveSect571k1,
        CurveNistP192           = CurveSecp192r1,
        CurveNistP224           = CurveSecp224r1,
        CurveNistP256           = CurveSecp256r1,
        CurveNistP384           = CurveSecp384r1,
        CurveNistP521           = CurveSecp521r1,

        // ANSI X9.62 primary field curves
        CurveAX962prime192v1    = CurveSecp192r1,
        CurveAX962prime192v2    = 101,
        CurveAX962prime192v3,
        CurveAX962prime239v1,
        CurveAX962prime239v2,
        CurveAX962prime239v3,
        CurveAX962prime256v1    = CurveSecp256r1,

        // ANSI X9.62 binary field curves
        CurveAX962c2pnb163v1    = 150,
        CurveAX962c2pnb163v2,
        CurveAX962c2pnb163v3,
        CurveAX962c2pnb176v1,
        CurveAX962c2tnb191v1,
        CurveAX962c2tnb191v2,
        CurveAX962c2tnb191v3,
        CurveAX962c2pnb208w1,
        CurveAX962c2tnb239v1,
        CurveAX962c2tnb239v2,
        CurveAX962c2tnb239v3,
        CurveAX962c2pnb272w1,
        CurveAX962c2pnb304w1,
        CurveAX962c2tnb359v1,
        CurveAX962c2pnb368w1,
        CurveAX962c2tnb431r1,

        // WTLS
        CurveWapWsgIdmEcidWtls1 = 200,
        CurveWapWsgIdmEcidWtls2,
        CurveWapWsgIdmEcidWtls3,
        CurveWapWsgIdmEcidWtls4,
        CurveWapWsgIdmEcidWtls5,
        CurveWapWsgIdmEcidWtls6,
        CurveWapWsgIdmEcidWtls7,
        CurveWapWsgIdmEcidWtls8,
        CurveWapWsgIdmEcidWtls9,
        CurveWapWsgIdmEcidWtls10,
        CurveWapWsgIdmEcidWtls11,
        CurveWapWsgIdmEcidWtls12,

        // Independent "special" curves
        Curve25519          = 250,  // 128 bit security
        Curve41417,
        Curve1174,
        CurveM221,
        CurveE222,
        CurveE382,
        CurveM383,
        Curve448,  // 224 bit security
        CurveEd448Goldilocks,
        CurveM511,
        CurveE521,

        // Brainpool "random" prime curves
        CurveBrainpoolP160r1= 300,
        CurveBrainpoolP160t1,
        CurveBrainpoolP192r1,
        CurveBrainpoolP192t1,
        CurveBrainpoolP224r1,
        CurveBrainpoolP224t1,
        CurveBrainpoolP256r1,
        CurveBrainpoolP256t1,
        CurveBrainpoolP320r1,
        CurveBrainpoolP320t1,
        CurveBrainpoolP384r1,
        CurveBrainpoolP384t1,
        CurveBrainpoolP512r1,
        CurveBrainpoolP512t1,

        LastCurve           = 4096 // reserve
    };
    Q_ENUM(EllipticCurve)

    enum Operation {
        OperationUnknown        = 0,
        OperationCustom         = 1,
        OperationSign           = 2,
        OperationVerify         = 4,
        OperationEncrypt        = 8,
        OperationDecrypt        = 16,
        OperationCalculateDigest= 32,
        OperationCalculateMac   = 64,
        OperationDeriveKey      = 128
    };
    Q_ENUM(Operation)
    Q_DECLARE_FLAGS(Operations, Operation)
    Q_FLAG(Operations)

    enum VerificationStatusType {
        VerificationStatusUnknown = 0,
        VerificationSucceeded = 1,
        VerificationFailed = 2,
        VerificationSignatureInvalid = 4,
        VerificationSignatureExpired = 8,
        VerificationKeyExpired = 16,
        VerificationKeyRevoked = 32,
        VerificationKeyInvalid = 64
    };
    Q_ENUM(VerificationStatusType)
    Q_DECLARE_FLAGS(VerificationStatus, VerificationStatusType)
    Q_FLAG(VerificationStatus)

    CryptoManager(QObject *parent = Q_NULLPTR);
    virtual ~CryptoManager();

    bool isInitialized() const;

protected:
    CryptoManagerPrivate *pimpl() const; // for unit tests

private:
    QScopedPointer<CryptoManagerPrivate> const d_ptr;
    Q_DECLARE_PRIVATE(CryptoManager)
    friend class CalculateDigestRequest;
    friend class CipherRequest;
    friend class DecryptRequest;
    friend class DeleteStoredKeyRequest;
    friend class EncryptRequest;
    friend class GenerateKeyRequest;
    friend class GenerateRandomDataRequest;
    friend class GenerateStoredKeyRequest;
    friend class ImportKeyRequest;
    friend class ImportStoredKeyRequest;
    friend class GenerateInitializationVectorRequest;
    friend class LockCodeRequest;
    friend class PluginInfoRequest;
    friend class SeedRandomDataGeneratorRequest;
    friend class SignRequest;
    friend class StoredKeyIdentifiersRequest;
    friend class StoredKeyRequest;
    friend class VerifyRequest;
};

} // namespace Crypto

} // namespace Sailfish

Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::Algorithm);
Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::BlockMode);
Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::EncryptionPadding);
Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::SignaturePadding);
Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::DigestFunction);
Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::Operation);
Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::Operations);
Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::VerificationStatusType);
Q_DECLARE_METATYPE(Sailfish::Crypto::CryptoManager::VerificationStatus);
Q_DECLARE_OPERATORS_FOR_FLAGS(Sailfish::Crypto::CryptoManager::Operations);
Q_DECLARE_OPERATORS_FOR_FLAGS(Sailfish::Crypto::CryptoManager::VerificationStatus);

#endif // LIBSAILFISHCRYPTO_CRYPTOMANAGER_H
