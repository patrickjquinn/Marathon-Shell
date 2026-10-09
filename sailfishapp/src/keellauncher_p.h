// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Internal glue between sailfishapp.cpp and keellauncher.cpp.
#ifndef KEEL_LAUNCHER_P_H
#define KEEL_LAUNCHER_P_H

class QCoreApplication;
class QString;
class QQuickView;

namespace Keel::detail {

// sailfishapp.cpp: <data dir>/translations/<app name>[-<locale>].qm, after
// installEnglishPlurals().
void installTranslations(QCoreApplication *app);

// sailfishapp.cpp: once per application, the lowest-priority translator:
// English singular and plural for qsTr("%n file(s)", "", n) when no catalog
// translates the string (englishPlural()).
void installEnglishPlurals(QCoreApplication *app);

// The English form of a numerus source text for n: "(s)" is dropped for
// n == 1 and becomes "s" otherwise; "(singular|plural)" picks one of the
// two ("%n (entry|entries)"). Null if the text has neither.
QString englishPlural(const QString &source, int n);

// keellauncher.cpp: the booster's preloaded view, once (nullptr otherwise).
QQuickView *takeBoosterView();

// keellauncher.cpp: what direct mode sets before the application exists
// (default surface format and alpha); called by SailfishApp::application().
void prepareApplicationDefaults();

} // namespace Keel::detail

#endif // KEEL_LAUNCHER_P_H
