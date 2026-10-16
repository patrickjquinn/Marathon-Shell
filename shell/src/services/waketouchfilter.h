#ifndef WAKETOUCHFILTER_H
#define WAKETOUCHFILTER_H

#include <QElapsedTimer>
#include <QObject>

/*
 * WakeTouchFilter
 *
 * Application-wide event filter (after lipstick's TouchScreen): for 100 ms
 * after the display wakes every touch is dropped, and from the screen going
 * off until a fresh touch begins, so a finger already down at wake, or the
 * tap that woke the screen, reaches nothing.
 */
class WakeTouchFilter : public QObject {
    Q_OBJECT

  public:
    static constexpr int BlockMs = 100;

    explicit WakeTouchFilter(QObject *parent = nullptr);

    void setScreenOn(bool on);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    QElapsedTimer m_sinceWake;
    bool          m_waitForBegin = false;
};

#endif
