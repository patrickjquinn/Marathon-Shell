#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

class SessionStore;
class UIStore;

// The app in front of the user: "" on the home screen, the switcher or the
// lock screen.
class ForegroundApp : public QObject {
    Q_OBJECT

  public:
    ForegroundApp(UIStore *ui, SessionStore *session, QObject *parent = nullptr);

    QString appId() const {
        return m_appId;
    }

  signals:
    void changed(const QString &appId);

  private:
    void     update();

    UIStore      *m_ui;
    // UIStore sets the app and the window open one at a time: only the
    // state they settle at is announced.
    QTimer        m_settle;
    SessionStore *m_session;
    QString       m_appId;
};
