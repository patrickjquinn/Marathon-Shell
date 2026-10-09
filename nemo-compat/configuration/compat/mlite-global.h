// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's stand-in for mlite's export macro header. The fallback MDConf
// classes are compiled into the Nemo.Configuration plugin, so nothing is
// exported or imported.
#ifndef MLITE_GLOBAL_H
#define MLITE_GLOBAL_H

#include <QtCore/qglobal.h>

#define MLITESHARED_EXPORT

#endif // MLITE_GLOBAL_H
