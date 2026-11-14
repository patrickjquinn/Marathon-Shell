// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Translations for the qsTrId() strings of Silica's BSD QML. Keel installs,
// once per application: the device's own Silica catalogue for the current
// locale when there is one (/usr/share/translations/sailfishsilica-qt5_*.qm,
// read at run time from the system; not shipped with Keel), and as a
// fallback the engineering English from the BSD QML's //% comments
// (silicastrings.inc), so that ids never show through. See
// installSilicaTranslations() for the order relative to the app's own.
#ifndef KEEL_TRANSLATOR_H
#define KEEL_TRANSLATOR_H

#include <QTranslator>

class KeelSilicaFallbackTranslator : public QTranslator
{
    Q_OBJECT

public:
    using QTranslator::QTranslator;
    QString translate(const char *context, const char *sourceText, const char *disambiguation = nullptr,
                      int n = -1) const override;
    bool isEmpty() const override { return false; }
};

namespace keel {
void installSilicaTranslations();
}

#endif // KEEL_TRANSLATOR_H
