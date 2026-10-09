// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "coverpolicy.h"

namespace keel {

QString windowRoleName(WindowRole role)
{
    switch (role) {
    case WindowRole::Main:
        return QStringLiteral("main");
    case WindowRole::Cover:
        return QStringLiteral("cover");
    case WindowRole::Secondary:
        return QStringLiteral("secondary");
    }
    return QString();
}

CoverPolicy::CoverPolicy()
    : m_titleMarker(defaultTitleMarker())
{
}

CoverPolicy::CoverPolicy(const QString &titleMarker)
    : m_titleMarker(titleMarker.isEmpty() ? defaultTitleMarker() : titleMarker)
{
}

QString CoverPolicy::defaultTitleMarker()
{
    return QStringLiteral("keel:cover");
}

QString CoverPolicy::appIdSuffix()
{
    return QStringLiteral(".keel-cover");
}

bool CoverPolicy::titleMatches(const QString &title) const
{
    if (title == m_titleMarker)
        return true;
    return title.startsWith(m_titleMarker + QLatin1Char(':'));
}

bool CoverPolicy::appIdMatches(const QString &appId)
{
    // The suffix alone (an empty reverse-DNS name) is not a valid app id.
    return appId.size() > appIdSuffix().size() && appId.endsWith(appIdSuffix());
}

bool CoverPolicy::isCover(const SurfaceInfo &info) const
{
    if (info.isChild())
        return false;
    return titleMatches(info.title) || appIdMatches(info.appId);
}

QString CoverPolicy::coverLabel(const QString &title) const
{
    const QString prefix = m_titleMarker + QLatin1Char(':');
    if (title.startsWith(prefix))
        return title.mid(prefix.size());
    return QString();
}

} // namespace keel
