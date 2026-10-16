#pragma once

#include <QAbstractAnimation>
#include <QElapsedTimer>
#include <QList>
#include <QObject>
#include <qqml.h>

class GestureTracker;

class GestureSettleAnimation : public QAbstractAnimation {
  public:
    explicit GestureSettleAnimation(GestureTracker *tracker);
    int duration() const override {
        return -1;
    }

  protected:
    void updateCurrentTime(int msecs) override;

  private:
    GestureTracker *m_tracker;
};

// One finger-driven quantity (px): tracks it while pressed, estimates its
// velocity from the last ~60 ms of samples, decides commit from distance
// plus projected velocity, and settles it with a velocity-seeded spring.
class GestureTracker : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal value READ value WRITE setValue NOTIFY valueChanged)
    Q_PROPERTY(qreal velocity READ velocity NOTIFY velocityChanged)
    Q_PROPERTY(qreal from READ from WRITE setFrom NOTIFY rangeChanged)
    Q_PROPERTY(qreal to READ to WRITE setTo NOTIFY rangeChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(qreal commitDistance READ commitDistance WRITE setCommitDistance NOTIFY
                   commitDistanceChanged)
    Q_PROPERTY(qreal flingVelocity READ flingVelocity WRITE setFlingVelocity NOTIFY
                   flingVelocityChanged)
    Q_PROPERTY(int settleDuration READ settleDuration WRITE setSettleDuration NOTIFY
                   settleDurationChanged)
    Q_PROPERTY(qreal dampingRatio READ dampingRatio WRITE setDampingRatio NOTIFY
                   dampingRatioChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool settling READ settling NOTIFY settlingChanged)
    Q_PROPERTY(bool willCommit READ willCommit NOTIFY willCommitChanged)

  public:
    struct Sample {
        qreal t; // ms
        qreal v;
    };
    struct SpringState {
        qreal offset;
        qreal velocity;
    };

    static constexpr qreal kVelocityWindowMs = 60;
    static constexpr qreal kStaleMs          = 80;
    static constexpr qreal kProjectionSec    = 0.1;

    static qreal       estimateVelocity(const QList<Sample> &samples, qreal nowMs);
    static bool        shouldCommit(qreal distance, qreal velocity, qreal commitDistance,
                                    qreal flingVelocity);
    static qreal       settleOmega(qreal offset, qreal velocity, qreal omega0, qreal zeta);
    static SpringState spring(qreal offset, qreal velocity, qreal omega, qreal zeta, qreal t);

    explicit GestureTracker(QObject *parent = nullptr);

    qreal value() const {
        return m_value;
    }
    void  setValue(qreal value);
    qreal velocity() const {
        return m_velocity;
    }
    qreal from() const {
        return m_from;
    }
    void  setFrom(qreal from);
    qreal to() const {
        return m_to;
    }
    void  setTo(qreal to);
    qreal progress() const;
    qreal commitDistance() const {
        return m_commitDistance;
    }
    void  setCommitDistance(qreal distance);
    qreal flingVelocity() const {
        return m_flingVelocity;
    }
    void setFlingVelocity(qreal velocity);
    int  settleDuration() const {
        return m_settleDuration;
    }
    void  setSettleDuration(int ms);
    qreal dampingRatio() const {
        return m_zeta;
    }
    void setDampingRatio(qreal zeta);
    bool active() const {
        return m_active;
    }
    bool settling() const {
        return m_settle.state() == QAbstractAnimation::Running;
    }
    bool willCommit() const {
        return m_willCommit;
    }

    // A press stops any settle where it is, so the finger picks the value up.
    Q_INVOKABLE void press();
    Q_INVOKABLE void move(qreal value);
    void             move(qreal value, qreal tMs);
    Q_INVOKABLE bool release();
    bool             release(qreal tMs);
    // shouldCommit with this tracker's thresholds, for a caller's own distance.
    Q_INVOKABLE bool decide(qreal distance, qreal velocity) const {
        return shouldCommit(distance, velocity, m_commitDistance, m_flingVelocity);
    }
    Q_INVOKABLE void settleTo(qreal target);
    Q_INVOKABLE void settleTo(qreal target, qreal velocity);
    Q_INVOKABLE void stop();

  signals:
    void valueChanged();
    void velocityChanged();
    void rangeChanged();
    void progressChanged();
    void commitDistanceChanged();
    void flingVelocityChanged();
    void settleDurationChanged();
    void dampingRatioChanged();
    void activeChanged();
    void settlingChanged();
    void willCommitChanged();
    void settled();

  private:
    friend class GestureSettleAnimation;

    qreal nowMs() const {
        return m_clock.nsecsElapsed() / 1e6;
    }
    qreal direction() const {
        return m_to >= m_from ? 1 : -1;
    }
    void writeValue(qreal value);
    void writeVelocity(qreal velocity);
    void setActive(bool active);
    void updateWillCommit();
    void step(int msecs);

    QElapsedTimer          m_clock;
    QList<Sample>          m_samples;
    GestureSettleAnimation m_settle;
    qreal                  m_value          = 0;
    qreal                  m_velocity       = 0;
    qreal                  m_from           = 0;
    qreal                  m_to             = 1;
    qreal                  m_commitDistance = 0;
    qreal                  m_flingVelocity  = 500;
    int                    m_settleDuration = 300;
    qreal                  m_zeta           = 1;
    bool                   m_active         = false;
    bool                   m_willCommit     = false;

    qreal m_target      = 0;
    qreal m_startOffset = 0;
    qreal m_startVel    = 0;
    qreal m_omega       = 0;
    bool  m_stopAtCross = false;
};
