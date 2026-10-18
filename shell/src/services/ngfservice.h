#pragma once

#include <QHash>
#include <QObject>
#include <QVariantMap>
#include <functional>

class QTimer;

// The ngfd D-Bus API (com.nokia.NonGraphicFeedback1) that Nemo.Ngf, and so
// Silica's pulley menus, call; events become vibration patterns.
class NgfService : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "com.nokia.NonGraphicFeedback1")

  public:
    enum State : quint8 { Failed = 0, Completed = 1, Playing = 2, Paused = 3 };

    using Vibrate = std::function<void(const QList<int> &pattern)>;
    using StopVibration = std::function<void()>;

    NgfService(Vibrate vibrate, StopVibration stop, QObject *parent = nullptr);

  public slots:
    quint32 Play(const QString &event, const QVariantMap &properties);
    bool    Pause(quint32 id, bool pause);
    bool    Stop(quint32 id);

  signals:
    void Status(quint32 id, quint32 state);

  private:
    void finish(quint32 id, State state);

    Vibrate                   m_vibrate;
    StopVibration             m_stop;
    quint32                   m_nextId = 1;
    QHash<quint32, QTimer *>  m_playing;
};
