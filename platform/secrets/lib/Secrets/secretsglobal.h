// SPDX-FileCopyrightText: 2017 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2017 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#ifndef LIBSAILFISHSECRETS_SECRETSGLOBAL_H
#define LIBSAILFISHSECRETS_SECRETSGLOBAL_H

#ifdef SAILFISH_SECRETS_LIBRARY_BUILD
  #define SAILFISH_SECRETS_API Q_DECL_EXPORT
#else
  #define SAILFISH_SECRETS_API Q_DECL_IMPORT
#endif

#endif // LIBSAILFISHSECRETS_SECRETSGLOBAL_H
