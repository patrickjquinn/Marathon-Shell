#include "gesturetracker.h"

#include <QtMath>

#include <algorithm>
#include <cmath>

namespace {
    constexpr qreal kEpsilon         = 0.5;  // px
    constexpr qreal kEpsilonVelocity = 10.0; // px/s
    // (1 + x)e^-x = 0.01: a critically damped spring at rest is within 1% of its
    // target after settleDuration.
    constexpr qreal kSettleFactor = 6.64;
    constexpr qreal kMaxOmegaGain = 4.0;
} // namespace

GestureSettleAnimation::GestureSettleAnimation(GestureTracker *tracker)
    : m_tracker(tracker) {}

void GestureSettleAnimation::updateCurrentTime(int msecs) {
    m_tracker->step(msecs);
}

qreal GestureTracker::estimateVelocity(const QList<Sample> &samples, qreal nowMs) {
    if (samples.size() < 2 || nowMs - samples.last().t > kStaleMs)
        return 0;
    const qreal windowStart = samples.last().t - kVelocityWindowMs;
    qsizetype   first       = samples.size() - 1;
    while (first > 0 && samples.at(first - 1).t >= windowStart)
        --first;
    if (first == samples.size() - 1)
        --first;

    const qsizetype n     = samples.size() - first;
    qreal           meanT = 0;
    qreal           meanV = 0;
    for (qsizetype i = first; i < samples.size(); ++i) {
        meanT += samples.at(i).t;
        meanV += samples.at(i).v;
    }
    meanT /= n;
    meanV /= n;
    qreal num = 0;
    qreal den = 0;
    for (qsizetype i = first; i < samples.size(); ++i) {
        const qreal dt = samples.at(i).t - meanT;
        num += dt * (samples.at(i).v - meanV);
        den += dt * dt;
    }
    return den > 1e-6 ? num / den * 1000 : 0;
}

bool GestureTracker::shouldCommit(qreal distance, qreal velocity, qreal commitDistance,
                                  qreal flingVelocity) {
    if (std::abs(velocity) >= flingVelocity)
        return velocity > 0 && distance > 0;
    return distance + velocity * kProjectionSec >= commitDistance;
}

// A critically damped spring released towards its target overshoots when
// the release is faster than the spring; stiffening it to |v / offset|
// makes it decay exactly from the finger's velocity instead.
qreal GestureTracker::settleOmega(qreal offset, qreal velocity, qreal omega0, qreal zeta) {
    if (zeta < 1 || offset * velocity >= 0 || offset == 0)
        return omega0;
    return std::clamp(std::abs(velocity / offset), omega0, omega0 * kMaxOmegaGain);
}

GestureTracker::SpringState GestureTracker::spring(qreal offset, qreal velocity, qreal omega,
                                                   qreal zeta, qreal t) {
    if (zeta >= 1) {
        const qreal b = velocity + omega * offset;
        const qreal e = std::exp(-omega * t);
        return {(offset + b * t) * e, (velocity - omega * b * t) * e};
    }
    const qreal alpha = zeta * omega;
    const qreal wd    = omega * std::sqrt(1 - zeta * zeta);
    const qreal c     = (velocity + alpha * offset) / wd;
    const qreal e     = std::exp(-alpha * t);
    const qreal cs    = std::cos(wd * t);
    const qreal sn    = std::sin(wd * t);
    return {e * (offset * cs + c * sn), e * (velocity * cs - (alpha * c + wd * offset) * sn)};
}

GestureTracker::GestureTracker(QObject *parent)
    : QObject(parent)
    , m_settle(this) {
    m_clock.start();
    connect(&m_settle, &QAbstractAnimation::stateChanged, this, &GestureTracker::settlingChanged);
}

void GestureTracker::setValue(qreal value) {
    stop();
    writeValue(value);
}

void GestureTracker::setFrom(qreal from) {
    if (m_from == from)
        return;
    const qreal old = progress();
    m_from          = from;
    emit rangeChanged();
    if (progress() != old)
        emit progressChanged();
    updateWillCommit();
}

void GestureTracker::setTo(qreal to) {
    if (m_to == to)
        return;
    const qreal old = progress();
    m_to            = to;
    emit rangeChanged();
    if (progress() != old)
        emit progressChanged();
    updateWillCommit();
}

