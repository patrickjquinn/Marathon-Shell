#include "unifiedsearchservicecpp.h"

#include "applaunchservice.h"
#include "appmodel.h"
#include "marathonappregistry.h"
#include "marathonappscanner.h"
#include "navigationroutercpp.h"
#include "settingsmanager.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QRegularExpression>

UnifiedSearchServiceCpp::UnifiedSearchServiceCpp(AppModel *appModel, MarathonAppRegistry *registry,
                                                 MarathonAppScanner  *scanner,
                                                 SettingsManager     *settings,
                                                 NavigationRouterCpp *router,
                                                 AppLaunchService *appLaunch, QObject *parent)
    : QObject(parent)
    , m_appModel(appModel)
    , m_registry(registry)
    , m_scanner(scanner)
    , m_settings(settings)
    , m_router(router)
    , m_appLaunch(appLaunch) {
    loadRecentSearches();

    if (m_scanner) {
        connect(m_scanner, &MarathonAppScanner::scanComplete, this,
                [this](int) { buildSearchIndex(); });
    }

    if (m_appModel) {
        connect(m_appModel, &AppModel::countChanged, this, [this]() { buildSearchIndex(); });
    }

    buildSearchIndex();
}

QVariantList UnifiedSearchServiceCpp::searchIndex() const {
    QVariantList out;
    out.reserve(m_items.size());
    for (const SearchItem &item : m_items)
        out.append(mapForItem(item, 0));
    return out;
}

QStringList UnifiedSearchServiceCpp::recentSearches() const {
    return m_recentSearches;
}

void UnifiedSearchServiceCpp::buildSearchIndex() {
    m_isIndexing = true;
    emit isIndexingChanged();
    m_items.clear();

    appendAppItems();
    appendDeepLinkItems();

    m_isIndexing = false;
    emit isIndexingChanged();
    emit searchIndexChanged();
    emit indexingComplete();
}

QVariantList UnifiedSearchServiceCpp::search(const QString &query) {
    const QString normalized = query.toLower().trimmed();
    if (normalized.isEmpty())
        return {};

    struct RankedResult {
        QVariantMap map;
        int         score;
    };

    QVector<RankedResult> ranked;
    ranked.reserve(m_items.size());

    for (const SearchItem &item : m_items) {
        const int score = computeScore(item, normalized);
        if (score <= 0)
            continue;

        ranked.push_back({mapForItem(item, score), score});
    }

    std::sort(ranked.begin(), ranked.end(), [](const RankedResult &a, const RankedResult &b) {
        if (a.score != b.score)
            return a.score > b.score;
        return a.map.value("title").toString() < b.map.value("title").toString();
    });

    QVariantList results;
    results.reserve(ranked.size());
    for (const RankedResult &entry : ranked)
        results.append(entry.map);

    emit searchCompleted(results);
    return results;
}

void UnifiedSearchServiceCpp::addToRecentSearches(const QString &query) {
    const QString normalized = query.trimmed();
    if (normalized.isEmpty())
        return;

    m_recentSearches.removeAll(normalized);
    m_recentSearches.prepend(normalized);
    while (m_recentSearches.size() > m_maxRecentSearches)
        m_recentSearches.removeLast();

    persistRecentSearches();
    emit recentSearchesChanged();
}

void UnifiedSearchServiceCpp::clearRecentSearches() {
    if (m_recentSearches.isEmpty())
        return;

    m_recentSearches.clear();
    persistRecentSearches();
    emit recentSearchesChanged();
}

void UnifiedSearchServiceCpp::executeSearchResult(const QVariantMap &result) {
    const QString     type = result.value("type").toString();
    const QVariantMap data = result.value("data").toMap();

    if (type == "app") {
        if (!m_appLaunch)
            return;
        QVariantMap appMap;
        appMap["id"]   = data.value("id");
        appMap["name"] = data.value("name");
        appMap["icon"] = data.value("icon");
        appMap["type"] = data.value("type", "marathon");
        m_appLaunch->launchApp(appMap);
        return;
    }

    if (type == "deeplink") {
        if (m_router)
            m_router->navigateToDeepLink(data.value("appId").toString(),
                                         data.value("route").toString(), {});
        return;
    }

    if (type == "setting") {
        emit settingRequested(result.value("id").toString());
    }
}

QVariantMap UnifiedSearchServiceCpp::mapForItem(const SearchItem &item, int score) const {
    QVariantMap map;
    map["type"]       = item.type;
    map["id"]         = item.id;
    map["appId"]      = item.appId;
    map["title"]      = item.title;
    map["subtitle"]   = item.subtitle;
    map["icon"]       = item.icon;
    map["keywords"]   = item.keywords;
    map["searchText"] = item.searchText;
    map["data"]       = item.data;
    map["score"]      = score;
    return map;
}

UnifiedSearchServiceCpp::SearchItem UnifiedSearchServiceCpp::itemForApp(QObject *app) const {
    SearchItem item;
    if (!app)
        return item;

    const QVariant idVar   = app->property("id");
    const QVariant nameVar = app->property("name");
    const QVariant iconVar = app->property("icon");
    const QVariant typeVar = app->property("type");

    const QString  appId   = idVar.toString();
    const QString  appName = nameVar.toString();
    const QString  appIcon = iconVar.toString();
    const QString  appType = typeVar.toString();

    item.type     = "app";
    item.id       = appId;
    item.title    = appName;
    item.subtitle = appType == "native" ? "Native App" : "Marathon App";
    item.icon     = appIcon;
    item.keywords = {appName.toLower(), appId.toLower()};

    const QStringList nameParts =
        appName.toLower().split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
    item.keywords.append(nameParts);

    item.searchText = appName.toLower() + " " + appId.toLower();
    item.data = QVariantMap{{"id", appId}, {"name", appName}, {"icon", appIcon}, {"type", appType}};
    return item;
}

