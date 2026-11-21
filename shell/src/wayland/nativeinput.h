#ifndef NATIVEINPUT_H
#define NATIVEINPUT_H

#include <QStringList>

namespace NativeInput {

    // libcosmic/iced and Telegram Desktop bind wl_touch but do not activate
    // widgets from it. Keep this compatibility path toolkit-scoped.
    inline bool needsPointerFallback(const QStringList &desktopTerms) {
        for (const QString &term : desktopTerms) {
            if (term.compare(QStringLiteral("cosmic"), Qt::CaseInsensitive) == 0 ||
                term.compare(QStringLiteral("tdesktop"), Qt::CaseInsensitive) == 0)
                return true;
        }
        return false;
    }

} // namespace NativeInput

#endif
