#pragma once

#include <QObject>
#include <QString>
#include <qqml.h>

class Router : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(int currentPageIndex READ currentPageIndex NOTIFY currentPageIndexChanged)
    Q_PROPERTY(int previousPageIndex READ previousPageIndex NOTIFY previousPageIndexChanged)
    Q_PROPERTY(int pageHub READ pageHub CONSTANT)
    Q_PROPERTY(int pageFrames READ pageFrames CONSTANT)
    Q_PROPERTY(int pageApps READ pageApps CONSTANT)

  public:
    explicit Router(QObject *parent = nullptr);

    int currentPageIndex() const {
        return m_currentPageIndex;
    }
    int previousPageIndex() const {
        return m_previousPageIndex;
    }
    int pageHub() const {
        return m_pageHub;
    }
    int pageFrames() const {
        return m_pageFrames;
    }
    int pageApps() const {
        return m_pageApps;
    }

    Q_INVOKABLE void goToHub();
    Q_INVOKABLE void goToFrames();
    Q_INVOKABLE void goToAppPage(int page);
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void navigateLeft();
    Q_INVOKABLE void navigateRight();
    Q_INVOKABLE int  getCurrentPage() const;
    Q_INVOKABLE void navigateToSetting(const QString &settingId);

  signals:
    void currentPageIndexChanged();
    void previousPageIndexChanged();
    void navigateToHub();
    void navigateToFrames();
    void navigateToApps(int appPage);
    void navigateBack();
    void navigateNext();
    void navigateToSettingPage(const QString &settingId);

  private:
    void      setCurrentPageIndex(int index);
    void      setPreviousPageIndex(int index);
    void      logNavigation(const QString &from, const QString &to, const QString &method);

    const int m_pageHub           = 0;
    const int m_pageFrames        = 1;
    const int m_pageApps          = 2;
    int       m_currentPageIndex  = 2;
    int       m_previousPageIndex = 2;
};