void UnifiedSearchServiceCpp::appendAppItems() {
    if (!m_appModel)
        return;

    const int  count           = m_appModel->count();
    const bool indexNativeApps = shouldIndexNativeApp();
    for (int i = 0; i < count; ++i) {
        QObject *app = m_appModel->getAppAtIndex(i);
        if (!app)
            continue;

        const QString appType = app->property("type").toString();
        if (appType == "native" && !indexNativeApps)
            continue;

        SearchItem item = itemForApp(app);
        if (!item.title.isEmpty() && !item.id.isEmpty())
            m_items.push_back(item);
    }
}

void UnifiedSearchServiceCpp::appendDeepLinkItems() {
    if (!m_registry)
        return;

    const QStringList appIds = m_registry->getAllAppIds();
    for (const QString &appId : appIds) {
        const QVariantMap appData = m_registry->getApp(appId);
        if (!appData.value("id").isValid())
            continue;

        const QString appName       = appData.value("name").toString();
        const QString appIcon       = appData.value("icon").toString();
        const QString deepLinksJson = appData.value("deepLinks").toString();
        if (deepLinksJson.isEmpty())
            continue;

        const QJsonDocument doc = QJsonDocument::fromJson(deepLinksJson.toUtf8());
        if (!doc.isObject())
            continue;

        const QJsonObject obj = doc.object();
        for (auto it = obj.constBegin(); it != obj.constEnd(); ++it) {
            const QString route = it.key();
            if (!it.value().isObject())
                continue;

            const QJsonObject link = it.value().toObject();
            QStringList       keywords;
            const QJsonArray  keywordsArray = link.value("keywords").toArray();
            for (const QJsonValue &keyword : keywordsArray) {
                if (keyword.isString())
                    keywords.append(keyword.toString());
            }
            keywords.append(appName.toLower());
            keywords.append(route.toLower());

            SearchItem item;
            item.type       = "deeplink";
            item.id         = route;
            item.appId      = appId;
            item.title      = link.value("title").toString(route);
            item.subtitle   = link.value("description").toString(appName);
            item.icon       = appIcon.isEmpty() ? "qrc:/images/app-icon-placeholder.svg" : appIcon;
            item.keywords   = keywords;
            item.searchText = item.title.toLower() + " " + keywords.join(" ").toLower();
            item.data       = QVariantMap{{"appId", appId}, {"route", route}, {"appName", appName}};
            m_items.push_back(item);
        }
    }
}

bool UnifiedSearchServiceCpp::shouldIndexNativeApp() const {
    if (!m_settings)
        return true;
    return m_settings->searchNativeApps();
}

int UnifiedSearchServiceCpp::computeScore(const SearchItem &item, const QString &query) const {
    const QString title = item.title.toLower();
    int           score = 0;
    if (title == query)
        score = 10000;
    else if (title.startsWith(query))
        score = 5000;
    else if (item.keywords.contains(query))
        score = 3000;
    else {
        for (const QString &keyword : item.keywords) {
            if (keyword.startsWith(query)) {
                score = std::max(score, 2000);
                break;
            }
        }
    }

    if (score == 0 && title.contains(query))
        score = 1000;

    if (score == 0) {
        for (const QString &keyword : item.keywords) {
            if (keyword.contains(query))
                score = std::max(score, 500);
        }
    }

    if (score == 0) {
        const double fuzzy = fuzzyMatch(item.searchText, query);
        if (fuzzy > 0)
            score = int(fuzzy * 100);
    }

    if (score > 0 && item.type == "app")
        score += 100;

    return score;
}

double UnifiedSearchServiceCpp::fuzzyMatch(const QString &text, const QString &pattern) const {
    int patternIdx         = 0;
    int score              = 0;
    int consecutiveMatches = 0;

    for (int i = 0; i < text.size() && patternIdx < pattern.size(); ++i) {
        if (text.at(i) == pattern.at(patternIdx)) {
            score += 1 + consecutiveMatches * 2;
            ++consecutiveMatches;
            ++patternIdx;
        } else {
            consecutiveMatches = 0;
        }
    }

    if (patternIdx != pattern.size())
        return 0;

    return double(score) / double(pattern.size());
}

void UnifiedSearchServiceCpp::loadRecentSearches() {
    if (!m_settings)
        return;

    const QVariant raw = m_settings->get("search/recent", QVariantList());
    if (raw.canConvert<QStringList>()) {
        m_recentSearches = raw.toStringList();
        return;
    }

    if (raw.typeId() == QMetaType::QString) {
        const QJsonDocument doc = QJsonDocument::fromJson(raw.toString().toUtf8());
        if (!doc.isArray())
            return;
        const QJsonArray arr = doc.array();
        for (const QJsonValue &value : arr) {
            if (value.isString())
                m_recentSearches.append(value.toString());
        }
    }
}

void UnifiedSearchServiceCpp::persistRecentSearches() {
    if (!m_settings)
        return;
    m_settings->set("search/recent", m_recentSearches);
}
