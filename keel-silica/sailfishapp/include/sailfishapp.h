// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's Qt6 libsailfishapp: the public SailfishApp API (names and
// signatures as documented for libsailfishapp) implemented for Qt6 apps
// that run on Keel. Apps keep `#include <sailfishapp.h>` and
// `PKGCONFIG += sailfishapp` / pkg_check_modules(... sailfishapp).
#ifndef KEEL_SAILFISHAPP_H
#define KEEL_SAILFISHAPP_H

#include <QUrl>
#include <QtGlobal>

class QGuiApplication;
class QQuickView;
class QString;

#if defined(KEEL_SAILFISHAPP_LIBRARY)
#define SAILFISHAPP_EXPORT Q_DECL_EXPORT
#else
#define SAILFISHAPP_EXPORT Q_DECL_IMPORT
#endif

namespace SailfishApp {

// The application object (created on the first call; later calls return
// it). Sets the application name from argv[0] unless the app set one, and
// installs translations from <data dir>/translations.
SAILFISHAPP_EXPORT QGuiApplication *application(int &argc, char **argv);

// A QQuickView set up the way Silica apps expect: SizeRootObjectToView,
// translucent (keel-shell shows the ambience behind it).
SAILFISHAPP_EXPORT QQuickView *createView();

// file:// URL of `filename` in the app's data directory,
// /usr/share/<application name>/ (KEEL_SAILFISHAPP_DATADIR overrides it).
SAILFISHAPP_EXPORT QUrl pathTo(const QString &filename);

// pathTo("qml/<application name>.qml").
SAILFISHAPP_EXPORT QUrl pathToMainQml();

// application() + createView() + pathToMainQml(), shown, then exec().
SAILFISHAPP_EXPORT int main(int &argc, char **argv);

} // namespace SailfishApp

// As in libsailfishapp: the app's main() is exported so that a launcher can
// find it.
Q_DECL_EXPORT int main(int argc, char *argv[]);

#endif // KEEL_SAILFISHAPP_H
