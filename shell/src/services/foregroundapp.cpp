#include "foregroundapp.h"

#include "sessionstore.h"
#include "uistore.h"

ForegroundApp::ForegroundApp(UIStore *ui, SessionStore *session, QObject *parent)
    : QObject(parent)
    , m_ui(ui)
    , m_session(session) {
    m_settle.setSingleShot(true);
    m_settle.setInterval(0);
    connect(&m_settle, &QTimer::timeout, this, &ForegroundApp::update);
    const auto settle = [this]() { m_settle.start(); };
    connect(m_ui, &UIStore::appWindowOpenChanged, this, settle);
    connect(m_ui, &UIStore::currentAppIdChanged, this, settle);
    connect(m_session, &SessionStore::isLockedChanged, this, settle);
    update();
}

void ForegroundApp::update() {
    const QString appId =
        m_ui->appWindowOpen() && !m_session->isLocked() ? m_ui->currentAppId() : QString();
    if (appId == m_appId)
        return;
    m_appId = appId;
    emit changed(m_appId);
}
