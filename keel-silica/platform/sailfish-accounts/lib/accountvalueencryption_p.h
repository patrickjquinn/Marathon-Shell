/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTVALUEENCRYPTION_P_H
#define SAILFISH_ACCOUNTS__ACCOUNTVALUEENCRYPTION_P_H

#include <QByteArray>

#ifdef USE_OSSLEVP_ENCRYPTION
#include "accountvalueencryption_osslevp_p.h"
#elif USE_QCA_ENCRYPTION
#include "accountvalueencryption_qca_p.h"
#else
#include "accountvalueencoding_p.h"
#endif

QByteArray aes_encrypt_plaintext(const QByteArray &plaintext, const QByteArray &key)
{
#ifdef USE_OSSLEVP_ENCRYPTION
    QByteArray encryptedData;
    unsigned char *encrypted = NULL;
    int size = osslevp_aes_encrypt_plaintext((const unsigned char *)key.constData(),
                                             key.size(),
                                             (const unsigned char *)plaintext.constData(),
                                             plaintext.size(),
                                             &encrypted);
    if (size <= 0) {
        return encryptedData;
    }

    encryptedData = QByteArray::fromRawData((char *)encrypted, size);
    free(encrypted);
    return encryptedData;
#elif USE_QCA_ENCRYPTION
    return qca_aes_encrypt_plaintext(plaintext, key);
#else
    return encodeValue(QString::fromUtf8(plaintext), QLatin1String("xor"), QString::fromUtf8(key)).toLatin1();
#endif
}

QByteArray aes_decrypt_ciphertext(const QByteArray &ciphertext, const QByteArray &key)
{
#ifdef USE_OSSLEVP_ENCRYPTION
    QByteArray decryptedData;
    unsigned char *decrypted = NULL;
    int size = osslevp_aes_decrypt_ciphertext((const unsigned char *)key.constData(),
                                              key.size(),
                                              (const unsigned char *)ciphertext.constData(),
                                              ciphertext.size(),
                                              &decrypted);
    if (size <= 0) {
        return decryptedData;
    }

    decryptedData = QByteArray::fromRawData((char *)decrypted, size);
    free(decrypted);
    return decryptedData;
#elif USE_QCA_ENCRYPTION
    return qca_aes_decrypt_ciphertext(ciphertext, key);
#else
    return decodeValue(QString::fromUtf8(ciphertext), QLatin1String("xor"), QString::fromUtf8(key)).toLatin1();
#endif
}

#endif
