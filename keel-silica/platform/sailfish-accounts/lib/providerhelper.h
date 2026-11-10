/*
 * SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2020 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__PROVIDERHELPER_H
#define SAILFISH_ACCOUNTS__PROVIDERHELPER_H

#include <QSet>
#include <QString>

bool allowedProvider(const QSet<QString> &tags);

#endif
