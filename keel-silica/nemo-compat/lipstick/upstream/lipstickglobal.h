// SPDX-FileCopyrightText: 2012 Timur Kristóf
// SPDX-License-Identifier: LGPL-2.1-only


// This file is part of lipstick, a QML desktop library
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License version 2.1 as published by the Free Software Foundation
// and appearing in the file LICENSE.LGPL included in the packaging
// of this file.
//
// This code is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// Copyright (c) 2012, Timur Kristóf <venemo@fedoraproject.org>

#ifndef LIPSTICKGLOBAL_H
#define LIPSTICKGLOBAL_H

#include <QtGlobal>

#if defined(LIPSTICK_BUILD_LIBRARY)
#define LIPSTICK_EXPORT Q_DECL_EXPORT
#else
#define LIPSTICK_EXPORT Q_DECL_IMPORT
#endif

#endif // LIPSTICKGLOBAL_H
