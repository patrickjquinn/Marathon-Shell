/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTVALUEENCRYPTION_QCA_P_H
#define SAILFISH_ACCOUNTS__ACCOUNTVALUEENCRYPTION_QCA_P_H

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <QtCrypto/QtCrypto>

#include <QtDebug>

QByteArray qca_aes_encrypt_plaintext(const QByteArray &plaintext, const QByteArray &key)
{
    QCA::Initializer init;
    QCA::SecureArray plaintextArray(plaintext);

    if (plaintext.size() == 0 || key.size() == 0) {
        qWarning() << "qca_aes_encrypt_plaintext():"
                   << "invalid arguments, aborting encryption";
        return QByteArray();
    }

    if(!QCA::isSupported("aes128-cbc-pkcs7")) {
        qWarning() << "qca_aes_encrypt_plaintext():"
                   << "failed to initialize encryption context";
        return QByteArray();
    }

    QCA::SymmetricKey symmetricKey(key);
    QCA::InitializationVector initVector(QByteArray("Sailfish.Accounts"));

    QCA::Cipher cipher(QString("aes128"),
                       QCA::Cipher::CBC,
                       QCA::Cipher::DefaultPadding,
                       QCA::Encode,
                       symmetricKey,
                       initVector);

    QCA::SecureArray partial = cipher.update(plaintextArray);
    if (!cipher.ok()) {
        qWarning() << "qca_aes_encrypt_plaintext():"
                   << "encryption failed";
        return QByteArray();
    }

    QCA::SecureArray final = cipher.final();
    if (!cipher.ok()) {
        qWarning() << "qca_aes_encrypt_plaintext():"
                   << "encryption finalization failed";
        return QByteArray();
    }

    QCA::SecureArray ciphertext = partial.append(final);
    return ciphertext.toByteArray();
}

QByteArray qca_aes_decrypt_ciphertext(const QByteArray &ciphertext, const QByteArray &key)
{
    QCA::Initializer init;
    QCA::SecureArray ciphertextArray(ciphertext);

    if (ciphertext.size() == 0 || key.size() == 0) {
        qWarning() << "qca_aes_decrypt_ciphertext():"
                   << "invalid arguments, aborting decryption";
        return QByteArray();
    }

    if(!QCA::isSupported("aes128-cbc-pkcs7")) {
        qWarning() << "qca_aes_decrypt_ciphertext():"
                   << "failed to initialize decryption context";
        return QByteArray();
    }

    QCA::SymmetricKey symmetricKey(key);
    QCA::InitializationVector initVector(QByteArray("Sailfish.Accounts"));

    QCA::Cipher cipher(QString("aes128"),
                       QCA::Cipher::CBC,
                       QCA::Cipher::DefaultPadding,
                       QCA::Decode,
                       symmetricKey,
                       initVector);

    QCA::SecureArray partial = cipher.update(ciphertextArray);
    if (!cipher.ok()) {
        qWarning() << "qca_aes_decrypt_ciphertext():"
                   << "decryption failed";
        return QByteArray();
    }

    QCA::SecureArray final = cipher.final();
    if (!cipher.ok()) {
        qWarning() << "qca_aes_decrypt_ciphertext():"
                   << "decryption finalization failed: key failure";
        return QByteArray();
    }

    QCA::SecureArray plaintext = partial.append(final);
    return plaintext.toByteArray();
}

#endif
