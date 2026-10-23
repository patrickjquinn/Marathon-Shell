#ifndef NATIVEINPUT_H
#define NATIVEINPUT_H

#include <QStringList>

namespace NativeInput {

    // libcosmic/iced binds wl_touch but does not activate widgets from it.
    // Keep this compatibility path toolkit-scoped.
    inline bool needsPointerFallback(const QStringList &desktopTerms) {
        for (const QString &term : desktopTerms) {
            if (term.compare(QStringLiteral("cosmic"), Qt::CaseInsensitive) == 0)
                return true;
        }
        return false;
    }

} // namespace NativeInput

#endif