qreal GestureTracker::progress() const {
    if (m_to == m_from)
        return 0;
    return std::clamp((m_value - m_from) / (m_to - m_from), 0.0, 1.0);
}

void GestureTracker::setCommitDistance(qreal distance) {
    if (m_commitDistance == distance)
        return;
    m_commitDistance = distance;
    emit commitDistanceChanged();
    updateWillCommit();
}

void GestureTracker::setFlingVelocity(qreal velocity) {
    if (m_flingVelocity == velocity)
        return;
    m_flingVelocity = velocity;
    emit flingVelocityChanged();
}

void GestureTracker::setSettleDuration(int ms) {
    if (m_settleDuration == ms)
        return;
    m_settleDuration = ms;
    emit settleDurationChanged();
}

void GestureTracker::setDampingRatio(qreal zeta) {
    zeta = std::clamp(zeta, 0.05, 1.0);
    if (m_zeta == zeta)
        return;
    m_zeta = zeta;
    emit dampingRatioChanged();
}

void GestureTracker::press() {
    stop();
    m_samples.clear();
    m_samples.append({nowMs(), m_value});
    setActive(true);
}

void GestureTracker::move(qreal value) {
    move(value, nowMs());
}

void GestureTracker::move(qreal value, qreal tMs) {
    if (!m_active) {
        stop();
        m_samples.clear();
        setActive(true);
    }
    writeValue(value);
    m_samples.append({tMs, value});
    while (m_samples.size() > 2 && m_samples.first().t < tMs - 4 * kVelocityWindowMs)
        m_samples.removeFirst();
    writeVelocity(estimateVelocity(m_samples, tMs));
}

bool GestureTracker::release() {
    return release(nowMs());
}

bool GestureTracker::release(qreal tMs) {
    writeVelocity(estimateVelocity(m_samples, tMs));
    m_samples.clear();
    setActive(false);
    const qreal dir = direction();
    return shouldCommit((m_value - m_from) * dir, m_velocity * dir, m_commitDistance,
                        m_flingVelocity);
}

void GestureTracker::settleTo(qreal target) {
    settleTo(target, m_velocity);
}

void GestureTracker::settleTo(qreal target, qreal velocity) {
    m_settle.stop();
    setActive(false);
    m_target      = target;
    m_startOffset = m_value - target;
    m_startVel    = velocity;
    if (std::abs(m_startOffset) < kEpsilon &&
        (m_zeta >= 1 || std::abs(velocity) < kEpsilonVelocity)) {
        writeValue(target);
        writeVelocity(0);
        emit settled();
        return;
    }
    const qreal omega0 = kSettleFactor * 1000 / std::max(1, m_settleDuration);
    m_omega            = settleOmega(m_startOffset, velocity, omega0, m_zeta);
    m_stopAtCross =
        m_zeta >= 1 && m_startOffset * velocity < 0 && std::abs(velocity / m_startOffset) > m_omega;
    m_settle.start();
}

void GestureTracker::stop() {
    if (!settling())
        return;
    m_settle.stop();
    writeVelocity(0);
}

void GestureTracker::step(int msecs) {
    const SpringState s       = spring(m_startOffset, m_startVel, m_omega, m_zeta, msecs / 1000.0);
    const bool        crossed = m_stopAtCross && s.offset * m_startOffset <= 0;
    const bool rested = std::abs(s.offset) < kEpsilon && std::abs(s.velocity) < kEpsilonVelocity;
    if (crossed || rested || msecs > 4 * m_settleDuration + 500) {
        m_settle.stop();
        writeValue(m_target);
        writeVelocity(0);
        emit settled();
        return;
    }
    writeValue(m_target + s.offset);
    writeVelocity(s.velocity);
}

void GestureTracker::writeValue(qreal value) {
    if (m_value == value)
        return;
    const qreal old = progress();
    m_value         = value;
    emit valueChanged();
    if (progress() != old)
        emit progressChanged();
    updateWillCommit();
}

void GestureTracker::writeVelocity(qreal velocity) {
    if (m_velocity == velocity)
        return;
    m_velocity = velocity;
    emit velocityChanged();
}

void GestureTracker::setActive(bool active) {
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
}

void GestureTracker::updateWillCommit() {
    const bool will = m_commitDistance > 0 && (m_value - m_from) * direction() >= m_commitDistance;
    if (m_willCommit == will)
        return;
    m_willCommit = will;
    emit willCommitChanged();
}
