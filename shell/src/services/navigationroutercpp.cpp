#include "navigationroutercpp.h"

#include <QDateTime>
#include <QUrl>
#include <QUrlQuery>

NavigationRouterCpp::NavigationRouterCpp(QObject *parent)
    : QObject(parent) {}

bool NavigationRouterCpp::navigate(const QString &uri) {
    return navigateInternal(uri, true);
}

bool NavigationRouterCpp::goBack() {
    if (m_history.size() <= 1)
        return false;

    m_history.removeLast();
    emit              historyChanged();

    const QVariantMap previous = m_history.last().toMap();
    const QString     uri      = previous.value("uri").toString();
    return navigateInternal(uri, false);
}

void NavigationRouterCpp::clearHistory() {
    if (m_history.isEmpty())
        return;

    m_history.clear();
    emit historyChanged();
    m_currentApp.clear();
    m_currentPage.clear();
    m_currentParams.clear();
    emit currentAppChanged();
    emit currentPageChanged();
    emit currentParamsChanged();
}

bool NavigationRouterCpp::navigateToDeepLink(const QString &appId, const QString &route,
                                             const QVariantMap &params) {
    if (appId.isEmpty())
        return false;

    emit deepLinkRequested(appId, route, params);
    return true;
}

bool NavigationRouterCpp::navigateInternal(const QString &uri, bool recordHistory) {
    ParsedUri parsed = parseUri(uri);
    if (!parsed.valid) {
        const QString error = QStringLiteral("Invalid URI format: %1").arg(uri);
        emit          navigationFailed(uri, error);
        return false;
    }

    if (recordHistory) {
        m_history.append(buildHistoryEntry(uri, parsed));
        emit historyChanged();
    }

    setCurrentState(parsed);

    if (parsed.app == "hub")
        return handleHubRoute(parsed);
    if (parsed.app == "browser")
        return handleBrowserRoute(parsed);
    return handleAppRoute(parsed);
}

NavigationRouterCpp::ParsedUri NavigationRouterCpp::parseUri(const QString &uri) const {
    ParsedUri  result;
    const QUrl url(uri);
    if (!url.isValid() || url.scheme() != "marathon")
        return result;

    const QStringList parts = url.path().split('/', Qt::SkipEmptyParts);
    if (parts.isEmpty())
        return result;

    result.valid   = true;
    result.app     = parts.value(0);
    result.page    = parts.value(1);
    result.subpage = parts.value(2);

    QUrlQuery  query(url);
    const auto items = query.queryItems();
    for (const auto &item : items)
        result.params.insert(item.first, item.second);

    return result;
}

QVariantMap NavigationRouterCpp::buildHistoryEntry(const QString   &uri,
                                                   const ParsedUri &parsed) const {
    QVariantMap entry;
    entry.insert("uri", uri);
    entry.insert("app", parsed.app);
    entry.insert("page", parsed.page);
    entry.insert("params", parsed.params);
    entry.insert("timestamp", QDateTime::currentMSecsSinceEpoch());
    return entry;
}

bool NavigationRouterCpp::handleHubRoute(const ParsedUri &parsed) {
    if (parsed.page == "messages")
        emit hubTabRequested(0);
    else if (parsed.page == "notifications")
        emit hubTabRequested(1);
    else if (parsed.page == "calendar")
        emit hubTabRequested(2);

    emit navigated(QStringLiteral("marathon://hub/%1").arg(parsed.page));
    return true;
}

bool NavigationRouterCpp::handleBrowserRoute(const ParsedUri &parsed) {
    QVariantMap params;
    params.insert("url", parsed.params.value("url").toString());
    emit deepLinkRequested("browser", "", params);
    emit navigated(QStringLiteral("marathon://browser"));
    return true;
}

bool NavigationRouterCpp::handleAppRoute(const ParsedUri &parsed) {
    emit deepLinkRequested(parsed.app, "", QVariantMap());
    emit navigated(QStringLiteral("marathon://%1").arg(parsed.app));
    return true;
}

void NavigationRouterCpp::setCurrentState(const ParsedUri &parsed) {
    if (m_currentApp != parsed.app) {
        m_currentApp = parsed.app;
        emit currentAppChanged();
    }
    if (m_currentPage != parsed.page) {
        m_currentPage = parsed.page;
        emit currentPageChanged();
    }
    m_currentParams = parsed.params;
    emit currentParamsChanged();
}
