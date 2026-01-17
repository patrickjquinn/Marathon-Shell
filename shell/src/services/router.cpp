#include "router.h"

#include <QDebug>
#include <QtGlobal>

Router::Router(QObject *parent)
    : QObject(parent) {}

void Router::goToHub() {
    logNavigation("current", "Hub", "direct");
    setPreviousPageIndex(m_currentPageIndex);
    setCurrentPageIndex(m_pageHub);
    emit navigateToHub();
}

void Router::goToFrames() {
    logNavigation("current", "ActiveFrames", "direct");
    setPreviousPageIndex(m_currentPageIndex);
    setCurrentPageIndex(m_pageFrames);
    emit navigateToFrames();
}

void Router::goToAppPage(int page) {
    logNavigation("current", QString("AppPage%1").arg(page), "direct");
    setPreviousPageIndex(m_currentPageIndex);
    setCurrentPageIndex(m_pageApps + page);
    emit navigateToApps(page);
}

void Router::goBack() {
    logNavigation("current", "previous", "back");
    const int previous = m_previousPageIndex;
    setPreviousPageIndex(m_currentPageIndex);
    setCurrentPageIndex(previous);
    emit navigateBack();
}

void Router::navigateLeft() {
    if (m_currentPageIndex >= 10) {
        return;
    }
    const int previous = m_currentPageIndex;
    setPreviousPageIndex(previous);
    setCurrentPageIndex(previous + 1);
    logNavigation(QString("page%1").arg(previous), QString("page%1").arg(m_currentPageIndex),
                  "swipeLeft");
}

void Router::navigateRight() {
    if (m_currentPageIndex <= 0) {
        return;
    }
    const int previous = m_currentPageIndex;
    setPreviousPageIndex(previous);
    setCurrentPageIndex(previous - 1);
    logNavigation(QString("page%1").arg(previous), QString("page%1").arg(m_currentPageIndex),
                  "swipeRight");
}

int Router::getCurrentPage() const {
    return m_currentPageIndex - m_pageApps;
}

void Router::navigateToSetting(const QString &settingId) {
    logNavigation("current", QString("Setting:%1").arg(settingId), "search");
    emit navigateToSettingPage(settingId);
}

void Router::setCurrentPageIndex(int index) {
    if (m_currentPageIndex == index) {
        return;
    }
    m_currentPageIndex = index;
    emit currentPageIndexChanged();
}

void Router::setPreviousPageIndex(int index) {
    if (m_previousPageIndex == index) {
        return;
    }
    m_previousPageIndex = index;
    emit previousPageIndexChanged();
}

void Router::logNavigation(const QString &from, const QString &to, const QString &method) {
    const QByteArray debugEnv = qgetenv("MARATHON_DEBUG").trimmed();
    if (!(debugEnv == "1" || debugEnv == "true")) {
        return;
    }
    qDebug().noquote() << "[NAV]" << from << "→" << to << "(" + method + ")";
}
