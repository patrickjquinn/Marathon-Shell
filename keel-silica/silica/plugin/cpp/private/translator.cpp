// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// See translator.h.

#include "translator.h"

#include <QCoreApplication>
#include <QHash>
#include <QLocale>

namespace {
struct Entry
{
    const char *id;
    const char *text;
};
const Entry kStrings[] = {
#include "silicastrings.inc"
};
} // namespace

QString KeelSilicaFallbackTranslator::translate(const char *context, const char *sourceText,
                                                const char *disambiguation, int n) const
{
    Q_UNUSED(disambiguation)
    Q_UNUSED(n)
    if (context && *context)
        return QString();
    static const QHash<QByteArray, QString> table = [] {
        QHash<QByteArray, QString> t;
        for (const Entry &e : kStrings)
            t.insert(e.id, QString::fromUtf8(e.text));
        return t;
    }();
    return table.value(QByteArray(sourceText));
}

void keel::installSilicaTranslations()
{
    static bool installed = false;
    if (installed || !QCoreApplication::instance())
        return;
    installed = true;
    auto *app = QCoreApplication::instance();
    // Qt asks the most recently installed translator first. Both of Keel's
    // are installed when the first engine imports Sailfish.Silica, which is
    // usually after the app has installed its own, so they are asked before
    // the app's: the device catalogue first, then the engineering English.
    // The fallback answers only the Silica ids in silicastrings.inc (an empty
    // answer passes the question on), so an app is affected only if it ships
    // its own text for one of Silica's own ids.
    QCoreApplication::installTranslator(new KeelSilicaFallbackTranslator(app));
    // Owned by the application object (its QObject parent).
    auto *device = new QTranslator(app); // NOLINT(clang-analyzer-cplusplus.NewDeleteLeaks)
    if (device->load(QLocale(), QStringLiteral("sailfishsilica-qt5"), QStringLiteral("_"),
                     QStringLiteral("/usr/share/translations")))
        QCoreApplication::installTranslator(device);
    else
        delete device;
}
