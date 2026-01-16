#ifndef SESSIONSTORE_H
#define SESSIONSTORE_H

#include <QObject>
#include <QTimer>
#include <QString>

#include <qqml.h>

class SessionStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool isLocked READ isLocked WRITE setIsLocked NOTIFY isLockedChanged)
    Q_PROPERTY(bool isOnLockScreen READ isOnLockScreen WRITE setIsOnLockScreen NOTIFY
                   isOnLockScreenChanged)
    Q_PROPERTY(bool showLockScreen READ showLockScreen WRITE setShowLockScreen NOTIFY
                   showLockScreenChanged)
    Q_PROPERTY(bool isAnimatingLock READ isAnimatingLock WRITE setIsAnimatingLock NOTIFY
                   isAnimatingLockChanged)
    Q_PROPERTY(QString lockTransition READ lockTransition WRITE setLockTransition NOTIFY
                   lockTransitionChanged)

  public:
    explicit SessionStore(QObject *parent = nullptr);

    bool isLocked() const {
        return m_isLocked;
    }
    void setIsLocked(bool locked);

    bool isOnLockScreen() const {
        return m_isOnLockScreen;
    }
    void setIsOnLockScreen(bool onLockScreen);

    bool showLockScreen() const {
        return m_showLockScreen;
    }
    void setShowLockScreen(bool show);

    bool isAnimatingLock() const {
        return m_isAnimatingLock;
    }
    void    setIsAnimatingLock(bool animating);

    QString lockTransition() const {
        return m_lockTransition;
    }
    void             setLockTransition(const QString &transition);

    Q_INVOKABLE void lock();
    Q_INVOKABLE void unlock();
    Q_INVOKABLE bool checkSession() const;
    Q_INVOKABLE void showLock();
    Q_INVOKABLE void reset();

  signals:
    void isLockedChanged();
    void isOnLockScreenChanged();
    void showLockScreenChanged();
    void isAnimatingLockChanged();
    void lockTransitionChanged();

    void lockStateChanging(bool toLocked);
    void lockStateChanged(bool isLocked);
    void triggerShakeAnimation();
    void triggerUnlockAnimation();

  private:
    void    startLockTimer(bool targetLocked);

    bool    m_isLocked        = true;
    bool    m_isOnLockScreen  = false;
    bool    m_showLockScreen  = true;
    bool    m_isAnimatingLock = false;
    QString m_lockTransition;
    qint64  m_sessionValidUntil = 0;
    QTimer  m_lockTimer;
    bool    m_targetLocked = true;
};

#endif
