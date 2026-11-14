// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHCRYPTO_CRYPTOGLOBAL_H
#define LIBSAILFISHCRYPTO_CRYPTOGLOBAL_H

#ifdef SAILFISH_CRYPTO_LIBRARY_BUILD
  #define SAILFISH_CRYPTO_API Q_DECL_EXPORT
#else
  #define SAILFISH_CRYPTO_API Q_DECL_IMPORT
#endif

#endif // LIBSAILFISHCRYPTO_CRYPTOGLOBAL_H
