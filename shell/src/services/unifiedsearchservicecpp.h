#ifndef UNIFIEDSEARCHSERVICECPP_H
#define UNIFIEDSEARCHSERVICECPP_H

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class AppModel;
class MarathonAppRegistry;
class MarathonAppScanner;
class SettingsManager;
class NavigationRouterCpp;
class AppLaunchService;

class UnifiedSearchServiceCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList searchIndex READ searchIndex NOTIFY searchIndexChanged)
    Q_PROPERTY(QStringList recentSearches READ recentSearches NOTIFY recentSearchesChanged)
    Q_PROPERTY(bool isIndexing READ isIndexing NOTIFY isIndexingChanged)
    Q_PROPERTY(int maxRecentSearches READ maxRecentSearches CONSTANT)

  public:
    explicit UnifiedSearchServiceCpp(AppModel *appModel, MarathonAppRegistry *registry,
                                     MarathonAppScanner *scanner, SettingsManager *settings,
                                     NavigationRouterCpp *router, AppLaunchService *appLaunch,
                                     QObject *parent = nullptr);

    QVariantList searchIndex() const;
    QStringList  recentSearches() const;
    bool         isIndexing() const {
        return m_isIndexing;
    }
    int maxRecentSearches() const {
        return m_maxRecentSearches;
    }

    Q_INVOKABLE void         buildSearchIndex();
    Q_INVOKABLE QVariantList search(const QString &query);
    Q_INVOKABLE void         addToRecentSearches(const QString &query);
    Q_INVOKABLE void         clearRecentSearches();
    Q_INVOKABLE void         executeSearchResult(const QVariantMap &result);

  signals:
    void searchIndexChanged();
    void recentSearchesChanged();
    void isIndexingChanged();
    void searchCompleted(const QVariantList &results);
    void indexingComplete();
    void settingRequested(const QString &settingId);

  private:
    struct SearchItem {
        QString     type;
        QString     id;
        QString     appId;
        QString     title;
        QString     subtitle;
        QString     icon;
        QStringList keywords;
        QString     searchText;
        QVariantMap data;
    };

    QVariantMap          mapForItem(const SearchItem &item, int score) const;
    SearchItem           itemForApp(QObject *app) const;
    void                 appendAppItems();
    void                 appendDeepLinkItems();
    bool                 shouldIndexNativeApp() const;
    int                  computeScore(const SearchItem &item, const QString &query) const;
    double               fuzzyMatch(const QString &text, const QString &pattern) const;
    void                 loadRecentSearches();
    void                 persistRecentSearches();

    AppModel            *m_appModel  = nullptr;
    MarathonAppRegistry *m_registry  = nullptr;
    MarathonAppScanner  *m_scanner   = nullptr;
    SettingsManager     *m_settings  = nullptr;
    NavigationRouterCpp *m_router    = nullptr;
    AppLaunchService    *m_appLaunch = nullptr;

    QVector<SearchItem>  m_items;
    QStringList          m_recentSearches;
    bool                 m_isIndexing        = false;
    int                  m_maxRecentSearches = 10;
};

#endif
