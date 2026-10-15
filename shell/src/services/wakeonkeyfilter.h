#ifndef WAKEONKEYFILTER_H
#define WAKEONKEYFILTER_H

#include <QObject>
#include <QSet>

#include <functional>

/*
 * WakeOnKeyFilter
 *
 * Application-wide event filter (DeviceProfile WAKE_ON_KEY): while the screen
 * is off, a physical key press wakes it and is swallowed together with its
 * repeats and release, so no app or shell item sees it. Power/sleep keys pass
 * through to the power-key path. The shell is the compositor, so every
 * keyboard libinput reports, hotplugged ones included, reaches its window.
 */
class WakeOnKeyFilter : public QObject {
    Q_OBJECT

  public:
    WakeOnKeyFilter(std::function<bool()> screenOff, std::function<void()> wake,
                    QObject *parent = nullptr);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    std::function<bool()> m_screenOff;
    std::function<void()> m_wake;
    QSet<quint32>         m_swallowed;
};

#endif
