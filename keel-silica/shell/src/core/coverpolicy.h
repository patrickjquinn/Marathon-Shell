// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The cover contract (see PROTOCOL.md, "Cover surface"). A nested toplevel is
// the app's cover when EITHER
//   * its title is exactly the marker ("keel:cover") or starts with the
//     marker followed by ':' (e.g. "keel:cover:Weather"), OR
//   * its app_id / wl_shell class ends with ".keel-cover".
// Child surfaces (transients, popups, subsurfaces) are never covers
// themselves; they follow their parent.

#ifndef KEEL_COVERPOLICY_H
#define KEEL_COVERPOLICY_H

#include "surfaceinfo.h"

namespace keel {

class CoverPolicy
{
public:
    CoverPolicy();
    explicit CoverPolicy(const QString &titleMarker);

    static QString defaultTitleMarker();   // "keel:cover"
    static QString appIdSuffix();          // ".keel-cover"

    QString titleMarker() const { return m_titleMarker; }

    bool isCover(const SurfaceInfo &info) const;
    bool titleMatches(const QString &title) const;
    static bool appIdMatches(const QString &appId);

    // Human-readable part of the title after "keel:cover:", if any.
    QString coverLabel(const QString &title) const;

private:
    QString m_titleMarker;
};

} // namespace keel

#endif // KEEL_COVERPOLICY_H
