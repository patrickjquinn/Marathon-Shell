#pragma once

#include <QString>

// A Keel app's cover is a second top-level window titled with the marker
// the host passes in KEEL_SHELL_COVER_TITLE (keel/shell/PROTOCOL.md).
namespace KeelCover {

inline const QString &marker() {
    static const QString kMarker = QStringLiteral("keel:cover");
    return kMarker;
}

inline bool isCoverTitle(const QString &title) {
    return title == marker() || title.startsWith(marker() + QLatin1Char(':'));
}

} // namespace KeelCover
