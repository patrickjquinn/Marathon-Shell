#ifndef INPUTBOOST_H
#define INPUTBOOST_H

#include <QList>
#include <QObject>
#include <QTimer>

/*
 * InputBoost
 *
 * Raises every cpufreq policy's scaling_min_freq to its maximum while the
 * user is interacting, and restores it once input has been quiet for
 * kHoldMs. The shell is the compositor, so this application-wide event
 * filter sees every touch, including those headed for an app.
 *
 * Why: ondemand samples load every few ms and only ramps when a sample is
 * over up_threshold (95%). A frame's work is a short burst between idle
 * periods, so the clock stayed at 648-912 MHz during gestures and most
 * frames missed vblank on the PinePhone (20.7 ms median on a 14.4 ms
 * panel). Lowering up_threshold fixed gestures but held the top clock for
 * half of idle time. Boosting on input gives the performance-governor
 * result during interaction and stock ondemand power the rest of the time.
 *
 * Needs write access to scaling_min_freq, granted to the input group by
 * marathon-base-config's 60-marathon-cpufreq.rules. Without it the boost
 * is inert and logs once.
 */
class InputBoost : public QObject {
    Q_OBJECT

  public:
    explicit InputBoost(QObject *parent = nullptr);
    ~InputBoost() override;

    // Boost now and (re)start the hold timer.
    void boost();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    struct Policy {
        int        fd;
        QByteArray boostFreq;
        QByteArray restingFreq;
    };

    void write(bool boosted);

    QList<Policy> m_policies;
    QTimer        m_release;
    bool          m_boosted = false;
};

#endif // INPUTBOOST_H
