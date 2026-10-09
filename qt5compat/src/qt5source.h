// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 source compatibility for unported Sailfish apps (keel/qt5compat,
// README.md "Qt 5 JavaScript in app sources").
//
// Sailfish OS ran apps on Qt 5.6, whose JavaScript engine accepted some code
// that Qt 6's rejects at compile time. A file with such code does not load
// at all on Qt 6, and no QML module can stand in for it. Keel therefore
// rewrites those constructs in the app's own QML and JavaScript files before
// Qt compiles them:
//
//   rewriteQt5Source()  the rewrite itself (a JavaScript tokenizer; strings,
//                       comments, template literals and regular expression
//                       literals are never touched). Only code that Qt 6
//                       cannot compile is changed, so code that already
//                       compiles on Qt 6 comes back unchanged.
//   installSourceCompat()  a QQmlAbstractUrlInterceptor on the engine: a QML
//                       or JavaScript file under one of the app's
//                       directories that needs the rewrite is loaded from a
//                       rewritten copy in a cache directory. Qt resolves
//                       relative URLs, imports and qmldir lookups against the
//                       original URL (QQmlDataBlob::finalUrl()), and errors
//                       name the original file, line and column.
//
// SailfishApp::createView() (keel/sailfishapp) installs it for the app's data
// directory; the corpus harness (corpus/harness/keel-load) for the app tree.
#ifndef KEEL_QT5SOURCE_H
#define KEEL_QT5SOURCE_H

#include <QList>
#include <QString>
#include <QStringList>
#include <QStringView>
#include <QUrl>

class QQmlEngine;

namespace KeelQt5Compat {

struct SourceRewrite
{
    QString source;          // the rewritten source (the input when unchanged)
    int constDeclarations = 0; // `const` declarations without an initializer, now `var`
    bool changed() const { return constDeclarations > 0; }
};

// Rewrites the Qt 5-only constructs in one QML or JavaScript file:
//
//   const x;  const a, b = 1;  ->  var   x;  var   a, b = 1;
//     A `const` declaration with a declarator that has no initializer is a
//     SyntaxError in Qt 6 ("Missing initializer in const declaration"). Qt
//     5.6's engine treated `const` like `var` (function scope, assignable), and
//     such code assigns the variable later, so it becomes `var`. The keyword
//     is padded to its length, so columns stay as in the original. `for
//     (const x of y)` and `for (const k in o)` are valid and stay.
//
// Positions are preserved: the result has the same lines and columns.
SourceRewrite rewriteQt5Source(QStringView source);

// The rewrites done by installSourceCompat() on an engine so far.
struct RewrittenFile
{
    QUrl url;           // the app's file
    QString cachedPath; // the rewritten copy Qt compiled
    int constDeclarations = 0;
};

// False when KEEL_QT5COMPAT_SOURCE=0 (the opt-out).
bool sourceCompatEnabled();

// Installs the rewrite on `engine` for QML and JavaScript files below
// `appRoots` (local directories). Rewritten copies are cached, keyed by a
// hash of the original content, in the first writable of:
// $KEEL_QT5COMPAT_CACHE, $XDG_CACHE_HOME/keel/qt5compat (~/.cache/...),
// the app's own cache directory + /keel-qt5compat (the one Sailjail lets an
// app write), and a directory under the system temporary directory. Each
// rewritten file is logged once (category keel.qt5compat.source). Does
// nothing when sourceCompatEnabled() is false, when `appRoots` is empty, or
// when the engine already has it (the roots are then added). The engine
// owns what this creates.
void installSourceCompat(QQmlEngine *engine, const QStringList &appRoots);

QList<RewrittenFile> rewrittenFiles(const QQmlEngine *engine);

} // namespace KeelQt5Compat

#endif // KEEL_QT5SOURCE_H
