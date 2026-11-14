/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNTVALUEENCODING_P_H
#define SAILFISH_ACCOUNTS__ACCOUNTVALUEENCODING_P_H

#include <QtCore/QString>
#include <QtCore/QByteArray>

static QString encodeValue(const QString &value, const QString &scheme, const QString &key)
{
    QByteArray vutf8 = value.toUtf8();
    QByteArray vb64 = vutf8.toBase64();

    if (scheme.toLower() == QLatin1String("xor")) {
        QByteArray xorkey = "sailfish";
        QString lowerkey = key.toLower();
        bool invalid = lowerkey.isEmpty();

        // search through the supplied key to search for invalid characters
        for (int i = 0; i < lowerkey.length(); ++i) {
            char currchar = lowerkey.at(i).toLatin1();
            if (currchar < 'a' || currchar > 'z') {
                invalid = true;
            }
        }

        if (!invalid)
            xorkey = lowerkey.toLatin1();

        QByteArray xorba;
        int keyidx = xorkey.length();
        for (int i = 0; i < vb64.length(); ++i) {
            keyidx += 1;
            if (keyidx >= xorkey.length())
                keyidx = 0;

            char currchar = vb64.at(i) ^ xorkey.at(keyidx);
            xorba.append(currchar);
        }

        // then base64 encode the xor result.
        return QString::fromLatin1(xorba.toBase64());
    } else if (scheme.toLower() == QLatin1String("rot")) {
        // ascending rotation.
        QByteArray rotba;
        char rotnum = 0;
        for (int i = 0; i < vb64.length(); ++i) {
            char currchar = vb64.at(i);
            currchar += rotnum;
            if (rotnum == 125) // manually wrap at 125 to avoid underflow
                rotnum = 0;
            else
                rotnum += 1;
            rotba.append(currchar);
        }

        // then base64 encode the rotated result.
        return QString::fromLatin1(rotba.toBase64());
    } else {
        return QString::fromLatin1(vb64);
    }
}

static QString decodeValue(const QString &value, const QString &scheme, const QString &key)
{
    if (scheme.toLower() == QLatin1String("xor")) {
        QByteArray xorkey = "sailfish";
        QString lowerkey = key.toLower();
        bool invalid = lowerkey.isEmpty();

        // search through the supplied key to search for invalid characters
        for (int i = 0; i < lowerkey.length(); ++i) {
            char currchar = lowerkey.at(i).toLatin1();
            if (currchar < 'a' || currchar > 'z') {
                invalid = true;
            }
        }

        if (!invalid)
            xorkey = lowerkey.toLatin1();

        QByteArray encoded = value.toLatin1();
        QByteArray xorba = QByteArray::fromBase64(encoded);
        QByteArray vb64;
        int keyidx = xorkey.length();
        for (int i = 0; i < xorba.length(); ++i) {
            keyidx += 1;
            if (keyidx >= xorkey.length())
                keyidx = 0;

            char currchar = xorba.at(i) ^ xorkey.at(keyidx);
            vb64.append(currchar);
        }

        QByteArray vutf8 = QByteArray::fromBase64(vb64);
        return QString::fromUtf8(vutf8.constData());
    } else if (scheme.toLower() == QLatin1String("rot")) {
        // ascending rotation.
        QByteArray encoded = value.toLatin1();
        QByteArray rotba = QByteArray::fromBase64(encoded);
        QByteArray vb64;
        char rotnum = 0;
        for (int i = 0; i < rotba.length(); ++i) {
            char currchar = rotba.at(i);
            currchar -= rotnum;
            if (rotnum == 125) // manually wrap at 125 to avoid underflow
                rotnum = 0;
            else
                rotnum += 1;
            vb64.append(currchar);
        }

        QByteArray vutf8 = QByteArray::fromBase64(vb64);
        return QString::fromUtf8(vutf8.constData());
    } else {
        QByteArray vb64 = value.toLatin1();
        QByteArray vutf8 = QByteArray::fromBase64(vb64);
        return QString::fromUtf8(vutf8.constData());
    }
}

#endif
