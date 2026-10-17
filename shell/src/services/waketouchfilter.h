#ifndef WAKETOUCHFILTER_H
#define WAKETOUCHFILTER_H

#include <QElapsedTimer>
#include <QObject>

/*
 * WakeTouchFilter
 *
 * Application-wide event filter (after lipstick's TouchScreen): a touch or
 * press that begins while the screen is off, or within 100 ms of it waking,
 * is dropped to its release, so a finger already down at wake, or the tap
 * that woke the screen, reaches nothing. Each sequence is kept or dropped
 * whole: a scene that saw a press always sees its release.
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
    bool          blocksPress() const;

    QElapsedTimer m_sinceWake;
    bool          m_screenOn = true;
    bool          m_dropping = false;
};

#endif
