#ifndef NAVIGATIONROUTERCPP_H
#define NAVIGATIONROUTERCPP_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class NavigationRouterCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentApp READ currentApp NOTIFY currentAppChanged)
    Q_PROPERTY(QString currentPage READ currentPage NOTIFY currentPageChanged)
    Q_PROPERTY(QVariantMap currentParams READ currentParams NOTIFY currentParamsChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)

  public:
    explicit NavigationRouterCpp(QObject *parent = nullptr);

    QString currentApp() const {
        return m_currentApp;
    }
    QString currentPage() const {
        return m_currentPage;
    }
    QVariantMap currentParams() const {
        return m_currentParams;
    }
    QVariantList history() const {
        return m_history;
    }

    Q_INVOKABLE bool navigate(const QString &uri);
    Q_INVOKABLE bool goBack();
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE bool navigateToDeepLink(const QString &appId, const QString &route,
                                        const QVariantMap &params = QVariantMap());

  signals:
    void navigated(const QString &uri);
    void navigationFailed(const QString &uri, const QString &error);
    void settingsNavigationRequested(const QString &page, const QString &subpage,
                                     const QVariantMap &params);
    void hubTabRequested(int tabIndex);
    void deepLinkRequested(const QString &appId, const QString &route, const QVariantMap &params);
    void currentAppChanged();
    void currentPageChanged();
    void currentParamsChanged();
    void historyChanged();

  private:
    struct ParsedUri {
        bool        valid = false;
        QString     app;
        QString     page;
        QString     subpage;
        QVariantMap params;
    };

    bool         navigateInternal(const QString &uri, bool recordHistory);
    ParsedUri    parseUri(const QString &uri) const;
    QVariantMap  buildHistoryEntry(const QString &uri, const ParsedUri &parsed) const;
    bool         handleHubRoute(const ParsedUri &parsed);
    bool         handleBrowserRoute(const ParsedUri &parsed);
    bool         handleAppRoute(const ParsedUri &parsed);
    void         setCurrentState(const ParsedUri &parsed);

    QString      m_currentApp;
    QString      m_currentPage;
    QVariantMap  m_currentParams;
    QVariantList m_history;
};

#endif
