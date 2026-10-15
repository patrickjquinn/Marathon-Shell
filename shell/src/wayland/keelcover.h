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

// A Keel app's dialog (Lipstick's CATEGORY=dialog, like Pilot's overlay): a
// second top-level window titled with this marker, shown above the app on
// screen. Not in keel/shell/PROTOCOL.md v1 yet.
namespace KeelDialog {

inline bool isDialogTitle(const QString &title) {
    static const QString kMarker = QStringLiteral("keel:dialog");
    return title == kMarker || title.startsWith(kMarker + QLatin1Char(':'));
}

} // namespace KeelDialog
